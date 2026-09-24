using System;
using System.Collections;
using NoGraphicsAPI;

namespace GameCore;

public class RenderContext
{
    struct Draw
    {
        public uint16 ViewId;
        public ShaderProgram Program;
        public RenderState State;
        public DrawRoot Root;
        public DrawConstants* Constants;
        public GpuBuffer IndexBuffer;
        public uint32 VertexCount, IndexCount;
    }
    private Device* device;
    private List<Draw> draws = new .() ~ delete _;
    private List<GpuHeap> uploadPages = new .() ~ delete _;
    private int pageIndex;
    private uint64 pageOffset;
    public readonly PipelineCache Pipelines ~ delete _;
    public readonly CommandPool* Pool;
    public readonly RenderViewState[] Views = new RenderViewState[256] ~ DeleteContainerAndItems!(_);
    public bool HasDraws => draws.Count > 0;

    public this(Device* device)
    {
        this.device = device;
        Pipelines = new .(device);
        Pool = GPU.CreateCommandPool(device, 0);
        for (var view in ref Views) view = new .();
    }
    public ~this()
    {
        GPU.WaitIdle(device);
        for (var page in uploadPages) GPU.DestroyGpuHeap(page);
        GPU.DestroyCommandPool(Pool);
    }
    public GpuCpuRange Allocate(uint64 byteCount)
    {
        uint64 size = (byteCount + 15) & ~15UL;
        while (pageIndex < uploadPages.Count && pageOffset + size > uploadPages[pageIndex].range.size) { ++pageIndex; pageOffset = 0; }
        if (pageIndex == uploadPages.Count) uploadPages.Add(GPU.CreateGpuHeap(device, Math.Max(size, 4UL * 1024 * 1024), .cpu_visible));
        var page = uploadPages[pageIndex];
        if (page.range.cpu == null) Runtime.FatalError("Unable to allocate NGA frame memory");
        GpuCpuRange result = .() { cpu = page.range.cpu + pageOffset, gpu = page.range.gpu + pageOffset, size = byteCount };
        pageOffset += size;
        return result;
    }
    public void* Upload(void* source, uint64 byteCount)
    {
        if (source == null || byteCount == 0) return null;
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
    public void Enqueue(uint16 viewId, ShaderProgram program, GpuBuffer vertices, GpuBuffer indices, uint32 vertexCount, uint32 indexCount,
        DrawConstants constants, RenderState state, void* storage = null, bool lines = false, uint32 firstVertex = 0, uint32 firstIndex = 0)
    {
        var allocation = Allocate(sizeof(DrawConstants));
        *(DrawConstants*)allocation.cpu = constants;
        DrawRoot root = .() { Vertices = vertices.Memory.range.gpu, Storage = storage, Constants = (.)allocation.gpu,
            Indices = indices.Memory.range.gpu, Stride = vertices.Layout.stride, LineMode = lines ? 1U : 0U,
            IndexSize = indices.Memory.range.gpu == null ? 0U : indices.IndexType == .uint16 ? 2U : 4U, FirstVertex = firstVertex, FirstIndex = firstIndex };
        for (int attribute = 0; attribute < 18; ++attribute)
            root.Attributes[attribute] = vertices.Memory.range.gpu == null ? uint32.MaxValue : vertices.Layout.offset[attribute] | ((uint32)vertices.Layout.attributes[attribute] << 16);
        draws.Add(.() { ViewId = viewId, Program = program, State = state, Root = root, Constants = (.)allocation.cpu,
            IndexBuffer = indices, VertexCount = vertexCount, IndexCount = indexCount });
        Views[viewId].Active = true;
    }
    public bool Record(CommandBuffer* commands, SwapchainFrame frame)
    {
        bool success = true;
        for (int viewIndex = 0; viewIndex < Views.Count; ++viewIndex)
        {
            var view = Views[viewIndex];
            if (!view.Active) continue;
            var target = view.Target;
            RenderView* colorView = target != null ? (target.TextureHandle != null ? target.TextureHandle.View : null) : frame.render_view;
            if (colorView == null && (target == null || target.DepthHandle == null)) continue;
            Format colorFormat = target != null ? target.ColorFormat : .bgra8_srgb;
            Format depthFormat = target != null ? target.DepthFormat : .undefined;
            ColorAttachment color = .(); color.render_view = colorView;
            color.load = view.ClearColorBuffer ? .clear : .load; color.clear = view.ClearColor;
            RenderingDesc rendering = .();
            if (colorView != null) rendering.colors = .() { data = &color, size = 1 };
            if (target != null && target.DepthHandle != null)
            {
                rendering.depth.render_view = target.DepthHandle.View;
                rendering.depth.load = view.ClearDepthBuffer ? .clear : .load;
                rendering.depth.clear = view.ClearDepth;
                if (GPU.GetTextureFormatInfo(depthFormat).stencil) rendering.stencil.render_view = target.DepthHandle.View;
            }
            GPU.Barrier(commands, .all_commands, .color_write | .depth_stencil_write | .shader_read, .all_commands, .shader_read | .color_write | .depth_stencil_write);
            GPU.BeginRenderPass(commands, rendering, .none);
            var viewport = view.Viewport;
            if (viewport.width <= 0) viewport.width = target != null ? target.Width : frame.extent.x;
            if (viewport.height <= 0) viewport.height = target != null ? target.Height : frame.extent.y;
            GPU.SetViewport(commands, viewport);
            GPU.SetScissor(commands, .() { x = (.)viewport.x, y = (.)viewport.y, width = (.)viewport.width, height = (.)viewport.height });
            GPU.SetTextureDescriptorHeap(commands, GPU.GpuRange(RenderManager.TextureDescriptors));
            GPU.SetSamplerDescriptorHeap(commands, GPU.GpuRange(RenderManager.SamplerDescriptors));
            for (var draw in ref draws)
            {
                if (draw.ViewId != viewIndex) continue;
                draw.Constants.View = view.View; draw.Constants.Projection = view.Projection;
                draw.Constants.ViewRectangle = .(viewport.x, viewport.y, viewport.width, viewport.height);
                var pipeline = Pipelines.Get(draw.Program, colorFormat, depthFormat, draw.State);
                if (pipeline == null) { success = false; continue; }
                GPU.BindPso(commands, pipeline);
                var depth = draw.State.Depth;
                if (depthFormat == .undefined) { depth.depth_test = false; depth.depth_write = false; }
                GPU.SetDepthStencil(commands, depth);
                ByteSpan root = .() { data = (.)&draw.Root, size = sizeof(DrawRoot) };
                if (draw.Root.LineMode != 0) GPU.Draw(commands, root, (draw.IndexCount > 0 ? draw.IndexCount : draw.VertexCount) / 2 * 6, 1, 0, 0);
                else if (draw.IndexCount > 0) GPU.DrawIndexed(commands, root, GPU.GpuRange(draw.IndexBuffer.Memory), draw.IndexBuffer.IndexType, draw.IndexCount, 1, draw.Root.FirstIndex, (.)draw.Root.FirstVertex, 0);
                else GPU.Draw(commands, root, draw.VertexCount, 1, draw.Root.FirstVertex, 0);
            }
            GPU.EndRenderPass(commands);
        }
        return success;
    }
    public void Reset()
    {
        draws.Clear(); pageIndex = 0; pageOffset = 0;
        for (var view in Views) view.Active = false;
        GPU.ResetCommandPool(Pool);
    }
}
