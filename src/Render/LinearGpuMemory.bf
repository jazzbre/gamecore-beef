using System;
using System.Collections;
using NoGraphicsAPI;

namespace GameCore;

internal class LinearGpuMemory
{
    private const uint64 PageSize = 4UL * 1024 * 1024;
    private List<GpuHeap> pages = new .() ~ delete _;
    private int pageIndex;
    private uint64 pageOffset;
    public uint64 ByteCount { get; private set; }

    public ~this()
    {
        for (var page in pages)
            GPU.DestroyGpuHeap(page);
    }

    public GpuCpuRange Allocate(uint64 byteCount, uint64 alignment)
    {
        uint64 alignedSize = (byteCount + alignment - 1) & ~(alignment - 1);
        while (pageIndex < pages.Count && pageOffset + alignedSize > pages[pageIndex].range.size)
        {
            ++pageIndex;
            pageOffset = 0;
        }
        if (pageIndex == pages.Count)
            pages.Add(GPU.CreateGpuHeap(RenderManager.Device, Math.Max(alignedSize, PageSize), .cpu_visible));
        var page = pages[pageIndex];
        if (page.range.cpu == null)
            Runtime.FatalError("Unable to allocate NGA linear GPU memory");
        GpuCpuRange allocation = .() { cpu = page.range.cpu + pageOffset, gpu = page.range.gpu + pageOffset, size = byteCount };
        pageOffset += alignedSize;
        ByteCount += byteCount;
        return allocation;
    }

    public void Reset()
    {
        pageIndex = 0;
        pageOffset = 0;
        ByteCount = 0;
    }
}
