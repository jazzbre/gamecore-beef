using System;
using System.Collections;
using NoGraphicsAPI;

namespace GameCore;

internal class UploadBatch
{
    public CommandPool* Pool;
    public CommandBuffer* Commands;
    public TimelinePoint Completion;
    public uint64 ByteCount;
    private List<GpuHeap> pages = new .() ~ delete _;
    private int pageIndex;
    private uint64 pageOffset;

    public this()
    {
        Pool = GPU.CreateCommandPool(RenderManager.Device, 0);
        if (Pool == null)
            Runtime.FatalError("Unable to create upload command pool");
    }

    public ~this()
    {
        for (var page in pages)
            GPU.DestroyGpuHeap(page);
        GPU.DestroyCommandPool(Pool);
    }

    public GpuCpuRange Allocate(uint64 byteCount)
    {
        uint64 alignedSize = (byteCount + 511) & ~511UL;
        while (pageIndex < pages.Count && pageOffset + alignedSize > pages[pageIndex].range.size)
        {
            ++pageIndex;
            pageOffset = 0;
        }
        if (pageIndex == pages.Count)
            pages.Add(GPU.CreateGpuHeap(RenderManager.Device, Math.Max(alignedSize, 4UL * 1024 * 1024), .cpu_visible));
        var page = pages[pageIndex];
        if (page.range.cpu == null)
            Runtime.FatalError("Unable to allocate upload staging memory");
        GpuCpuRange allocation = .() { cpu = page.range.cpu + pageOffset, gpu = page.range.gpu + pageOffset, size = byteCount };
        pageOffset += alignedSize;
        ByteCount += byteCount;
        return allocation;
    }

    public void Reset()
    {
        GPU.ResetCommandPool(Pool);
        Completion = default;
        Commands = null;
        pageIndex = 0;
        pageOffset = 0;
        ByteCount = 0;
    }
}
