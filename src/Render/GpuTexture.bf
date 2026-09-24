using System;
using NoGraphicsAPI;
using ImGui;

namespace GameCore;

public class GpuTexture
{
    public NoGraphicsAPI.Texture* Texture;
    public TextureHeap Memory;
    public RenderView* View;
    public Format Format;
    public uint32 Width, Height;
    public uint32 Descriptor;
    private ImGui.TextureID imageId;

    public ImGui.TextureID ImageId
    {
        get
        {
            if (imageId == default) imageId = ImGui.NgaAddTexture(Texture);
            return imageId;
        }
    }
    public this(uint32 width, uint32 height, Format format, TextureUsage usage, void* pixels = null, uint32 pixelBytes = 0, uint32 mipLevels = 1)
    {
        RenderManager.ResourceLock.Enter(); defer RenderManager.ResourceLock.Exit();
        Width = width; Height = height; Format = format;
        TextureDesc description = .();
        description.extent = .() { x = width, y = height, z = 1 };
        description.format = format; description.mip_levels = mipLevels;
        description.usage = usage | .sampled | .transfer_source | .transfer_destination;
        Memory = GPU.CreateTextureHeap(RenderManager.Device, GPU.GetTextureSizeAlign(RenderManager.Device, description).size);
        if (Memory.owner == null) Runtime.FatalError("Unable to allocate NGA texture memory");
        var commands = GPU.BeginCommands(RenderManager.UploadPool);
        Texture = GPU.CreateTexture(commands, description, Memory, 0);
        GpuHeap upload = .();
        if (pixels != null && Texture != null)
        {
            upload = GPU.CreateGpuHeap(RenderManager.Device, pixelBytes, .cpu_visible);
            if (upload.range.cpu == null) Runtime.FatalError("Unable to allocate NGA texture upload");
            Internal.MemCpy(upload.range.cpu, pixels, pixelBytes);
            uint64 offset = 0;
            var formatInfo = GPU.GetTextureFormatInfo(format);
            for (uint32 mip = 0; mip < mipLevels; ++mip)
            {
                uint64 blocksX = (Math.Max(1U, width >> (int)mip) + formatInfo.block_extent.x - 1) / formatInfo.block_extent.x;
                uint64 blocksY = (Math.Max(1U, height >> (int)mip) + formatInfo.block_extent.y - 1) / formatInfo.block_extent.y;
                uint64 size = blocksX * blocksY * formatInfo.bytes_per_block;
                if (offset + size > pixelBytes) Runtime.FatalError("Texture upload is smaller than its mip chain");
                GPU.CopyMemoryToTexture(commands, .() { gpu = upload.range.gpu + offset, size = size }, Texture, .() { mip_level = mip });
                offset += size;
            }
            GPU.Barrier(commands, .transfer, .transfer_write, .all_commands, .shader_read);
        }
        RenderManager.SubmitUpload(commands);
        GPU.DestroyGpuHeap(upload);
        if (Texture == null) Runtime.FatalError("Unable to create NGA texture");
        if ((usage & (.color_attachment | .depth_stencil_attachment)) != 0) View = GPU.CreateRenderView(Texture, .());
        Descriptor = RenderManager.AllocateTextureDescriptor();
        GPU.WriteTextureDescriptor(RenderManager.Device, RenderManager.TextureDescriptors.range.cpu + Descriptor * GPU.GetDeviceCaps(RenderManager.Device).texture_descriptor_size, Texture, .sampled, .());
    }
    public ~this()
    {
        RenderManager.RetireTexture(Texture, Memory, View, Descriptor, imageId);
    }
}
