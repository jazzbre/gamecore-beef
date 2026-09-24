# GameCore NGA

The `NGA` branch uses `NoGraphicsAPI-beef` directly from Beef and targets DX12 on Windows x64. GameCore has no C/C++ bridge or CMake build. ImGui uses the sibling `imgui-nga-beef` project and shares GameCore's descriptor heaps.

## Build

Build the native libraries in the sibling dependencies first, including the DX12 branch of `NoGraphicsAPI-beef` and the `NGA` branch of `imgui-nga-beef`. From this repository root, build with Beef, then run from `example/` with Slang (`slangc`) on PATH:

```bat
beefbuild -config=Debug -platform=Win64
cd example
..\build\Debug_Win64\example\example.exe --smoke-test
```

Use `-config=Release` for Release. Building Beef does not compile assets. The example uses its current working directory as the resource root. Run it from `example/`; the IDE working directory is already set to that project directory. The smoke test reads pixels back from the GPU and checks meshes, command buffer submission order, depth, texture sampling, debug lines, skinning, sprites, alpha blending, resize, and pipeline cache reuse.

The interactive example acquires its triangle, screen, and text command buffers on the main thread, records and finishes them in three reusable jobs, then joins and submits in that order. ImGui remains on the main thread, and the text job owns a separate sprite batcher. The scheduler may also execute pending jobs on the main thread while it joins. The example draws Valmore text above the triangle through `Font.RenderText`. Its `.fnt` and PNG atlas are copied from Bramorr into `example/buildtime/resources/fonts/` and built into hashed runtime assets on startup. The font atlas uses the existing `texturec` tool. The smoke test also compares rendered text pixels against the atlas glyphs. Use `--headless-smoke-test` from the same directory to run the offscreen GPU checks without a window or presentation/VSync.

## Rendering

Initialize an SDL window, then call `RenderManager.InitializeDevice(ImGui.NgaGetNativeWindow(window))`. Create an ImGui context and call `RenderManager.InitializeImGui(window)` if needed. The example shows complete initialization and cleanup.

Acquire a `RenderCommandBuffer` from `RenderManager` on the main thread for each camera render or other ordered pass. Pass its fixed render target at acquisition, then set matrices, viewport, and clear operations before recording. `AcquireCommandBuffer(null)` creates a compute/transfer-only buffer; `AcquireSwapchainCommandBuffer(name)` binds the current swapchain image. Camera does not own command buffers.

```beef
var commands = RenderManager.AcquireCommandBuffer(target, "Main camera");
commands.View = viewMatrix;
commands.Projection = projectionMatrix;
commands.ClearColorBuffer = true;
commands.ClearDepthBuffer = true;
mesh.Render(commands, worldMatrix, shader, textures);
commands.Finish();
RenderManager.SubmitCommandBuffer(commands);
RenderManager.Frame();
```

`SubmitCommandBuffer` queues a finished native list in explicit execution order. Recording/acquisition order does not determine submission order. `Frame(overlay)` adds barriers between those lists from their resource-access summaries, adds swapchain and optional ImGui work, submits, and presents. Draws, dispatches, and transfers are recorded immediately by their recording thread; `Frame` does not replay them. It does not wait for the submitted frame. Three frame slots retain command pools, upload pages, transfer scratch memory, and retired resources. Reusing a slot waits for its GPU timeline point before returning its buffers to the available pool. The frame count alone never authorizes reuse.

Acquire buffers every frame; do not retain, delete, mutate, or record into them after submission. After joining workers, call `CancelCommandBuffer` on the main thread for unused recordings or finished buffers. Every acquired buffer must be submitted or cancelled before `Frame`. `WaitForIdle` drains submitted frames; it does not submit outstanding recordings. Shutdown also drains GPU work.

Each acquired buffer owns a native command pool/list, upload pages, scratch memory, pipeline cache, and local dependency tracker. Acquire all buffers on the main thread, fork jobs that record distinct buffers, call `Finish()` on each recording thread, join those jobs, then submit on the main thread. `Finish` closes the native list and returns whether pipeline creation succeeded; submission requires its `Executable` state. The first recording operation claims the buffer's thread ownership. Shader time and spherical harmonics are copied at acquisition.

Shared sampler and mip-descriptor caches use short locks; recording itself has no shared render lock. Resource-access summaries contain dependency metadata only. The example's `ParallelRecordingChecks` records graphics consumers before compute producers in jobs, submits producers first, and checks GPU pixels across four frames. It also verifies native lists, pipelines, and draw/dispatch counts exist before submission.

Set clear options before the first draw, dispatch, or transfer; attachments clear once per buffer. Keep shaders, textures, buffers, and render targets stable while jobs record and until their frame is submitted. Load/reload resources and resize targets outside that interval. Shared sprite/debug batchers need separate instances or serial use. Acquisition, cancellation, submission, frame management, and ImGui remain on the main thread.

Rendering uses `RenderState` with NGA blend, rasterization, and depth/stencil structures, plus NGA `SamplerDesc` and `Format` values. `GpuBuffer` and `GpuTexture` own NGA allocations; `RenderTexture` owns its attachment textures. Draw data and custom parameter blocks are copied into the command buffer's reusable upload pages. Shader programs and render targets must remain alive until their queued frame has been submitted. Buffer and texture destruction defers the GPU allocation release until frame completion.

`PipelineCache` is an instance-owned class. Each pooled `RenderCommandBuffer` owns one; no static cache or shared pipeline dictionary is involved. A cache belongs to one device and one recording owner. Its key includes shader identity, attachment count and ordered formats, blending, write mask, culling, and depth bias. Depth/stencil testing is applied dynamically with NGA. Submit recorded commands before clearing or destroying a cache, and keep the device alive until after its caches are destroyed.

Destroy application resources before shutting down the renderer. Finalize ImGui before `RenderManager.ShutdownDevice()`. Call `RenderManager.Finalize()` when using its shared sprite buffers and resources. Complete resource-loading jobs before shutdown.

## Multiple render targets

A `RenderTexture` can own up to eight color attachments and one shared depth attachment. Pass an ordered format span to its constructor, then acquire and record its command buffer normally:

```beef
Format[2] formats = .(.rgba8_unorm, .rgba16_float);
var target = scope RenderTexture(128, 128, Span<Format>(&formats[0], 2), .d24_unorm_s8_uint);
var commands = RenderManager.AcquireCommandBuffer(target, "G-buffer");
commands.ClearColorBuffer = true;
commands.ClearDepthBuffer = true;
// Record draws using a shader with SV_Target0 and SV_Target1 outputs.
commands.Finish();
RenderManager.SubmitCommandBuffer(commands);
```

`GetColorTexture(index)` exposes each texture for sampling, compute reads, or readback. `ColorAttachmentCount` and `GetColorFormat(index)` describe the ordered attachments. The existing `TextureHandle` and `ColorFormat` refer to attachment zero, and the single-format constructor is unchanged. Resize recreates every attachment at the same extent; do it outside command recording, as with single targets.

`ClearColorBuffer` and `ClearColor` apply to all color attachments. The draw's blend state and color write mask also apply to all attachments; independent per-attachment settings are not exposed yet. Pipeline keys include attachment count, ordered formats, shared blend/write state, depth format, and rasterization state. Every attachment participates in dependency tracking, and reopening a pass preserves its contents.

The interactive example records a two-output shader in its triangle job and displays both attachments in ImGui. `MultipleTargetChecks` verifies mixed RGBA8/RGBA16F outputs, shared depth, reopening after transfer work, sampling attachment one from another command buffer, resizing, and pipeline keys.

## Shaders and resources

Shader sources are native `.slang` files with `vertexMain` and `fragmentMain` entry points. `example/buildtime/resources/shaders/gamecore.slang` defines the vertex-pulling and draw-data layout used by the Beef renderer. Custom data is supplied through the draw's `parameters` span; the CRT renderer is an example of a typed parameter block.

An optional adjacent `.slang.json` file specifies named variants, defines, and optional `vertex`/`fragment` entry points, or a `compute` entry point. `ShaderBuilder` handles manifests, recursive include checks, and binary packaging. `Dx12ShaderCompiler` invokes Slang and validates DXIL. Additional backends can implement `ShaderCompiler` and be selected in `ShaderBuilder.SelectCompiler`; only DX12 is implemented now. Graphics packages remain compatible. A compute variant uses an empty first stage followed by its compute DXIL container. Compute and graphics stages cannot share a variant.

`ShaderBuilder.BuildFile` accepts an optional compiler instance. `NeedsBuild` checks source, includes, manifest, and the builder executable timestamp. Builder instances reuse their buffers and should have one owner at a time. Compilation failures leave the previous package intact.

Applications keep source assets under `buildtime/resources/` and generated files under `runtime/resources/`. For example, `buildtime/resources/shaders/example.slang` is registered as `shaders/example` and compiled to `runtime/resources/<hash>.Direct3D12.shader`. `resources.json` records the names and hashes using the existing resource format.

At application startup, initialize the job system and call `ResourceManager.Initialize` with the application root and loose resources enabled. With `RESOURCEBUILD`, it checks sources and builds missing or outdated assets. Load shaders through `ResourceManager.GetResource<Shader>("shaders/example")`. Call `ResourceManager.Update(false)` each frame to process source changes. Variant manifests belong to their shader and do not become separate JSON resources. Failed builds keep the last successful shader loaded.

The example's font, mesh/skinning, debug, fullscreen, and CRT shader sources are under `example/buildtime/resources/shaders/`, and its generated assets go to `example/runtime/resources/`. `gamecore.slang` lives beside the shaders and is treated as a shared include, not a standalone resource. CRT shaders include it through `../gamecore.slang`. Changes to it recheck the registered shaders. Only NGA's platform-header directory is passed as a compiler include path. The optional `dependencyRoot` argument to `ResourceManager.Initialize` identifies the directory containing sibling library repositories; the default remains the parent of the application root, as used by Bramorr. The nested example passes its dependency root explicitly. Without buildtime sources, the resource manager loads the existing runtime resource list and hashed files.

Texture loading supports the RGBA8 KTX1 assets produced by the existing texture builder, including mip chains. The existing offline texture/model builders still invoke `texturec` and `geometryc` from the sibling BGFX tools directory; BGFX is no longer a runtime or link dependency.

Bramorr's callers still need migration from indexed views to acquired command buffers.

## Compute and volume textures

A compute manifest uses `{"variants":[{"name":"Default","compute":"computeMain"}]}`. Slang entry points declare their thread group size with `[numthreads(x,y,z)]`. `RenderManager.Dispatch(commandBuffer, shader, variantIndex, groups, parameters)` snapshots the parameter bytes and uses the same `DrawRoot`/`DrawConstants` layout as graphics. The compiler defines exactly one of `GAMECORE_STAGE_VERTEX`, `GAMECORE_STAGE_FRAGMENT`, or `GAMECORE_STAGE_COMPUTE` for stage-specific source sections. Shared `.slangh` files trigger dependency checks without becoming resources.

Buffers execute in `SubmitCommandBuffer` order. Within each buffer, draws, dispatches, uploads, copies, and readbacks retain recording order. Draw passes reopen with attachment loading after compute or transfer work; clear operations run once per buffer. Resource dependencies determine where barriers are required; independent declared operations and repeated reads avoid unconditional barriers. `PipelineCache` owns both graphics and compute pipelines.

`GpuTexture` accepts NGA texture type, depth, mip count, and physical layer count. A cube defaults to six face layers; cube-array layer counts must be multiples of six. Initial pixels contain mip levels in order, with all physical layers tightly packed within each level. `GetMipDescriptor(mip, writable)` provides a sampled or storage descriptor for one level. Writable descriptors require `.storage` usage. `Update(commandBuffer, pixels, region)` records a partial update using NGA's `TextureCopyDesc` offsets and pitches.

Use `GpuBuffer.CreateStorage(byteCount)` for GPU-writable data and `buffer.Update(commandBuffer, bytes, offset)` for ordered uploads to it. `RenderManager.CopyTexture` records a copy between matching formats and byte counts. `TextureReadback(commandBuffer, texture, region)` records a readback; poll `Ready` and use `CopyTo` after its frame has been reclaimed, or call `WaitForIdle` first. A cancelled command buffer marks its requests `Cancelled`; later reuse cannot make them ready. Deleting a pending request cancels CPU consumption and defers its GPU allocation release. `RenderManager.ReadTexture` is the immediate alternative when no commands are queued, and accepts a mip level. Destroy readback requests before device shutdown.

`InitializeDevice(null)` supports offscreen execution without acquiring or presenting a swapchain. The same frame pool and fence-based recycling apply.

Enable `RenderManager.ProfilingEnabled` before acquiring the first buffer of the frame to collect GPU timings. `RenderManager.GpuMilliseconds` measures the complete GPU frame from the first frame command through the ImGui overlay, including gaps between command buffers. Upload batches and presentation/VSync are outside that interval. `HasGpuTiming` distinguishes a valid measurement from profiling being disabled or unavailable. `DrawCount` and `TriangleCount` describe the most recently reclaimed frame.

`CommandBufferTimingCount` and `GetCommandBufferTiming(index)` expose that frame's buffers in submission order, with copied names, GPU durations, validity flags, draw counts, and triangle counts. Results correspond to `CompletedFrame`, appear only after its fence completes, and add no readback wait. Result objects are reused when another frame completes; copy values if retaining history. Buffer objects still expose their own completed duration, but callers should use the manager's results after submitting buffers. The example displays frame and per-buffer timings in its ImGui window.

`InitializeDevice(nativeWindow, textureDescriptorCapacity: 8192)` defaults to 8,192 GameCore texture descriptors, plus a separate 256 entries for ImGui. Capacity must be between 1 and 32,512 to stay below NGA's internal buffer descriptor range; invalid capacities return `false`. `RenderManager.TextureDescriptorCapacity` exposes the configured capacity.

## Uploads and synchronization

Texture creation, initial pixel uploads, and render-target clears are queued into reusable upload batches. `Frame` flushes those batches before rendering on the same graphics queue, so consumers see uploaded data without a CPU wait. `FlushUploads()` submits pending work and returns its timeline point; it does not wait. Three upload pools retain their staging pages until their fences complete. A batch flushes before the next resource operation after reaching 16 MiB of staging data; reusing a busy upload pool can wait. Large individual textures can exceed that threshold.

`ReadTexture` is explicitly synchronous: it flushes pending uploads, submits the copy, and waits for that queue point. Use `TextureReadback` in an acquired command buffer for asynchronous consumption. `WaitForIdle` flushes uploads and drains submitted work. Device shutdown and explicit pipeline-cache clearing still wait for safe destruction.

GameCore tracks texture and buffer dependencies across commands, buffers, and frames. Built-in draws declare their texture/vertex/index reads, and transfers and attachments are tracked automatically. For compute shaders or custom parameter blocks containing resource references, declare every accessed resource before each draw/dispatch:

```beef
commands.UseBuffer(storageBuffer, .compute, .shader_read);
commands.UseTexture(outputTexture, .compute, .shader_write);
RenderManager.Dispatch(commands, shader, variant, groups, parameters,
    storage: storageBuffer.Memory.range.gpu);
```

Declarations apply to the next shader command, and must include indirect accesses through custom GPU pointers/descriptors. Declare read/write access for in-place compute updates. Complete declarations are mandatory: missing an access can cause incorrect synchronization, and GameCore cannot detect resources hidden in arbitrary shader pointers or descriptors. Direct `RenderCommandBuffer.Draw` declares vertex/index reads automatically; callers must declare any other referenced resources. Immutable data copied into the command buffer with `Upload` needs no declaration because it has no GPU writer and remains alive until completion. ImGui overlay callbacks retain internal conservative barriers before their work and before the next tracked operation because their resource accesses are external to GameCore.

Tracking is at whole-texture/whole-buffer granularity; independent mip levels are conservatively treated as overlapping. NGA currently exposes only global memory barriers. GameCore uses resource histories to omit unnecessary barriers and narrow stage/access masks, but it cannot issue resource-scoped native barriers through that API. Native attachment layout transitions remain NGA's responsibility. This path is validated on DX12 only; it does not implement multiple GPU queues or Vulkan validation.

`RenderManager.Synchronization` reports cumulative upload submissions/bytes, explicit barrier counts, external fallback barrier counts, and actual blocking fence waits split into frame reuse, upload reuse, immediate readback, and explicit draining. `CpuWaitMilliseconds` measures these fence waits only; it excludes presentation, driver allocation, and shader/pipeline compilation. Counters cover GameCore's explicit barriers, not NGA's internal transitions. The headless checks verify that 64 draws with and without custom parameter bytes avoid per-draw barriers; timings are diagnostic samples rather than a stable benchmark.
