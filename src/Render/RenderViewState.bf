using System;
using NoGraphicsAPI;

namespace GameCore;

public class RenderViewState
{
    public RenderTexture Target;
    public Matrix4 View = .Identity;
    public Matrix4 Projection = .Identity;
    public Viewport Viewport = .() { width = 0, height = 0 };
    public ClearColor ClearColor = .();
    public float ClearDepth = 1;
    public bool ClearColorBuffer;
    public bool ClearDepthBuffer;
    public bool Active;
}
