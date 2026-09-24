#pragma once
#include <NoGraphicsAPIUtility/shader_platform.h>

struct DrawConstants
{
    float4x4 World;
    float4x4 View;
    float4x4 Projection;
    float4 ViewRectangle;
    float4 Color;
    float4 Time;
    float4 Settings;
    float4 TextureScale;
    GPU_PTR(float4) Instances;
    GPU_PTR(float4) FragmentInstances;
    GPU_PTR(float4) SphericalHarmonics;
    GPU_PTR(uint) Parameters;
    uint Textures[8];
    uint Samplers[8];
};

struct DrawRoot
{
    GPU_PTR(uint) Vertices;
    GPU_PTR(float4) Storage;
    GPU_PTR(DrawConstants) Constants;
    GPU_PTR(uint) Indices;
    uint Stride;
    uint LineMode;
    uint IndexSize;
    uint FirstVertex;
    uint FirstIndex;
    uint Attributes[18];
};

NGA_ROOT(DrawRoot, root);

struct MeshVaryings
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : TEXCOORD1;
    float4 outline : TEXCOORD2;
};

float4 TransformPosition(float3 position)
{
    DrawConstants data = root.Constants[0];
    return mul(mul(mul(float4(position, 1.0), data.World), data.View), data.Projection);
}

float4 SampleTexture(uint slot, float2 uv)
{
    DrawConstants data = root.Constants[0];
    Texture2D<float4> texture = ResourceDescriptorHeap[NonUniformResourceIndex(data.Textures[slot])];
    SamplerState sampler = SamplerDescriptorHeap[NonUniformResourceIndex(data.Samplers[slot])];
    return texture.Sample(sampler, uv);
}

uint2 TextureSize(uint slot)
{
    Texture2D<float4> texture = ResourceDescriptorHeap[NonUniformResourceIndex(root.Constants[0].Textures[slot])];
    uint width, height;
    texture.GetDimensions(width, height);
    return uint2(width, height);
}

uint LineVertex(uint index)
{
    if (root.IndexSize == 0) return root.FirstVertex + index;
    uint offset = (root.FirstIndex + index) * root.IndexSize;
    uint word = root.Indices.load_word(offset & ~3u);
    return root.FirstVertex + (root.IndexSize == 4 ? word : (word >> ((offset & 2) * 8)) & 65535);
}

float4 ReadAttribute(uint vertexId, uint attributeIndex)
{
    uint descriptor = root.Attributes[attributeIndex];
    if ((descriptor >> 16) == 65535) return float4(0, 0, 0, 1);
    uint count = (descriptor >> 16) & 7;
    uint type = (descriptor >> 19) & 15;
    bool normalized = (descriptor & (1u << 23)) != 0;
    uint base = vertexId * root.Stride + (descriptor & 65535);
    float4 result = float4(0, 0, 0, 1);
    for (uint component = 0; component < count; ++component)
    {
        uint offset = base + component * (type == 4 ? 4 : type == 0 ? 1 : 2);
        uint word = root.Vertices.load_word(offset & ~3u);
        uint value = word >> ((offset & 3) * 8);
        if (type == 4) result[component] = asfloat(word);
        else if (type == 0) result[component] = float(value & 255) / (normalized ? 255.0 : 1.0);
        else if (type == 2) result[component] = normalized ? max(-1.0, float(int(value << 16) >> 16) / 32767.0) : float(int(value << 16) >> 16);
        else if (type == 3) result[component] = f16tof32(value & 65535);
        else result[component] = float((root.Vertices.load_word(base) >> (component * 10)) & (component == 3 ? 3 : 1023)) / (normalized ? (component == 3 ? 3.0 : 1023.0) : 1.0);
    }
    return result;
}
