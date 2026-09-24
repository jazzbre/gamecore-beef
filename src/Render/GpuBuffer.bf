using System;
using NoGraphicsAPI;

namespace GameCore;

public struct GpuBuffer
{
    public GpuHeap Memory;
    public MemoryType MemoryType;
    public VertexLayout Layout;
    public uint32 Count;
    public IndexType IndexType;
    public bool Valid => Memory.range.gpu != null;
    public static Self Null => default;

    public static Self CreateVertices(void* data, uint32 size, VertexLayout layout)
    {
        Self buffer = .() { Layout = layout, Count = size / layout.stride };
        buffer.Memory = GPU.CreateGpuHeap(RenderManager.Device, size, .cpu_visible);
        if (buffer.Memory.range.cpu != null)
            Internal.MemCpy(buffer.Memory.range.cpu, data, size);
        return buffer;
    }

    public static Self CreateIndices(void* data, uint32 size, IndexType type = .uint16)
    {
        Self buffer = .() { IndexType = type, Count = size / (type == .uint16 ? 2U : 4U) };
        buffer.Memory = GPU.CreateGpuHeap(RenderManager.Device, size, .cpu_visible);
        if (buffer.Memory.range.cpu != null)
            Internal.MemCpy(buffer.Memory.range.cpu, data, size);
        return buffer;
    }

    public static Self CreateStorage(uint32 byteCount)
    {
        return .() { Memory = GPU.CreateGpuHeap(RenderManager.Device, byteCount, .gpu_only), MemoryType = .gpu_only, Count = byteCount };
    }

    public void Update(RenderCommandBuffer commandBuffer, Span<uint8> data, uint64 byteOffset = 0)
    {
        commandBuffer.UpdateBuffer(this, data, byteOffset);
    }

    public void Dispose()
    {
        if (Memory.owner != null)
            RenderManager.Retire(Memory);
    }
}
