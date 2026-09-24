using internal GameCore;
using System;
using NoGraphicsAPI;

namespace GameCore;

public class RenderTexture
{
    public int Width { get; private set; }
    public int Height { get; private set; }
    public const int MaxColorAttachments = 8;
    private GpuTexture[MaxColorAttachments] colorTextures;
    private Format[MaxColorAttachments] colorFormats;
    public int ColorAttachmentCount { get; private set; }
    public GpuTexture TextureHandle => ColorAttachmentCount > 0 ? colorTextures[0] : null;
    public GpuTexture DepthHandle { get; private set; }
    public Format ColorFormat => ColorAttachmentCount > 0 ? colorFormats[0] : .undefined;
    public Format DepthFormat { get; private set; }

    public this(int width, int height, Format colorFormat = .rgba8_unorm, Format depthFormat = .undefined)
    {
        if (colorFormat != .undefined)
        {
            ColorAttachmentCount = 1;
            colorFormats[0] = colorFormat;
        }
        DepthFormat = depthFormat;
        Resize(width, height);
    }

    public this(int width, int height, Span<Format> colorFormats, Format depthFormat = .undefined)
    {
        if (colorFormats.Length > MaxColorAttachments)
            Runtime.FatalError("Too many color attachments");
        ColorAttachmentCount = colorFormats.Length;
        for (int index = 0; index < ColorAttachmentCount; ++index)
        {
            if (colorFormats[index] == .undefined)
                Runtime.FatalError("Color attachments require a defined format");
            this.colorFormats[index] = colorFormats[index];
        }
        DepthFormat = depthFormat;
        Resize(width, height);
    }

    public GpuTexture GetColorTexture(int index)
    {
        if (index < 0 || index >= ColorAttachmentCount)
            Runtime.FatalError("Color attachment index out of range");
        return colorTextures[index];
    }

    public Format GetColorFormat(int index)
    {
        if (index < 0 || index >= ColorAttachmentCount)
            Runtime.FatalError("Color attachment index out of range");
        return colorFormats[index];
    }

    public ~this()
    {
        for (var texture in colorTextures)
            delete texture;
        delete DepthHandle;
    }

    public void Resize(int width, int height)
    {
        if (Width == width && Height == height)
            return;
        for (var texture in colorTextures)
            delete texture;
        delete DepthHandle;
        colorTextures = default;
        DepthHandle = null;
        Width = width;
        Height = height;
        if (width <= 0 || height <= 0)
            return;
        for (int index = 0; index < ColorAttachmentCount; ++index)
            colorTextures[index] = new .((.)width, (.)height, colorFormats[index], .color_attachment);
        if (DepthFormat != .undefined)
            DepthHandle = new .((.)width, (.)height, DepthFormat, .depth_stencil_attachment);
        RenderManager.ResourceLock.Enter();
        defer RenderManager.ResourceLock.Exit();
        var commands = RenderManager.BeginUpload();
        ColorAttachment[MaxColorAttachments] colors = default;
        RenderingDesc rendering = .();
        for (int index = 0; index < ColorAttachmentCount; ++index)
            colors[index] = .() { render_view = colorTextures[index].View, load = .clear };
        rendering.colors = .() { data = &colors[0], size = (.)ColorAttachmentCount };
        if (DepthHandle != null)
        {
            rendering.depth.render_view = DepthHandle.View;
            rendering.depth.load = .clear;
            rendering.depth.clear = 1;
            if (GPU.GetTextureFormatInfo(DepthFormat).stencil)
            {
                rendering.stencil.render_view = DepthHandle.View;
                rendering.stencil.load = .clear;
            }
        }
        GPU.BeginRenderPass(commands, rendering, .none);
        GPU.EndRenderPass(commands);
    }
}
