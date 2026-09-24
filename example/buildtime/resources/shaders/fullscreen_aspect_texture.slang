#include "gamecore.slang"
MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    MeshVaryings output = {};
    output.uv = float2(float(vertexId == 1 || vertexId == 3 || vertexId == 4), float(vertexId == 2 || vertexId == 4 || vertexId == 5));
    output.position = float4(output.uv * 2.0 - 1.0, 0, 1);
    return output;
}
float4 fragmentMain(MeshVaryings input) : SV_Target0
{
    float2 sourceSize = float2(TextureSize(0));
    float sourceAspect = sourceSize.x / max(sourceSize.y, 1.0);
    float viewAspect = root.Constants[0].ViewRectangle.z / max(root.Constants[0].ViewRectangle.w, 1.0);
    float2 visibleSize = viewAspect > sourceAspect ? float2(sourceAspect / viewAspect, 1) : float2(1, viewAspect / sourceAspect);
    float2 uv = (input.uv - 0.5) / visibleSize + 0.5;
    if (any(uv < 0) || any(uv > 1)) return float4(0,0,0,1);
    return SampleTexture(0, uv);
}
