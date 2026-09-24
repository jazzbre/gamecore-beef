using internal GameCore;
using System;
using NoGraphicsAPI;

namespace GameCore;

public class TextureReadback
{
    public GpuHeap Memory { get; private set; }
    private RenderCommandBuffer.CompletionStatus completionStatus;
    public bool Ready => completionStatus.Complete;
    public bool Cancelled => completionStatus.Cancelled;
    public uint64 ByteCount => Memory.range.size;

    public this(RenderCommandBuffer commandBuffer, GpuTexture source, TextureCopyDesc region = default)
    {
        uint64 size = source.GetRegionByteCount(region);
        if (size == 0)
            Runtime.FatalError("Invalid texture readback region");
        Memory = GPU.CreateGpuHeap(RenderManager.Device, size, .readback);
        if (Memory.range.cpu == null)
            Runtime.FatalError("Unable to allocate texture readback");
        completionStatus = commandBuffer.RetainCompletionStatus();
        commandBuffer.ReadTexture(source, this, region);
    }

    public ~this()
    {
        completionStatus.Release();
        RenderManager.Retire(Memory);
    }

    public bool CopyTo(Span<uint8> destination)
    {
        if (!Ready || (uint64)destination.Length < ByteCount)
            return false;
        Internal.MemCpy(destination.Ptr, Memory.range.cpu, (.)ByteCount);
        return true;
    }
}
