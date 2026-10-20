using internal GameCore;
using System;
using NoGraphicsAPI;

namespace GameCore;

public class FrameCapture
{
    // Owned by the caller; release the capture before the rendering device is shut down.
    internal RenderTexture Target;
    internal RenderManager.FramePresenter Presenter;
    internal TextureReadback Readback;
    internal bool cancelled;

    public int Width => Target?.Width ?? 0;
    public int Height => Target?.Height ?? 0;
    public uint64 ByteCount => Readback?.ByteCount ?? 0;
    public bool Ready => Readback?.Ready ?? false;
    public bool Cancelled => cancelled || (Readback?.Cancelled ?? false);
    public uint64 FrameNumber { get; internal set; }

    internal this(RenderManager.FramePresenter presenter)
    {
        Presenter = presenter;
    }

    internal void Initialize(uint32x2 extent)
    {
        Target = new .((int)extent.x, (int)extent.y, .bgra8_srgb);
    }

    public bool CopyTo(Span<uint8> destination)
    {
        return Readback?.CopyTo(destination) ?? false;
    }

    public ~this()
    {
        RenderManager.CancelFrameCapture(this);
        delete Readback;
        delete Target;
    }
}
