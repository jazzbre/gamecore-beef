#include "gamecore.slang"

MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    MeshVaryings output = {};
    output.position = TransformPosition(ReadAttribute(vertexId, 0).xyz);
    return output;
}

struct MultipleTargetOutput
{
    float4 color : SV_Target0;
    float4 alternateColor : SV_Target1;
};

MultipleTargetOutput fragmentMain(MeshVaryings input)
{
    MultipleTargetOutput output;
    output.color = root.Constants[0].Color;
    output.alternateColor = output.color.grba;
    return output;
}
