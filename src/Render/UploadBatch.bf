using internal GameCore;
using System;
using NoGraphicsAPI;

namespace GameCore;

internal class UploadBatch
{
    public CommandPool* Pool;
    public CommandBuffer* Commands;
    public TimelinePoint Completion;
    private LinearGpuMemory memory = new .() ~ delete _;
    public uint64 ByteCount => memory.ByteCount;

    public this()
    {
        Pool = GPU.CreateCommandPool(RenderManager.Device, 0);
        if (Pool == null)
            Runtime.FatalError("Unable to create upload command pool");
    }

    public ~this()
    {
        GPU.DestroyCommandPool(Pool);
    }

    public GpuCpuRange Allocate(uint64 byteCount)
    {
        return memory.Allocate(byteCount, 512);
    }

    public void Reset()
    {
        GPU.ResetCommandPool(Pool);
        Completion = default;
        Commands = null;
        memory.Reset();
    }
}
