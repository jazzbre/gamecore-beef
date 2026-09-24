#include "gamecore.slang"
MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    DrawConstants data = root.Constants[0];
    float3 position = ReadAttribute(vertexId, 0).xyz;
    uint instance = uint(position.z);
    float4 rowX = data.Instances[instance];
    float4 rowY = data.Instances[instance + 1];
    float4 tile = data.Instances[instance + 3];
    float2 size = data.TextureScale.xy * (tile.zw - tile.xy);
    float4 local = float4(position.xy * size, 0, 1);
    local.xy = float2(dot(local, rowX), dot(local, rowY));
    MeshVaryings output = {};
#ifdef WORLD
    float4 anchor = mul(mul(float4(0,0,0,1), data.World), data.View);
    output.position = mul(anchor, data.Projection);
    output.position.xy += local.xy * float2(2.0, -2.0) / data.ViewRectangle.zw * output.position.w;
#else
    float2 pixelPosition = float2(data.World[3].x, -data.World[3].y) + local.xy;
    output.position = float4(pixelPosition * float2(2.0, -2.0) / data.ViewRectangle.zw - 1.0, 0, 1);
#endif
    output.uv = float2(lerp(tile.x, tile.z, position.x), lerp(tile.w, tile.y, position.y));
    output.color = data.Instances[instance + 2];
    return output;
}
float4 fragmentMain(MeshVaryings input) : SV_Target0 { return SampleTexture(0, input.uv) * input.color; }
