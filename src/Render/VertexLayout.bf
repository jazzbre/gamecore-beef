using System;

namespace GameCore;

public enum VertexAttribute { Position, Normal, Tangent, Bitangent, Color0, Color1, Color2, Color3, Indices, Weight, TexCoord0, TexCoord1, TexCoord2, TexCoord3, TexCoord4, TexCoord5, TexCoord6, TexCoord7, Count }
public enum VertexComponent { Uint8, Uint10, Int16, Half, Float, Count }

[CRepr]
public struct VertexLayout
{
    public uint32 hash;
    public uint16 stride;
    public uint16[18] offset;
    public uint16[18] attributes;
    public void Begin() mut { this = default; for (var attribute in ref attributes) attribute = uint16.MaxValue; }
    public void Add(VertexAttribute attribute, uint8 count, VertexComponent component, bool normalized = false, bool asInteger = false) mut
    {
        offset[(int)attribute] = stride;
        attributes[(int)attribute] = (uint16)(count | ((uint32)component << 3) | (normalized ? 128U : 0U) | (asInteger ? 256U : 0U));
        stride += component == .Uint10 ? 4 : (uint16)(count * (component == .Float ? 4 : component == .Uint8 ? 1 : 2));
    }
    public void End() mut { hash = 2166136261; for (var attribute in attributes) hash = (hash ^ attribute) &* 16777619; }
}
