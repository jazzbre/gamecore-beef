#include "gamecore.slang"
MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    DrawConstants data = root.Constants[0];
    float2 position = ReadAttribute(vertexId, 0).xy;
    float3 offsetAndRadius = ReadAttribute(vertexId, 10).xyz;
    float4 viewPosition = mul(mul(float4(position + offsetAndRadius.xy * offsetAndRadius.z, 0, 1), data.World), data.View);
    viewPosition.xy = floor(viewPosition.xy);
    MeshVaryings output = {};
    output.position = mul(viewPosition, data.Projection);
    output.uv = offsetAndRadius.xy;
    output.color = ReadAttribute(vertexId, 11); output.color.xyz *= output.color.w;
    output.outline = ReadAttribute(vertexId, 12); output.outline.xyz *= output.outline.w;
    return output;
}
float4 fragmentMain(MeshVaryings input) : SV_Target0
{
    float radius = length(input.uv);
    float width = length(fwidth(input.uv));
    float mask = smoothstep(-1.0, width - 1.0, -radius);
    float outline = smoothstep(1.0 - 2.0 * width, 1.0 - width, radius);
    return (input.color + (input.outline - input.color * input.outline.a) * outline) * mask;
}
