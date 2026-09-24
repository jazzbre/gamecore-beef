using System;
using System.Collections;
using System.Threading;
using NoGraphicsAPI;
using ImGui;

namespace GameCore;

public enum RenderShaderType { Font, Last }

public static class RenderManager
{
    public struct Statistics
    {
        public uint64 submitCount, blitCount;
        public void Clear() mut { this = default; }
    }
    struct RetiredTexture
    {
        public NoGraphicsAPI.Texture* Texture;
        public TextureHeap Memory;
        public RenderView* View;
        public uint32 Descriptor;
        public ImGui.TextureID Image;
    }
    public static readonly Monitor ResourceLock = new .() ~ delete _;
    public static Device* Device;
    public static CommandPool* UploadPool;
    public static RenderContext Context;
    public static GpuHeap TextureDescriptors, SamplerDescriptors;
    private static TimelinePoint completion;
    private static List<GpuHeap> retiredBuffers = new .() ~ delete _;
    private static List<RetiredTexture> retiredTextures = new .() ~ delete _;
    private static List<uint32> freeDescriptors = new .() ~ delete _;
    private static uint32 nextDescriptor;
    private static List<SamplerDesc> samplerDescriptions = new .() ~ delete _;
    private static GpuTexture whiteTexture;
    public static Statistics statistics;
    public static SpriteBatchRenderer batchRenderer, entityBatchRenderer;
    public static RenderTexture temporaryRenderTextureWithDepth;
    public static GpuTexture readBackTextureHandle;
    public static bool capture;
    public static int width = 1280, height = 720;
    public static float ooWidth, ooHeight, aspectRatio = 1;
    public static Bounds2 viewBounds;
    public static bool IsRenderTextureYFlipped => true;
    public static Vector4 ShaderData { get; private set; }
    public static uint16 PreViewId { get; private set; }
    public static uint16 ViewId { get; private set; }
    public static uint16 PostViewId { get; private set; }
    public static GpuBuffer batchVertexBufferHandle, batchIndexBufferHandle, batchTesselatedVertexBufferHandle, batchTesselatedIndexBufferHandle;
    public static int batchVertexCount, batchIndexCount, batchTesselatedVertexCount, batchTesselatedIndexCount;
    public static VertexLayout batchVertexLayout;
    public static Shader[] shaders = new Shader[(int)RenderShaderType.Last] ~ delete _;
    public static SH9 sh9 = new .() ~ delete _;
    public typealias OverlayRenderer = function void(CommandBuffer* commands, uint32x2 extent, TimelinePoint completion);
    public static SamplerDesc LinearClamp
    {
        get { SamplerDesc sampler = .(); sampler.address_u = sampler.address_v = sampler.address_w = .clamp_to_edge; return sampler; }
    }
    public static SamplerDesc PointClamp
    {
        get { var sampler = LinearClamp; sampler.min_filter = sampler.mag_filter = sampler.mip_filter = .nearest; return sampler; }
    }
    public static bool InitializeDevice(void* nativeWindow)
    {
        if (Device != null) return false;
        DeviceDesc description = .(); description.window = nativeWindow; description.swapchain_format = .bgra8_srgb;
        Device = GPU.CreateDevice(description).device;
        if (Device == null) return false;
        var capabilities = GPU.GetDeviceCaps(Device);
        TextureDescriptors = GPU.CreateGpuHeap(Device, capabilities.texture_descriptor_size * 4352, .texture_descriptor_heap);
        SamplerDescriptors = GPU.CreateGpuHeap(Device, capabilities.sampler_descriptor_size * 256, .sampler_descriptor_heap);
        completion = .(); completion.semaphore = GPU.CreateTimelineSemaphore(Device, 0);
        UploadPool = GPU.CreateCommandPool(Device, 0);
        if (TextureDescriptors.owner == null || SamplerDescriptors.owner == null || completion.semaphore == null || UploadPool == null)
        { ShutdownDevice(); return false; }
        Context = new .(Device);
        if (Context.Pool == null) { ShutdownDevice(); return false; }
        uint32 white = uint32.MaxValue;
        whiteTexture = new .(1, 1, .rgba8_unorm, .sampled, &white, 4);
        GetSampler(LinearClamp);
        return true;
    }
    public static bool InitializeImGui(SDL2.SDL.Window* window) => ImGui.NgaInitializeShared(window, Device, .bgra8_srgb, 256, &TextureDescriptors, &SamplerDescriptors, 4096, 255);
    public static void ShutdownDevice()
    {
        ResourceLock.Enter(); defer ResourceLock.Exit();
        if (Device == null) return;
        GPU.WaitIdle(Device);
        delete whiteTexture; whiteTexture = null;
        CollectResources();
        delete Context; Context = null;
        GPU.DestroyCommandPool(UploadPool);
        GPU.DestroyTimelineSemaphore(completion.semaphore);
        GPU.DestroyGpuHeap(TextureDescriptors); GPU.DestroyGpuHeap(SamplerDescriptors);
        GPU.DestroyDevice(Device); Device = null;
        nextDescriptor = 0; freeDescriptors.Clear(); samplerDescriptions.Clear();
    }
    public static uint32 AllocateTextureDescriptor()
    {
        if (freeDescriptors.Count > 0) return freeDescriptors.PopBack();
        if (nextDescriptor == 4096) Runtime.FatalError("GameCore texture descriptor capacity exceeded");
        return nextDescriptor++;
    }
    public static uint32 GetSampler(SamplerDesc sampler)
    {
        for (int index = 0; index < samplerDescriptions.Count; ++index)
        {
            var existing = samplerDescriptions[index];
            if (existing.min_filter == sampler.min_filter && existing.mag_filter == sampler.mag_filter && existing.mip_filter == sampler.mip_filter
                && existing.address_u == sampler.address_u && existing.address_v == sampler.address_v && existing.address_w == sampler.address_w
                && existing.anisotropic == sampler.anisotropic && existing.compare_enabled == sampler.compare_enabled && existing.compare == sampler.compare) return (.)index;
        }
        if (samplerDescriptions.Count >= 255) Runtime.FatalError("GameCore sampler capacity exceeded");
        uint32 descriptor = (.)samplerDescriptions.Count;
        samplerDescriptions.Add(sampler);
        GPU.WriteSamplerDescriptor(Device, SamplerDescriptors.range.cpu + descriptor * GPU.GetDeviceCaps(Device).sampler_descriptor_size, sampler);
        return descriptor;
    }
    public static void Retire(GpuHeap memory) { ResourceLock.Enter(); defer ResourceLock.Exit(); retiredBuffers.Add(memory); }
    public static void RetireTexture(NoGraphicsAPI.Texture* texture, TextureHeap memory, RenderView* view, uint32 descriptor, ImGui.TextureID image)
    { ResourceLock.Enter(); defer ResourceLock.Exit(); retiredTextures.Add(.() { Texture = texture, Memory = memory, View = view, Descriptor = descriptor, Image = image }); }
    private static void CollectResources()
    {
        for (var memory in retiredBuffers) GPU.DestroyGpuHeap(memory);
        retiredBuffers.Clear();
        for (var texture in retiredTextures)
        {
            if (texture.Image != default) ImGui.NgaRemoveTexture(texture.Image);
            GPU.DestroyRenderView(texture.View); GPU.DestroyTexture(texture.Texture); GPU.DestroyTextureHeap(texture.Memory);
            freeDescriptors.Add(texture.Descriptor);
        }
        retiredTextures.Clear();
    }
    public static void SubmitUpload(CommandBuffer* commands)
    {
        var commands;
        GPU.EndCommands(commands); completion.value++;
        SubmitDesc submission = .(); submission.commands = .() { data = &commands, size = 1 }; submission.completion = completion;
        GPU.Submit(Device, submission, 0); GPU.WaitTimeline(completion); GPU.ResetCommandPool(UploadPool);
    }
    public static bool Frame(OverlayRenderer overlay = null)
    {
        ResourceLock.Enter(); defer ResourceLock.Exit();
        var commands = GPU.BeginCommands(Context.Pool);
        var frame = GPU.Acquire(commands);
        bool success = Context.Record(commands, frame);
        completion.value++;
        if (overlay != null && frame.render_view != null)
        {
            ColorAttachment color = .(); color.render_view = frame.render_view;
            RenderingDesc rendering = .(); rendering.colors = .() { data = &color, size = 1 };
            GPU.BeginRenderPass(commands, rendering, .none); overlay(commands, frame.extent, completion); GPU.EndRenderPass(commands);
        }
        GPU.EndCommands(commands);
        SubmitDesc submission = .(); submission.commands = .() { data = &commands, size = 1 }; submission.completion = completion;
        if (frame.render_view != null) GPU.SubmitAndPresent(Device, submission); else GPU.Submit(Device, submission, 0);
        GPU.WaitTimeline(completion); CollectResources(); Context.Reset();
        return success;
    }
    public static bool ReadTexture(GpuTexture texture, void* destination, uint32 capacity)
    {
        ResourceLock.Enter(); defer ResourceLock.Exit();
        if (Context.HasDraws) return false;
        uint64 size = texture.Width * texture.Height * GPU.GetTextureFormatInfo(texture.Format).bytes_per_block;
        if (capacity < size) return false;
        var memory = GPU.CreateGpuHeap(Device, size, .readback);
        if (memory.range.cpu == null) return false;
        var commands = GPU.BeginCommands(UploadPool);
        GPU.CopyTextureToMemory(commands, texture.Texture, GPU.GpuRange(memory), .());
        GPU.Barrier(commands, .transfer, .transfer_write, .host, .host_read);
        SubmitUpload(commands); Internal.MemCpy(destination, memory.range.cpu, (.)size); GPU.DestroyGpuHeap(memory);
        return true;
    }
    public static RenderViewState GetView(uint16 id) => Context.Views[id];
    public static Shader GetShader(RenderShaderType type) => shaders[(int)type];
    public static void PreInitialize() {}
    public static bool Initialize(int maxBatchCount = 128)
    {
        batchRenderer = new .(); entityBatchRenderer = new .();
        batchVertexLayout.Begin(); batchVertexLayout.Add(.Position, 3, .Float); batchVertexLayout.End();
        CreateQuad(1, 1, maxBatchCount, out batchVertexBufferHandle, out batchIndexBufferHandle, out batchVertexCount, out batchIndexCount);
        CreateQuad(2, 2, maxBatchCount, out batchTesselatedVertexBufferHandle, out batchTesselatedIndexBufferHandle, out batchTesselatedVertexCount, out batchTesselatedIndexCount);
        shaders[(int)RenderShaderType.Font] = ResourceManager.GetResource<Shader>("shaders/font_sprite_texture");
        Resize(width, height);
        return true;
    }
    public static void Resize(int newWidth, int newHeight)
    {
        width = newWidth; height = newHeight; ooWidth = 1.0f / Math.Max(1, width); ooHeight = 1.0f / Math.Max(1, height);
        aspectRatio = width * ooHeight; viewBounds = .(.Zero, .(width, height));
        if (temporaryRenderTextureWithDepth == null) temporaryRenderTextureWithDepth = new .(width, height, .rgba16_float, .d24_unorm_s8_uint);
        else temporaryRenderTextureWithDepth.Resize(width, height);
    }
    public static void Finalize()
    {
        DebugDraw3D.Finalize();
        delete batchRenderer; delete entityBatchRenderer; delete temporaryRenderTextureWithDepth; delete readBackTextureHandle;
        batchRenderer = null; entityBatchRenderer = null; temporaryRenderTextureWithDepth = null; readBackTextureHandle = null;
        batchVertexBufferHandle.Dispose(); batchIndexBufferHandle.Dispose(); batchTesselatedVertexBufferHandle.Dispose(); batchTesselatedIndexBufferHandle.Dispose();
    }
    public static void OnPreRender(float timeStep)
    {
        PreViewId = 0; ViewId = 60; PostViewId = 100; statistics.Clear();
        ShaderData = .((float)Time.Time, (float)(Time.Time * 0.1), timeStep, timeStep != 0 ? 1.0f / timeStep : 0);
    }
    public static void OnPostRender() {}
    public static uint16 NextPreViewId() => ++PreViewId;
    public static uint16 NextViewId() => ++ViewId;
    public static uint16 NextPostViewId() => ++PostViewId;
    public static void SetViewRectangle(uint16 id, uint16 x, uint16 y, uint16 viewWidth, uint16 viewHeight)
    { GetView(id).Viewport = .() { x = x, y = y, width = viewWidth, height = viewHeight }; }
    public static void FixProjectionMatrix(ref Matrix4 projection) { projection.d[5] = -projection.d[5]; projection.v.m31 = -projection.v.m31; }
    public static CullMode GetCullingState(bool counterClockwise) => counterClockwise ? .clockwise : .counter_clockwise;
    public static Matrix4 CreatePerspectiveOrtho(float left, float right, float bottom, float top, float near, float far, float offset = 0)
    { var projection = Matrix4.CreatePerspectiveOrtho(left, right, bottom, top, near, far, offset, false); FixProjectionMatrix(ref projection); return projection; }
    public static void Draw(uint16 viewId, Shader shader, int programIndex, GpuBuffer vertices, GpuBuffer indices, uint32 vertexCount, uint32 indexCount,
        Matrix4 world, Vector4 color, Vector4 settings, GpuTexture[] textures = null, RenderState? state = null, SamplerDesc? sampler = null,
        Vector4* instances = null, int instanceCount = 0, Vector4 textureScale = .Zero, void* storage = null, bool lines = false, Span<uint8> parameters = default)
    {
        DrawConstants constants = .() { World = world, Color = color, Time = ShaderData, Settings = settings, TextureScale = textureScale };
        constants.Instances = (.)Context.Upload(instances, (uint64)instanceCount * sizeof(Vector4));
        constants.SphericalHarmonics = (.)Context.Upload(&sh9.sh[0].x, 9 * sizeof(Vector4));
        constants.Parameters = Context.Upload(parameters.Ptr, (.)parameters.Length);
        uint32 samplerIndex = GetSampler(sampler.GetValueOrDefault(LinearClamp));
        for (int index = 0; index < 8; ++index)
        {
            constants.Textures[index] = textures != null && index < textures.Count && textures[index] != null ? textures[index].Descriptor : whiteTexture.Descriptor;
            constants.Samplers[index] = samplerIndex;
        }
        Context.Enqueue(viewId, shader.Programs[programIndex], vertices, indices, vertexCount, indexCount, constants, state.GetValueOrDefault(.Alpha), storage, lines);
        ++statistics.submitCount;
    }
    public static void RenderMeshes(uint16 viewId, Matrix4 world, Shader shader, int quadCount, Vector4* instances, int instanceCount,
        Vector4 settings, Vector4 textureScale, GpuTexture[] textures, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0, bool tesselated = false)
    {
        Draw(viewId, shader, programIndex, tesselated ? batchTesselatedVertexBufferHandle : batchVertexBufferHandle,
            tesselated ? batchTesselatedIndexBufferHandle : batchIndexBufferHandle,
            (uint32)(quadCount * (tesselated ? batchTesselatedVertexCount : batchVertexCount)), (uint32)(quadCount * (tesselated ? batchTesselatedIndexCount : batchIndexCount)),
            world, .One, settings, textures, state, sampler, instances, instanceCount, textureScale);
    }
    public static void RenderScreenQuad(uint16 viewId, Shader shader, GpuTexture[] textures, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0)
    { Draw(viewId, shader, programIndex, batchVertexBufferHandle, batchIndexBufferHandle, 4, 6, .Identity, .One, .Zero, textures, state, sampler); }
    public static void RenderScreenQuad(uint16 viewId, Shader shader, GpuTexture texture, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0)
    { RenderScreenQuad(viewId, shader, scope GpuTexture[](texture), state, sampler, programIndex); }
    public static void BlitWithShader(uint16 viewId, Shader shader, RenderTexture target, GpuTexture[] textures, RenderState? state = null, SamplerDesc? sampler = null, bool clear = true, int shiftScale = 0, int programIndex = 0)
    {
        var view = GetView(viewId); view.Target = target; view.ClearColorBuffer = clear; view.ClearDepthBuffer = clear; view.Active = true;
        view.Viewport = .() { width = target.Width >> shiftScale, height = target.Height >> shiftScale };
        view.View = .Identity; view.Projection = CreatePerspectiveOrtho(0, view.Viewport.width, 0, view.Viewport.height, 0, 1);
        RenderScreenQuad(viewId, shader, textures, state, sampler, programIndex);
    }
    public static void BlitWithShader(uint16 viewId, Shader shader, RenderTexture target, GpuTexture texture, RenderState? state = null, SamplerDesc? sampler = null, bool clear = true, int shiftScale = 0, int programIndex = 0)
    { BlitWithShader(viewId, shader, target, scope GpuTexture[](texture), state, sampler, clear, shiftScale, programIndex); }
    public static void RenderFullScreenTextureAspect(uint16 viewId, GpuTexture texture, Shader shader, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0)
    { Draw(viewId, shader, programIndex, default, default, 6, 0, .Identity, .One, .Zero, scope GpuTexture[](texture), state.GetValueOrDefault(.Opaque), sampler); }
		public static void CreateQuad(int tessX, int tessY, int batchCount, out GpuBuffer outVertexBuffer, out GpuBuffer outIndexBuffer, out int vertsPerBatch, out int indicesPerBatch)
		{
			vertsPerBatch = (tessX + 1) * (tessY + 1);
			indicesPerBatch = tessX * tessY * 6;

			int totalVertCount = vertsPerBatch * batchCount;
			int totalIndexCount = indicesPerBatch * batchCount;

			var vertices = scope Vector3[totalVertCount];
			var indices  = scope uint16[totalIndexCount];

			int v = 0;
			int i = 0;
			float instanceIndex = 0.0f;

			for (int batch = 0; batch < batchCount; batch++,instanceIndex += 4.0f)
			{
				int baseVertex = v;

				// Create vertices for this batch
				for (int y = 0; y <= tessY; y++)
				{
					float fy = (float)y / (float)tessY;
					for (int x = 0; x <= tessX; x++)
					{
						float fx = (float)x / (float)tessX;
						vertices[v++] = Vector3(fx, fy, instanceIndex);
					}
				}

				// Create indices for this batch
				for (int ty = 0; ty < tessY; ty++)
				{
					for (int tx = 0; tx < tessX; tx++)
					{
						uint16 v0 = (uint16)(baseVertex + ty * (tessX + 1) + tx);
						uint16 v1 = (uint16)(v0 + 1);
						uint16 v2 = (uint16)(v0 + (tessX + 1));
						uint16 v3 = (uint16)(v2 + 1);

						// First triangle
						indices[i++] = v0;
						indices[i++] = v1;
						indices[i++] = v3;

						// Second triangle
						indices[i++] = v0;
						indices[i++] = v3;
						indices[i++] = v2;
					}
				}
			}

			outVertexBuffer = GpuBuffer.CreateVertices(&vertices[0], (uint32)(vertices.Count * sizeof(Vector3)), batchVertexLayout);
			outIndexBuffer = GpuBuffer.CreateIndices(&indices[0], (uint32)(indices.Count * sizeof(uint16)));
		}

}
