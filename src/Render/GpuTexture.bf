using internal GameCore;
using System;
using System.Collections;
using NoGraphicsAPI;
using ImGui;

namespace GameCore;

public class GpuTexture
{
    public NoGraphicsAPI.Texture* Texture;
    public TextureHeap Memory;
    public RenderView* View;
    public Format Format;
    public uint32 Width, Height, Depth, MipLevels, LayerCount;
    public TextureType Type;
    public TextureUsage Usage;
    private Dictionary<uint64, uint32> subresourceDescriptors = new .() ~ delete _;
    public uint32 Descriptor;
    private ImGui.TextureID imageId;

    public ImGui.TextureID ImageId
    {
        get
        {
            if (imageId == default)
                imageId = ImGui.NgaAddTexture(Texture);
            return imageId;
        }
    }

    public this(uint32 width, uint32 height, Format format, TextureUsage usage, void* pixels = null, uint32 pixelBytes = 0, uint32 mipLevels = 1, TextureType type = .two_d, uint32 depth = 1, uint32 layerCount = 0)
    {
        RenderManager.ResourceLock.Enter();
        defer RenderManager.ResourceLock.Exit();
        Width = width;
        Height = height;
        Depth = depth;
        Format = format;
        MipLevels = mipLevels;
        LayerCount = layerCount != 0 ? layerCount : (type == .cube || type == .cube_array ? 6U : 1U);
        Type = type;
        Usage = usage;
        TextureDesc description = .();
        description.extent = .() { x = width, y = height, z = depth };
        description.type = type;
        description.layer_count = LayerCount;
        description.format = format;
        description.mip_levels = mipLevels;
        description.usage = usage | .sampled | .transfer_source | .transfer_destination;
        Memory = GPU.CreateTextureHeap(RenderManager.Device, GPU.GetTextureSizeAlign(RenderManager.Device, description).size);
        if (Memory.owner == null)
            Runtime.FatalError("Unable to allocate NGA texture memory");
        var commands = RenderManager.BeginUpload();
        Texture = GPU.CreateTexture(commands, description, Memory, 0);
        if (pixels != null && Texture != null)
        {
            var upload = RenderManager.AllocateUpload(pixelBytes);
            Internal.MemCpy(upload.cpu, pixels, pixelBytes);
            uint64 offset = 0;
            var formatInfo = GPU.GetTextureFormatInfo(format);
            for (uint32 mip = 0; mip < mipLevels; ++mip)
            {
                uint64 blocksX = (Math.Max(1U, width >> (int)mip) + formatInfo.block_extent.x - 1) / formatInfo.block_extent.x;
                uint64 blocksY = (Math.Max(1U, height >> (int)mip) + formatInfo.block_extent.y - 1) / formatInfo.block_extent.y;
                uint64 blocksZ = Math.Max(1U, depth >> (int)mip);
                uint64 size = blocksX * blocksY * blocksZ * LayerCount * formatInfo.bytes_per_block;
                if (offset + size > pixelBytes)
                    Runtime.FatalError("Texture upload is smaller than its mip chain");
                GPU.CopyMemoryToTexture(commands, .() { gpu = upload.gpu + offset, size = size }, Texture, .() { mip_level = mip });
                offset += size;
            }
        }
        if (Texture == null)
            Runtime.FatalError("Unable to create NGA texture");
        if ((usage & (.color_attachment | .depth_stencil_attachment)) != 0)
            View = GPU.CreateRenderView(Texture, .());
        Descriptor = RenderManager.AllocateTextureDescriptor();
        GPU.WriteTextureDescriptor(RenderManager.Device, RenderManager.TextureDescriptors.range.cpu + Descriptor * GPU.GetDeviceCaps(RenderManager.Device).texture_descriptor_size, Texture, .sampled, .());
    }

    public uint32 GetMipDescriptor(uint32 mip, bool writable = false)
    {
        RenderManager.ResourceLock.Enter();
        defer RenderManager.ResourceLock.Exit();
        if (mip >= MipLevels || (writable && (Usage & .storage) == 0))
            Runtime.FatalError("Invalid texture subresource descriptor");
        if (!writable && mip == 0 && MipLevels == 1)
            return Descriptor;
        uint64 key = (uint64)mip | (writable ? 1UL << 32 : 0);
        if (subresourceDescriptors.TryGetValue(key, let existing))
            return existing;
        uint32 descriptor = RenderManager.AllocateTextureDescriptor();
        TextureDescriptorDesc description = .();
        description.base_mip = mip;
        description.mip_count = 1;
        GPU.WriteTextureDescriptor(RenderManager.Device,
            RenderManager.TextureDescriptors.range.cpu + descriptor * GPU.GetDeviceCaps(RenderManager.Device).texture_descriptor_size,
            Texture, writable ? .storage : .sampled, description);
        subresourceDescriptors.Add(key, descriptor);
        return descriptor;
    }

    public static uint32 CalculateMipLevels(uint32 width, uint32 height, uint32 depth = 1)
    {
        uint32 largestDimension = Math.Max(width, Math.Max(height, depth));
        uint32 count = 1;
        while (largestDimension > 1)
        {
            largestDimension >>= 1;
            ++count;
        }
        return count;
    }

    public uint64 GetRegionByteCount(TextureCopyDesc region)
    {
        if (region.mip_level >= MipLevels)
            return 0;
        uint32 mipWidth = (.)Math.Max(1U, Width >> (int)region.mip_level);
        uint32 mipHeight = (.)Math.Max(1U, Height >> (int)region.mip_level);
        uint32 mipDepth = (.)Math.Max(1U, Depth >> (int)region.mip_level);
        if (region.offset.x >= mipWidth || region.offset.y >= mipHeight || region.offset.z >= mipDepth || region.base_slice >= LayerCount)
            return 0;
        uint32 copyWidth = region.extent.x != 0 ? region.extent.x : mipWidth - region.offset.x;
        uint32 copyHeight = region.extent.y != 0 ? region.extent.y : mipHeight - region.offset.y;
        uint32 copyDepth = region.extent.z != 0 ? region.extent.z : mipDepth - region.offset.z;
        uint32 slices = region.slice_count != 0 ? region.slice_count : LayerCount - region.base_slice;
        if (copyWidth > mipWidth - region.offset.x || copyHeight > mipHeight - region.offset.y || copyDepth > mipDepth - region.offset.z || slices > LayerCount - region.base_slice)
            return 0;
        var formatInfo = GPU.GetTextureFormatInfo(Format);
        if (region.offset.x % formatInfo.block_extent.x != 0 || region.offset.y % formatInfo.block_extent.y != 0)
            return 0;
        uint64 rowBytes = ((uint64)copyWidth + formatInfo.block_extent.x - 1) / formatInfo.block_extent.x * formatInfo.bytes_per_block;
        uint64 rowCount = ((uint64)copyHeight + formatInfo.block_extent.y - 1) / formatInfo.block_extent.y;
        uint64 rowPitch = region.row_pitch_bytes != 0 ? region.row_pitch_bytes : rowBytes;
        uint64 slicePitch = region.slice_pitch_bytes != 0 ? region.slice_pitch_bytes : rowPitch * rowCount;
        if (rowPitch < rowBytes || slicePitch < rowPitch * rowCount)
            return 0;
        return slicePitch * ((uint64)copyDepth * slices - 1) + rowPitch * (rowCount - 1) + rowBytes;
    }

    public void Update(RenderCommandBuffer commandBuffer, Span<uint8> pixels, TextureCopyDesc region)
    {
        commandBuffer.UploadTexture(this, pixels, region);
    }

    public ~this()
    {
        for (var entry in subresourceDescriptors)
            RenderManager.RetireTextureDescriptor(entry.value);
        RenderManager.RetireTexture(Texture, Memory, View, Descriptor, imageId);
    }
}
