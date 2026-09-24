using System;

namespace GameCore;

[CRepr]
public struct DrawConstants
{
    public Matrix4 World;
    public Matrix4 View;
    public Matrix4 Projection;
    public Vector4 ViewRectangle;
    public Vector4 Color;
    public Vector4 Time;
    public Vector4 Settings;
    public Vector4 TextureScale;
    public Vector4* Instances;
    public Vector4* FragmentInstances;
    public Vector4* SphericalHarmonics;
    public void* Parameters;
    public uint32[8] Textures;
    public uint32[8] Samplers;
}

[CRepr]
public struct DrawRoot
{
    public void* Vertices;
    public void* Storage;
    public DrawConstants* Constants;
    public void* Indices;
    public uint32 Stride;
    public uint32 LineMode;
    public uint32 IndexSize;
    public uint32 FirstVertex;
    public uint32 FirstIndex;
    public uint32[18] Attributes;
}
