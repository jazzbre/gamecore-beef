#include "gamecore.slang"
MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    float3 position = ReadAttribute(vertexId, 0).xyz;
#ifdef SKINNED
    DrawConstants data = root.Constants[0];
    uint4 joints = uint4(round(ReadAttribute(vertexId, 8) * 255.0));
    float4 weights = ReadAttribute(vertexId, 9);
    float3 skinned = 0.0;
    for (uint influence = 0; influence < 4; ++influence)
    {
        uint row = joints[influence] * 3;
        float4 local = float4(position, 1.0);
        skinned += float3(dot(data.Instances[row], local), dot(data.Instances[row + 1], local), dot(data.Instances[row + 2], local)) * weights[influence];
    }
    position = skinned;
#endif
    MeshVaryings output = {};
    output.position = TransformPosition(position);
    output.uv = ReadAttribute(vertexId, 10).xy;
    output.color = (root.Attributes[4] >> 16) == 65535 ? float4(1.0) : ReadAttribute(vertexId, 4);
    return output;
}
float4 fragmentMain(MeshVaryings input) : SV_Target0
{
    return SampleTexture(0, input.uv) * input.color * root.Constants[0].Color;
}
