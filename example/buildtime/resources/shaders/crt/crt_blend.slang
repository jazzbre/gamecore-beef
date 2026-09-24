#include "../gamecore.slang"
struct CrtParameters
{
    float4 Blur;
    float4 Modulate;
    float4 ModulateAndTime;
    float4 ResolutionAndUseFrame;
    float4 ConfigA;
    float4 ConfigB;
    float4 ConfigC;
    float4 ConfigD;
    float4 ConfigE;
};
property CrtParameters parameters
{
    get { GPU_PTR(CrtParameters) pointer; pointer.address = root.Constants[0].Parameters.address; return pointer[0]; }
}
MeshVaryings vertexMain(uint vertexId : SV_VertexID)
{
    MeshVaryings output = {};
    output.position = float4(ReadAttribute(vertexId, 0).xy, 0, 1);
    output.uv = ReadAttribute(vertexId, 10).xy;
    return output;
}







float4 fragmentMain(MeshVaryings input) : SV_Target0
{
   float4 a = SampleTexture( 0u, input.uv ) * parameters.Modulate;
   float4 b = SampleTexture( 1u, input.uv );

   return max( a, b * 0.32 );
}