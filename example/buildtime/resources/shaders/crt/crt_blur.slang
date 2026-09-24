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
   float2 uv = input.uv;
   float4 sum = SampleTexture( 0u, uv ) * 0.2270270270;
   sum += SampleTexture(0u, float2( uv.x - 4.0 * parameters.Blur.x, uv.y - 4.0 * parameters.Blur.y ) ) * 0.0162162162;
   sum += SampleTexture(0u, float2( uv.x - 3.0 * parameters.Blur.x, uv.y - 3.0 * parameters.Blur.y ) ) * 0.0540540541;
   sum += SampleTexture(0u, float2( uv.x - 2.0 * parameters.Blur.x, uv.y - 2.0 * parameters.Blur.y ) ) * 0.1216216216;
   sum += SampleTexture(0u, float2( uv.x - 1.0 * parameters.Blur.x, uv.y - 1.0 * parameters.Blur.y ) ) * 0.1945945946;
   sum += SampleTexture(0u, float2( uv.x + 1.0 * parameters.Blur.x, uv.y + 1.0 * parameters.Blur.y ) ) * 0.1945945946;
   sum += SampleTexture(0u, float2( uv.x + 2.0 * parameters.Blur.x, uv.y + 2.0 * parameters.Blur.y ) ) * 0.1216216216;
   sum += SampleTexture(0u, float2( uv.x + 3.0 * parameters.Blur.x, uv.y + 3.0 * parameters.Blur.y ) ) * 0.0540540541;
   sum += SampleTexture(0u, float2( uv.x + 4.0 * parameters.Blur.x, uv.y + 4.0 * parameters.Blur.y ) ) * 0.0162162162;
   return sum;
}
