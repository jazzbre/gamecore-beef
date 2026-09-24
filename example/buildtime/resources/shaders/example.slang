#include "gamecore.slang"
MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    MeshVaryings output = {};
    output.position = TransformPosition(float3(ReadAttribute(vertexId, 0).xy, 0.0));
    output.uv = ReadAttribute(vertexId, 10).xy;
    output.color = ReadAttribute(vertexId, 4);
    return output;
}
float4 fragmentMain(MeshVaryings input) : SV_Target0
{
    return SampleTexture(0, input.uv) * input.color * root.Constants[0].Color;
}
