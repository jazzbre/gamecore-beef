#include "gamecore.slang"
MeshVaryings EvaluateVertex(uint vertexId)
{
    DrawConstants data = root.Constants[0];
    MeshVaryings output = {};
#ifdef CUBE
    uint instanceId = vertexId >> 3;
    float4 centerAndSize = root.Storage[instanceId * 2];
    output.color = root.Storage[instanceId * 2 + 1];
    uint3 corner = uint3(vertexId & 1, (vertexId & 4) >> 2, (vertexId & 2) >> 1);
    float3 camera = -data.View[3].xyz - centerAndSize.xyz;
    if (camera.x > 0) corner.x = 1 - corner.x;
    if (camera.y > 0) corner.y = 1 - corner.y;
    if (camera.z > 0) corner.z = 1 - corner.z;
    output.position = TransformPosition(centerAndSize.xyz + (float3(corner) * 2.0 - 1.0) * centerAndSize.w);
#else
    float3 position = ReadAttribute(vertexId, 0).xyz;
    output.color = ReadAttribute(vertexId, 10);
#ifdef SCREEN
    output.position = float4(position.xy * 2.0 / data.ViewRectangle.zw - 1.0, 0, 1);
#else
    output.position = TransformPosition(position);
#endif
#endif
    return output;
}
MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    if (root.LineMode == 0) return EvaluateVertex(vertexId);
    uint corner = vertexId % 6;
    MeshVaryings first = EvaluateVertex(LineVertex(vertexId / 6 * 2));
    MeshVaryings second = EvaluateVertex(LineVertex(vertexId / 6 * 2 + 1));
    MeshVaryings output = corner == 1 || corner == 2 || corner == 4 ? second : first;
    float2 extent = root.Constants[0].ViewRectangle.zw;
    float2 direction = (second.position.xy / second.position.w - first.position.xy / first.position.w) * extent;
    float2 normal = float2(-direction.y, direction.x) / max(length(direction), 0.0001);
    output.position.xy += normal / extent * output.position.w * (corner == 0 || corner == 1 || corner == 5 ? -1.0 : 1.0);
    return output;
}
float4 fragmentMain(MeshVaryings input) : SV_Target0 { return input.color; }
