# GameCore NGA

The `NGA` branch uses `NoGraphicsAPI-beef` directly from Beef and targets DX12 on Windows x64. GameCore has no C/C++ bridge or CMake build. ImGui uses the sibling `imgui-nga-beef` project and shares GameCore's descriptor heaps.

## Build

Build the native libraries in the sibling dependencies first, including the DX12 branch of `NoGraphicsAPI-beef` and the `NGA` branch of `imgui-nga-beef`. From this repository root, build with Beef, then run from `example/` with Slang (`slangc`) on PATH:

```bat
beefbuild -config=Debug -platform=Win64
cd example
..\build\Debug_Win64\example\example.exe --smoke-test
```

Use `-config=Release` for Release. Building Beef does not compile assets. The example uses its current working directory as the resource root. Run it from `example/`; the IDE working directory is already set to that project directory. The smoke test reads pixels back from the GPU and checks meshes, ordered views, depth, texture sampling, debug lines, skinning, sprites, alpha blending, resize, and pipeline cache reuse.

The example draws Valmore text above the triangle through `Font.RenderText`. Its `.fnt` and PNG atlas are copied from Bramorr into `example/buildtime/resources/fonts/` and built into hashed runtime assets on startup. The font atlas uses the existing `texturec` tool. The smoke test also compares rendered text pixels against the atlas glyphs.

## Rendering

Initialize an SDL window, then call `RenderManager.InitializeDevice(ImGui.NgaGetNativeWindow(window))`. Create an ImGui context and call `RenderManager.InitializeImGui(window)` if needed. The example shows complete initialization and cleanup.

`RenderManager.GetView(id)` exposes a view's target, matrices, viewport, and clear operations. Mesh, sprite, model, and debug renderers enqueue complete draw records. `RenderManager.Frame(overlay)` records those views in ascending ID order using NGA commands, optionally renders ImGui, submits, and presents. The initial implementation waits for each frame to complete before recycling its upload pages and retired resources.

Rendering uses `RenderState` with NGA blend, rasterization, and depth/stencil structures, plus NGA `SamplerDesc` and `Format` values. `GpuBuffer` and `GpuTexture` own NGA allocations; `RenderTexture` owns its attachment textures. Draw data and custom parameter blocks are copied into the context's reusable upload pages. Shader programs and render targets must remain alive until their queued frame has been submitted. Buffer and texture destruction defers the GPU allocation release until frame completion.

`PipelineCache` is an instance-owned class. Each `RenderContext` owns one. A future recording worker can own a separate cache/context; no static cache or shared pipeline dictionary is involved. A cache belongs to one device and one recording owner. Its key includes shader identity, attachment formats, blending, write mask, culling, and depth bias. Depth/stencil testing is applied dynamically with NGA. Submit recorded commands before clearing or destroying a cache, and keep the device alive until after its caches are destroyed.

Destroy application resources before shutting down the renderer. Finalize ImGui before `RenderManager.ShutdownDevice()`. Call `RenderManager.Finalize()` when using its shared sprite buffers and resources. Complete resource-loading jobs before shutdown.

## Shaders and resources

Shader sources are native `.slang` files with `vertexMain` and `fragmentMain` entry points. `example/buildtime/resources/shaders/gamecore.slang` defines the vertex-pulling and draw-data layout used by the Beef renderer. Custom data is supplied through the draw's `parameters` span; the CRT renderer is an example of a typed parameter block.

An optional adjacent `.slang.json` file specifies named variants, defines, and optional `vertex`/`fragment` entry points. `ShaderBuilder` handles manifests, recursive include checks, and binary packaging. `Dx12ShaderCompiler` invokes Slang and validates DXIL. Additional backends can implement `ShaderCompiler` and be selected in `ShaderBuilder.SelectCompiler`; only DX12 is implemented now. The `.Direct3D12.shader` format is unchanged.

`ShaderBuilder.BuildFile` accepts an optional compiler instance. `NeedsBuild` checks source, includes, manifest, and the builder executable timestamp. Builder instances reuse their buffers and should have one owner at a time. Compilation failures leave the previous package intact.

Applications keep source assets under `buildtime/resources/` and generated files under `runtime/resources/`. For example, `buildtime/resources/shaders/example.slang` is registered as `shaders/example` and compiled to `runtime/resources/<hash>.Direct3D12.shader`. `resources.json` records the names and hashes using the existing resource format.

At application startup, initialize the job system and call `ResourceManager.Initialize` with the application root and loose resources enabled. With `RESOURCEBUILD`, it checks sources and builds missing or outdated assets. Load shaders through `ResourceManager.GetResource<Shader>("shaders/example")`. Call `ResourceManager.Update(false)` each frame to process source changes. Variant manifests belong to their shader and do not become separate JSON resources. Failed builds keep the last successful shader loaded.

The example's font, mesh/skinning, debug, fullscreen, and CRT shader sources are under `example/buildtime/resources/shaders/`, and its generated assets go to `example/runtime/resources/`. `gamecore.slang` lives beside the shaders and is treated as a shared include, not a standalone resource. CRT shaders include it through `../gamecore.slang`. Changes to it recheck the registered shaders. Only NGA?s platform-header directory is passed as a compiler include path. The optional `dependencyRoot` argument to `ResourceManager.Initialize` identifies the directory containing sibling library repositories; the default remains the parent of the application root, as used by Bramorr. The nested example passes its dependency root explicitly. Without buildtime sources, the resource manager loads the existing runtime resource list and hashed files.

Texture loading supports the RGBA8 KTX1 assets produced by the existing texture builder, including mip chains. The existing offline texture/model builders still invoke `texturec` and `geometryc` from the sibling BGFX tools directory; BGFX is no longer a runtime or link dependency.

Bramorr has an `NGA` branch, but its application callers and game-specific compute/volume shaders are the next migration stage.
