using internal GameCore;
using System;
using System.Collections;
using System.Threading;
using NoGraphicsAPI;

namespace GameCore;

public class RenderCommandBuffer
{
    public enum Lifecycle
    {
        Available,
        Recording,
        Executable,
        Queued,
        InFlight
    }

    private Device* device;
    private GpuHeap timestamps;
    private bool recordedTimings;
    private bool renderPassOpen;
    private bool attachmentsInitialized;
    private bool swapchainTarget;
    private bool recordingSucceeded;
    private int recordingThreadId;
    private ColorAttachment[RenderTexture.MaxColorAttachments] colorAttachments;
    private int colorAttachmentCount;
    private RenderView* depthView;
    private NoGraphicsAPI.Texture*[RenderTexture.MaxColorAttachments] colorTextures;
    private NoGraphicsAPI.Texture* depthTexture;
    private Format[RenderTexture.MaxColorAttachments] colorFormats;
    private Format depthFormat;
    private uint32x2 targetExtent;
    private uint64 directBarrierCount;
    private List<GpuHeap> uploadPages = new .() ~ delete _;
    private List<GpuHeap> temporaryBuffers = new .() ~ delete _;
    private int temporaryBufferIndex;
    private int pageIndex;
    private uint64 pageOffset;
    private RenderResourceTracker resourceTracker = new .(false) ~ delete _;
    private List<RenderResourceAccess> pendingAccesses = new .() ~ delete _;
    internal List<RenderResourceAccess> ResourceSummary = new .() ~ delete _;
    internal CommandBuffer* NativeCommands;
    internal Vector4 FrameShaderData;
    internal Vector4[9] FrameSphericalHarmonics;
    public readonly PipelineCache Pipelines ~ delete _;
    public readonly CommandPool* Pool;
    public Lifecycle Status { get; internal set; }
    public RenderTexture Target { get; private set; }
    public String Name = new .() ~ delete _;
    public bool ProfilingEnabled { get; internal set; }
    public float GpuMilliseconds { get; private set; }
    public bool HasGpuTiming { get; private set; }
    public uint32 DrawCount { get; private set; }
    public uint32 TriangleCount { get; private set; }
    public uint32 DispatchCount { get; private set; }
    public uint32 CopyCount { get; private set; }
    public bool HasCommands { get; private set; }
    public Matrix4 View = .Identity;
    public Matrix4 Projection = .Identity;
    public Viewport Viewport = .() { width = 0, height = 0 };
    public ClearColor ClearColor;
    public float ClearDepth = 1;
    public bool ClearColorBuffer;
    public bool ClearDepthBuffer;
    internal bool RecordingSucceeded => recordingSucceeded;
    internal uint64 BarrierCount => resourceTracker.BarrierCount + directBarrierCount;

    internal class CompletionStatus
    {
        private int references = 1;
        public bool Complete;
        public bool Cancelled;

        public void AddReference()
        {
            Interlocked.Increment(ref references);
        }

        public void Release()
        {
            if (Interlocked.Decrement(ref references) == 0)
                delete this;
        }
    }

    private CompletionStatus completionStatus;

    internal CompletionStatus RetainCompletionStatus()
    {
        RequireRecording();
        if (completionStatus == null)
            completionStatus = new .();
        completionStatus.AddReference();
        return completionStatus;
    }

    internal this(Device* device)
    {
        this.device = device;
        Pipelines = new .(device);
        timestamps = GPU.CreateGpuHeap(device, 2 * sizeof(uint64), .readback);
        Pool = GPU.CreateCommandPool(device, 0);
    }

    public ~this()
    {
        GPU.WaitIdle(device);
        if (completionStatus != null)
        {
            completionStatus.Cancelled = true;
            completionStatus.Release();
        }
        for (var page in uploadPages)
            GPU.DestroyGpuHeap(page);
        for (var memory in temporaryBuffers)
            GPU.DestroyGpuHeap(memory);
        GPU.DestroyGpuHeap(timestamps);
        GPU.DestroyCommandPool(Pool);
    }

    internal void Begin(RenderTexture target, bool swapchain, SwapchainFrame frame)
    {
        Target = target;
        swapchainTarget = swapchain;
        colorAttachmentCount = target != null ? target.ColorAttachmentCount : swapchain && frame.render_view != null ? 1 : 0;
        for (int index = 0; index < colorAttachmentCount; ++index)
        {
            colorAttachments[index] = .() { render_view = target != null ? target.GetColorTexture(index)?.View : frame.render_view };
            colorTextures[index] = target != null ? target.GetColorTexture(index)?.Texture : null;
            colorFormats[index] = target != null ? target.GetColorFormat(index) : .bgra8_srgb;
        }
        depthView = target != null ? target.DepthHandle?.View : null;
        depthTexture = target != null ? target.DepthHandle?.Texture : null;
        depthFormat = target != null ? target.DepthFormat : .undefined;
        targetExtent = target != null ? .() { x = (.)target.Width, y = (.)target.Height } : frame.extent;
        recordingSucceeded = true;
        recordingThreadId = 0;
        HasCommands = false;
        DrawCount = TriangleCount = DispatchCount = CopyCount = 0;
        NativeCommands = GPU.BeginCommands(Pool);
        recordedTimings = ProfilingEnabled && timestamps.range.cpu != null && GPU.GetDeviceCaps(device).timestamp_period_ns > 0;
        if (recordedTimings)
            GPU.WriteTimestamp(NativeCommands, (.)timestamps.range.gpu, .all_commands);
        GPU.SetTextureDescriptorHeap(NativeCommands, GPU.GpuRange(RenderManager.TextureDescriptors));
        GPU.SetSamplerDescriptorHeap(NativeCommands, GPU.GpuRange(RenderManager.SamplerDescriptors));
    }

    public void RequireRecording()
    {
        if (Status != .Recording)
            Runtime.FatalError("Command buffer is not recording");
        int currentThread = Thread.CurrentThreadId;
        int owner = Interlocked.CompareExchange(ref recordingThreadId, 0, currentThread);
        if (owner != 0 && owner != currentThread)
            Runtime.FatalError("Command buffer must be recorded and finished by one thread");
    }

    public GpuCpuRange Allocate(uint64 byteCount)
    {
        RequireRecording();
        uint64 size = (byteCount + 15) & ~15UL;
        while (pageIndex < uploadPages.Count && pageOffset + size > uploadPages[pageIndex].range.size)
        {
            ++pageIndex;
            pageOffset = 0;
        }
        if (pageIndex == uploadPages.Count)
            uploadPages.Add(GPU.CreateGpuHeap(device, Math.Max(size, 4UL * 1024 * 1024), .cpu_visible));
        var page = uploadPages[pageIndex];
        if (page.range.cpu == null)
            Runtime.FatalError("Unable to allocate NGA frame memory");
        GpuCpuRange result = .() { cpu = page.range.cpu + pageOffset, gpu = page.range.gpu + pageOffset, size = byteCount };
        pageOffset += size;
        return result;
    }

    public void* Upload(void* source, uint64 byteCount)
    {
        if (source == null || byteCount == 0)
            return null;
        var allocation = Allocate(byteCount);
        Internal.MemCpy(allocation.cpu, source, (.)byteCount);
        return allocation.gpu;
    }

    public GpuBuffer TransientVertices(void* source, uint32 byteCount, VertexLayout layout)
    {
        var allocation = Allocate(byteCount);
        Internal.MemCpy(allocation.cpu, source, byteCount);
        return .() { Memory = .() { range = allocation }, Layout = layout, Count = byteCount / layout.stride };
    }

    public GpuBuffer TransientIndices(void* source, uint32 byteCount, IndexType type = .uint16)
    {
        var allocation = Allocate(byteCount);
        Internal.MemCpy(allocation.cpu, source, byteCount);
        return .() { Memory = .() { range = allocation }, IndexType = type, Count = byteCount / (type == .uint16 ? 2U : 4U) };
    }

    private void Summarize(RenderResourceAccess access)
    {
        if (access.Resource == null)
            return;
        for (var existing in ref ResourceSummary)
        {
            if (existing.Resource == access.Resource && existing.IsTexture == access.IsTexture)
            {
                existing.Stages |= access.Stages;
                existing.Access |= access.Access;
                return;
            }
        }
        ResourceSummary.Add(access);
    }

    public void UseTexture(GpuTexture texture, Stage stages, Access access)
    {
        RequireRecording();
        pendingAccesses.Add(.() { Resource = texture.Texture, IsTexture = true, Stages = stages, Access = access });
    }

    public void UseBuffer(GpuBuffer buffer, Stage stages, Access access)
    {
        RequireRecording();
        pendingAccesses.Add(.() { Resource = buffer.Memory.owner, Stages = stages, Access = access });
    }

    private void CloseRenderPass()
    {
        if (!renderPassOpen)
            return;
        GPU.EndRenderPass(NativeCommands);
        renderPassOpen = false;
    }

    private void AddAttachmentAccesses()
    {
        for (int index = 0; index < colorAttachmentCount; ++index)
        {
            RenderResourceAccess color = .() { Resource = colorTextures[index], IsTexture = true, Stages = .color_output, Access = .color_read | .color_write };
            resourceTracker.Add(color);
            Summarize(color);
        }
        RenderResourceAccess depth = .() { Resource = depthTexture, IsTexture = true, Stages = .depth_stencil_tests, Access = .depth_stencil_read | .depth_stencil_write };
        resourceTracker.Add(depth);
        Summarize(depth);
    }

    private void EmitDependencies()
    {
        if (resourceTracker.Prepare())
        {
            CloseRenderPass();
            resourceTracker.Emit(NativeCommands);
        }
    }

    private void OpenRenderPass()
    {
        if (renderPassOpen || (colorAttachmentCount == 0 && depthView == null))
            return;
        for (int index = 0; index < colorAttachmentCount; ++index)
        {
            colorAttachments[index].load = !attachmentsInitialized && ClearColorBuffer ? .clear : .load;
            colorAttachments[index].clear = ClearColor;
        }
        RenderingDesc rendering = .();
        rendering.colors = .() { data = &colorAttachments[0], size = (.)colorAttachmentCount };
        if (depthView != null)
        {
            rendering.depth.render_view = depthView;
            rendering.depth.load = !attachmentsInitialized && ClearDepthBuffer ? .clear : .load;
            rendering.depth.clear = ClearDepth;
            if (GPU.GetTextureFormatInfo(depthFormat).stencil)
                rendering.stencil.render_view = depthView;
        }
        GPU.BeginRenderPass(NativeCommands, rendering, .none);
        for (int index = 0; index < colorAttachmentCount; ++index)
            if (colorTextures[index] != null)
                resourceTracker.RecordAttachmentWrite(colorTextures[index], .color_output, .color_write);
        if (depthTexture != null)
            resourceTracker.RecordAttachmentWrite(depthTexture, .depth_stencil_tests, .depth_stencil_write);
        attachmentsInitialized = true;
        renderPassOpen = true;
        HasCommands = true;
    }

    private void InitializeAttachments()
    {
        if (attachmentsInitialized || (!ClearColorBuffer && !ClearDepthBuffer) || (colorAttachmentCount == 0 && depthView == null))
            return;
        resourceTracker.BeginCommand();
        AddAttachmentAccesses();
        EmitDependencies();
        OpenRenderPass();
    }

    private void PrepareShader(bool graphics)
    {
        InitializeAttachments();
        if (!graphics)
            CloseRenderPass();
        resourceTracker.BeginCommand();
        for (var access in pendingAccesses)
        {
            resourceTracker.Add(access);
            Summarize(access);
        }
        pendingAccesses.Clear();
        if (graphics && !renderPassOpen)
            AddAttachmentAccesses();
        EmitDependencies();
        if (graphics)
            OpenRenderPass();
    }

    private DrawRoot CreateRoot(DrawConstants constants, void* storage)
    {
        var constants;
        constants.View = View;
        constants.Projection = Projection;
        var viewport = EffectiveViewport;
        constants.ViewRectangle = .(viewport.x, viewport.y, viewport.width, viewport.height);
        return .() { Constants = (.)Upload(&constants, sizeof(DrawConstants)), Storage = storage };
    }

    private Viewport EffectiveViewport
    {
        get
        {
            var viewport = Viewport;
            if (viewport.width <= 0)
                viewport.width = targetExtent.x;
            if (viewport.height <= 0)
                viewport.height = targetExtent.y;
            return viewport;
        }
    }

    public void Draw(ShaderProgram program, GpuBuffer vertices, GpuBuffer indices, uint32 vertexCount, uint32 indexCount,
        DrawConstants constants, RenderState state, void* storage = null, bool lines = false,
        uint32 firstVertex = 0, uint32 firstIndex = 0)
    {
        RequireRecording();
        if (Target == null && !swapchainTarget)
            Runtime.FatalError("Draw requires a render target; null targets are compute/transfer only");
        UseBuffer(vertices, .vertex, .shader_read);
        UseBuffer(indices, lines ? .vertex : .index_input, lines ? .shader_read : .index_read);
        PrepareShader(true);
        if (!renderPassOpen)
            return;
        var pipeline = Pipelines.Get(program, Span<Format>(&colorFormats[0], colorAttachmentCount), depthFormat, state);
        if (pipeline == null)
        {
            recordingSucceeded = false;
            return;
        }
        DrawRoot root = CreateRoot(constants, storage);
        root.Vertices = vertices.Memory.range.gpu;
        root.Indices = indices.Memory.range.gpu;
        root.Stride = vertices.Layout.stride;
        root.LineMode = lines ? 1U : 0U;
        root.IndexSize = indices.Memory.range.gpu == null ? 0U : indices.IndexType == .uint16 ? 2U : 4U;
        root.FirstVertex = firstVertex;
        root.FirstIndex = firstIndex;
        for (int attribute = 0; attribute < 18; ++attribute)
            root.Attributes[attribute] = vertices.Memory.range.gpu == null ? uint32.MaxValue : vertices.Layout.offset[attribute] | ((uint32)vertices.Layout.attributes[attribute] << 16);
        var viewport = EffectiveViewport;
        GPU.SetViewport(NativeCommands, viewport);
        GPU.SetScissor(NativeCommands, .() { x = (.)viewport.x, y = (.)viewport.y, width = (.)viewport.width, height = (.)viewport.height });
        GPU.BindPso(NativeCommands, pipeline);
        var depth = state.Depth;
        if (depthFormat == .undefined)
        {
            depth.depth_test = false;
            depth.depth_write = false;
        }
        GPU.SetDepthStencil(NativeCommands, depth);
        ByteSpan rootBytes = .() { data = (.)&root, size = sizeof(DrawRoot) };
        if (lines)
            GPU.Draw(NativeCommands, rootBytes, (indexCount > 0 ? indexCount : vertexCount) / 2 * 6, 1, 0, 0);
        else if (indexCount > 0)
            GPU.DrawIndexed(NativeCommands, rootBytes, GPU.GpuRange(indices.Memory), indices.IndexType, indexCount, 1, firstIndex, (.)firstVertex, 0);
        else
            GPU.Draw(NativeCommands, rootBytes, vertexCount, 1, firstVertex, 0);
        ++DrawCount;
        TriangleCount += lines ? (indexCount > 0 ? indexCount : vertexCount) : (indexCount > 0 ? indexCount : vertexCount) / 3;
        HasCommands = true;
    }

    public void Dispatch(ShaderProgram program, uint32x3 groups, DrawConstants constants, void* storage = null)
    {
        RequireRecording();
        PrepareShader(false);
        var pipeline = Pipelines.GetCompute(program);
        if (pipeline == null)
        {
            recordingSucceeded = false;
            return;
        }
        var root = CreateRoot(constants, storage);
        GPU.BindPso(NativeCommands, pipeline);
        GPU.Dispatch(NativeCommands, .() { data = (.)&root, size = sizeof(DrawRoot) }, groups);
        ++DispatchCount;
        HasCommands = true;
    }

    private void BeginTransfer()
    {
        RequireRecording();
        InitializeAttachments();
        CloseRenderPass();
        resourceTracker.BeginCommand();
        HasCommands = true;
    }

    private void TransferAccess(void* resource, bool texture, Access access)
    {
        RenderResourceAccess declaration = .() { Resource = resource, IsTexture = texture, Stages = .transfer, Access = access };
        resourceTracker.Add(declaration);
        Summarize(declaration);
    }

    public void UploadTexture(GpuTexture texture, Span<uint8> pixels, TextureCopyDesc region)
    {
        BeginTransfer();
        uint64 requiredSize = texture.GetRegionByteCount(region);
        if (requiredSize == 0 || requiredSize > (uint64)pixels.Length)
            Runtime.FatalError("Invalid texture upload region or size");
        var allocation = Allocate((.)pixels.Length);
        Internal.MemCpy(allocation.cpu, pixels.Ptr, pixels.Length);
        TransferAccess(texture.Texture, true, .transfer_write);
        EmitDependencies();
        GPU.CopyMemoryToTexture(NativeCommands, .() { gpu = allocation.gpu, size = allocation.size }, texture.Texture, region);
    }

    public void UpdateBuffer(GpuBuffer buffer, Span<uint8> data, uint64 byteOffset)
    {
        BeginTransfer();
        if (buffer.MemoryType != .gpu_only)
            Runtime.FatalError("Buffer uploads require GPU storage memory");
        if (byteOffset > buffer.Memory.range.size || (uint64)data.Length > buffer.Memory.range.size - byteOffset)
            Runtime.FatalError("Buffer upload exceeds allocation");
        TransferAccess(buffer.Memory.owner, false, .transfer_write);
        EmitDependencies();
        GPU.CopyMemory(NativeCommands, .() { gpu = Upload(data.Ptr, (.)data.Length), size = (.)data.Length },
            .() { gpu = buffer.Memory.range.gpu + byteOffset, size = (.)data.Length });
    }

    public bool CopyTexture(GpuTexture source, GpuTexture destination, TextureCopyDesc sourceRegion, TextureCopyDesc destinationRegion)
    {
        RequireRecording();
        uint64 size = source.GetRegionByteCount(sourceRegion);
        if (size == 0 || source.Format != destination.Format || size != destination.GetRegionByteCount(destinationRegion))
            return false;
        if (temporaryBufferIndex == temporaryBuffers.Count)
            temporaryBuffers.Add(GPU.CreateGpuHeap(device, size, .gpu_only));
        else if (temporaryBuffers[temporaryBufferIndex].range.size < size)
        {
            GPU.DestroyGpuHeap(temporaryBuffers[temporaryBufferIndex]);
            temporaryBuffers[temporaryBufferIndex] = GPU.CreateGpuHeap(device, size, .gpu_only);
        }
        var memory = temporaryBuffers[temporaryBufferIndex++];
        if (memory.owner == null)
            return false;
        BeginTransfer();
        TransferAccess(source.Texture, true, .transfer_read);
        EmitDependencies();
        GPU.CopyTextureToMemory(NativeCommands, source.Texture, GPU.GpuRange(memory), sourceRegion);
        resourceTracker.BeginCommand();
        TransferAccess(destination.Texture, true, .transfer_write);
        EmitDependencies();
        GPU.Barrier(NativeCommands, .transfer, .transfer_write, .transfer, .transfer_read);
        ++directBarrierCount;
        GPU.CopyMemoryToTexture(NativeCommands, GPU.GpuRange(memory), destination.Texture, destinationRegion);
        ++CopyCount;
        return true;
    }

    public void ReadTexture(GpuTexture source, TextureReadback readback, TextureCopyDesc region)
    {
        BeginTransfer();
        TransferAccess(source.Texture, true, .transfer_read);
        EmitDependencies();
        GPU.CopyTextureToMemory(NativeCommands, source.Texture, GPU.GpuRange(readback.Memory), region);
        GPU.Barrier(NativeCommands, .transfer, .transfer_write, .host, .host_read);
        ++directBarrierCount;
    }

    public bool Finish()
    {
        RequireRecording();
        InitializeAttachments();
        CloseRenderPass();
        if (recordedTimings)
            GPU.WriteTimestamp(NativeCommands, (uint64*)timestamps.range.gpu + 1, .all_commands);
        GPU.EndCommands(NativeCommands);
        Status = .Executable;
        return recordingSucceeded;
    }

    internal void Cancel()
    {
        CloseRenderPass();
        if (Status == .Recording)
            GPU.EndCommands(NativeCommands);
        Reset();
    }

    internal void Complete()
    {
        float millisecondsPerTick = GPU.GetDeviceCaps(device).timestamp_period_ns / 1000000.0f;
        uint64* ticks = (.)timestamps.range.cpu;
        HasGpuTiming = recordedTimings && ticks[1] >= ticks[0];
        GpuMilliseconds = HasGpuTiming ? (ticks[1] - ticks[0]) * millisecondsPerTick : 0;
        if (completionStatus != null)
            completionStatus.Complete = true;
        Reset();
    }

    internal void Reset()
    {
        if (completionStatus != null)
        {
            completionStatus.Cancelled = !completionStatus.Complete;
            completionStatus.Release();
            completionStatus = null;
        }
        resourceTracker.Reset();
        pendingAccesses.Clear();
        ResourceSummary.Clear();
        pageIndex = 0;
        pageOffset = 0;
        temporaryBufferIndex = 0;
        directBarrierCount = 0;
        HasCommands = false;
        attachmentsInitialized = false;
        renderPassOpen = false;
        GPU.ResetCommandPool(Pool);
        NativeCommands = null;
        Target = null;
        View = .Identity;
        Projection = .Identity;
        Viewport = .() { width = 0, height = 0 };
        ClearColor = default;
        ClearDepth = 1;
        ClearColorBuffer = false;
        ClearDepthBuffer = false;
        Name.Clear();
        Status = .Available;
    }
}
