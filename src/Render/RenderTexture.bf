using System;
using NoGraphicsAPI;
namespace GameCore;
public class RenderTexture
{
    public int Width { get; private set; }
    public int Height { get; private set; }
    public GpuTexture TextureHandle { get; private set; }
    public GpuTexture DepthHandle { get; private set; }
    public Format ColorFormat { get; private set; }
    public Format DepthFormat { get; private set; }
    public this(int width, int height, Format colorFormat = .rgba8_unorm, Format depthFormat = .undefined)
    { ColorFormat = colorFormat; DepthFormat = depthFormat; Resize(width, height); }
    public ~this() { delete TextureHandle; delete DepthHandle; }
    public void Resize(int width, int height)
    {
        if (Width == width && Height == height) return;
        delete TextureHandle; delete DepthHandle; TextureHandle = null; DepthHandle = null;
        Width = width; Height = height;
        if (width <= 0 || height <= 0) return;
        if (ColorFormat != .undefined) TextureHandle = new .((.)width, (.)height, ColorFormat, .color_attachment);
        if (DepthFormat != .undefined) DepthHandle = new .((.)width, (.)height, DepthFormat, .depth_stencil_attachment);
    }
}
