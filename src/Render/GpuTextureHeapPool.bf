using System;
using System.Collections;
using System.Threading;
using NoGraphicsAPI;

namespace GameCore;

/// Places textures in a few large heaps instead of one heap each. A heap costs a fraction of
/// a millisecond to create, which adds up to seconds for thousands of small textures.
public class GpuTextureHeapPool
{
    public const uint64 BlockSize = 64UL * 1024 * 1024;

    public struct Allocation
    {
        public TextureHeap Heap;
        public uint64 Offset;
        public uint64 Size;
        public bool IsZeroed;
    }

    private struct FreeRange : this(uint64 Offset, uint64 Size)
    {
    }

    private class Block
    {
        public TextureHeap Heap;
        public uint64 Capacity;
        /// Memory from here on has never held a texture, so it still reads as zero.
        public uint64 UntouchedOffset;
        public List<FreeRange> FreeRanges = new .() ~ delete _;
    }

    private List<Block> blocks = new .() ~ DeleteContainerAndItems!(_);
    private Monitor monitor = new .() ~ delete _;

    public ~this()
    {
        for (let block in blocks)
        {
            GPU.DestroyTextureHeap(block.Heap);
        }
    }

    private static uint64 AlignUp(uint64 value, uint64 alignment)
    {
        return (value + alignment - 1) / alignment * alignment;
    }

    public Allocation Allocate(uint64 size, uint64 alignment)
    {
        using (monitor.Enter())
        {
            for (let block in blocks)
            {
                let offset = AlignUp(block.UntouchedOffset, alignment);
                if (offset + size <= block.Capacity)
                {
                    block.UntouchedOffset = offset + size;
                    return .() { Heap = block.Heap, Offset = offset, Size = size, IsZeroed = true };
                }
            }
            for (let block in blocks)
            {
                for (int rangeIndex = 0; rangeIndex < block.FreeRanges.Count; rangeIndex++)
                {
                    let range = block.FreeRanges[rangeIndex];
                    let offset = AlignUp(range.Offset, alignment);
                    let rangeEnd = range.Offset + range.Size;
                    if (offset + size > rangeEnd)
                    {
                        continue;
                    }
                    block.FreeRanges.RemoveAt(rangeIndex);
                    if (offset + size < rangeEnd)
                    {
                        block.FreeRanges.Insert(rangeIndex, FreeRange(offset + size, rangeEnd - offset - size));
                    }
                    if (offset > range.Offset)
                    {
                        block.FreeRanges.Insert(rangeIndex, FreeRange(range.Offset, offset - range.Offset));
                    }
                    return .() { Heap = block.Heap, Offset = offset, Size = size, IsZeroed = false };
                }
            }
            let block = new Block();
            block.Capacity = Math.Max(BlockSize, AlignUp(size, alignment));
            block.Heap = GPU.CreateTextureHeap(RenderManager.Device, block.Capacity);
            if (block.Heap.owner == null)
            {
                delete block;
                return .();
            }
            block.UntouchedOffset = size;
            blocks.Add(block);
            return .() { Heap = block.Heap, Offset = 0, Size = size, IsZeroed = true };
        }
    }

    public void Free(TextureHeap heap, uint64 offset, uint64 size)
    {
        using (monitor.Enter())
        {
            for (let block in blocks)
            {
                if (block.Heap.owner != heap.owner)
                {
                    continue;
                }
                var ranges = block.FreeRanges;
                int insertIndex = 0;
                while ((insertIndex < ranges.Count) && (ranges[insertIndex].Offset < offset))
                {
                    insertIndex++;
                }
                ranges.Insert(insertIndex, FreeRange(offset, size));
                if ((insertIndex + 1 < ranges.Count) && (ranges[insertIndex].Offset + ranges[insertIndex].Size == ranges[insertIndex + 1].Offset))
                {
                    ranges[insertIndex] = .(ranges[insertIndex].Offset, ranges[insertIndex].Size + ranges[insertIndex + 1].Size);
                    ranges.RemoveAt(insertIndex + 1);
                }
                if ((insertIndex > 0) && (ranges[insertIndex - 1].Offset + ranges[insertIndex - 1].Size == ranges[insertIndex].Offset))
                {
                    ranges[insertIndex - 1] = .(ranges[insertIndex - 1].Offset, ranges[insertIndex - 1].Size + ranges[insertIndex].Size);
                    ranges.RemoveAt(insertIndex);
                }
                return;
            }
        }
    }
}
