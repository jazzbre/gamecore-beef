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




#define cfg_modulate parameters.ModulateAndTime.xyz
#define cfg_time parameters.ModulateAndTime.w


#define cfg_resolution parameters.ResolutionAndUseFrame.xy
#define cfg_use_frame parameters.ResolutionAndUseFrame.z


#define cfg_curvature parameters.ConfigA.x
#define cfg_scanlines parameters.ConfigA.y
#define cfg_shadow_mask parameters.ConfigA.z
#define cfg_separation parameters.ConfigA.w


#define cfg_ghosting parameters.ConfigB.x
#define cfg_noise parameters.ConfigB.y
#define cfg_flicker parameters.ConfigB.z
#define cfg_vignette parameters.ConfigB.w


#define cfg_distortion parameters.ConfigC.x
#define cfg_aspect_lock parameters.ConfigC.y
#define cfg_hpos parameters.ConfigC.z
#define cfg_vpos parameters.ConfigC.w


#define cfg_hsize parameters.ConfigD.x
#define cfg_vsize parameters.ConfigD.y
#define cfg_contrast parameters.ConfigD.z
#define cfg_brightness parameters.ConfigD.w


#define cfg_saturation parameters.ConfigE.x
#define cfg_degauss parameters.ConfigE.y







float3 tsample( uint samp, float2 tc, float offs, float2 resolution )
{
    float3 s = pow( abs( SampleTexture( samp, float2( tc.x, 1.0-tc.y ) ).rgb), float3( 2.2, 2.2, 2.2 ) );
    return s*float3(1.25, 1.25, 1.25);
}

float3 filmic( float3 LinearColor )
{
   float3 x = max( float3(0.0, 0.0, 0.0), LinearColor-float3(0.004, 0.004, 0.004));
   return (x*(6.2*x+0.5))/(x*(6.2*x+1.7)+0.06);
}

float2 curve( float2 uv )
{
   uv = (uv - 0.5) * 2.0;
   uv *= float2( 1.049, 1.042);
   uv -= float2( -0.008, 0.008 );
   uv.x *= 1.0 + pow((abs(uv.y) / 5.0), 2.0);
   uv.y *= 1.0 + pow((abs(uv.x) / 4.0), 2.0);
   uv  = (uv / 2.0) + 0.5;
   return uv;
}

float rand(float2 co)
{
   return frac(sin(dot(co.xy ,float2(12.9898,78.233))) * 43758.5453);
}

float4 fragmentMain(MeshVaryings input) : SV_Target0
{

   float2 curved_uv = lerp( curve( input.uv ), input.uv, 0.4 );
   float scale = 0.04;
   float2 scuv = curved_uv*(1.0-scale)+scale/2.0+float2(0.003, -0.001);
   scuv = curved_uv;

   float3 col;
   float x =  sin(0.1*cfg_time+curved_uv.y*13.0)*sin(0.23*cfg_time+curved_uv.y*19.0)*sin(0.3+0.11*cfg_time+curved_uv.y*23.0)*0.0012;
   float o =sin(input.position.y/1.5)/cfg_resolution.x;
   x+=o*0.25;
   x*=0.2f;
   col.r = tsample(0u,float2(x+scuv.x+0.0009,scuv.y+0.0009),cfg_resolution.y/800.0, cfg_resolution ).x+0.02;
   col.g = tsample(0u,float2(x+scuv.x+0.0000,scuv.y-0.0011),cfg_resolution.y/800.0, cfg_resolution ).y+0.02;
   col.b = tsample(0u,float2(x+scuv.x-0.0015,scuv.y+0.0000),cfg_resolution.y/800.0, cfg_resolution ).z+0.02;
   float i = clamp(col.r*0.299 + col.g*0.587 + col.b*0.114, 0.0, 1.0 );
   i = pow( 1.0 - pow(i,2.0), 1.0 );
   i = (1.0-i) * 0.85 + 0.15;


   float ghs = 0.15;
   float3 r = tsample(1u, float2(x-0.014*1.0, -0.027)*0.85+0.007*float2( 0.35*sin(1.0/7.0 + 15.0*curved_uv.y + 0.9*cfg_time),
       0.35*sin( 2.0/7.0 + 10.0*curved_uv.y + 1.37*cfg_time) )+float2(scuv.x+0.001,scuv.y+0.001),
       5.5+1.3*sin( 3.0/9.0 + 31.0*curved_uv.x + 1.70*cfg_time),cfg_resolution).xyz*float3(0.5,0.25,0.25);
   float3 g = tsample(1u, float2(x-0.019*1.0, -0.020)*0.85+0.007*float2( 0.35*cos(1.0/9.0 + 15.0*curved_uv.y + 0.5*cfg_time),
       0.35*sin( 2.0/9.0 + 10.0*curved_uv.y + 1.50*cfg_time) )+float2(scuv.x+0.000,scuv.y-0.002),
       5.4+1.3*sin( 3.0/3.0 + 71.0*curved_uv.x + 1.90*cfg_time),cfg_resolution).xyz*float3(0.25,0.5,0.25);
   float3 b = tsample(1u, float2(x-0.017*1.0, -0.003)*0.85+0.007*float2( 0.35*sin(2.0/3.0 + 15.0*curved_uv.y + 0.7*cfg_time),
       0.35*cos( 2.0/3.0 + 10.0*curved_uv.y + 1.63*cfg_time) )+float2(scuv.x-0.002,scuv.y+0.000),
       5.3+1.3*sin( 3.0/7.0 + 91.0*curved_uv.x + 1.65*cfg_time),cfg_resolution).xyz*float3(0.25,0.25,0.5);

   col += pow(clamp(r * 3.0, float3(0.0, 0.0, 0.0), float3(1.0, 1.0, 1.0)), float3(2.0, 2.0, 2.0)) * i * ghs * (1.0-0.299);
   col += pow(clamp(g * 3.0, float3(0.0, 0.0, 0.0), float3(1.0, 1.0, 1.0)), float3(2.0, 2.0, 2.0)) * i * ghs * (1.0-0.587);
   col += pow(clamp(b * 3.0, float3(0.0, 0.0, 0.0), float3(1.0, 1.0, 1.0)), float3(2.0, 2.0, 2.0)) * i * ghs * (1.0-0.114);


   col *= float3(0.95,1.05,0.95);
   col = clamp(col*1.3 + col*0.75*col + col*1.25*col*col*col*col,float3(0.0, 0.0, 0.0),float3(10.0, 10.0, 10.0));


   float vig = (0.1 + 1.0*16.0*curved_uv.x*curved_uv.y*(1.0-curved_uv.x)*(1.0-curved_uv.y));
   vig = 1.3*pow(vig,0.5);
   col *= vig;


   float scans = clamp( 0.35+0.18*sin(6.0*cfg_time+curved_uv.y*cfg_resolution.y*cfg_scanlines), 0.0, 1.0);
   float s = pow(scans,0.9);
   col = col * float3(s, s, s);


   col*=1.0-0.23*(clamp((fmod(input.position.xy.x, cfg_shadow_mask))/2.0,0.0,1.0));


   col = filmic( col );



   float2 seed = curved_uv*cfg_resolution.xy;;

   col -= 0.015*pow(float3(rand( seed +cfg_time ), rand( seed +cfg_time*2.0 ), rand( seed +cfg_time * 3.0 ) ), float3(1.5, 1.5, 1.5) );


   col *= (1.0-0.004*(sin(50.0*cfg_time+curved_uv.y*2.0)*0.5+0.5));


   if (curved_uv.x < 0.0 || curved_uv.x > 1.0)
       col *= 0.0;
   if (curved_uv.y < 0.0 || curved_uv.y > 1.0)
       col *= 0.0;


   float2 fscale = float2( -0.019, -0.018 );
   float4 f=SampleTexture(2u,input.uv*((1.0)+2.0*fscale)-fscale-float2(-0.0, 0.005));
   f.xyz = lerp( f.xyz, float3(0.5,0.5,0.5), 0.5 );
   float fvig = clamp( -0.00+512.0*input.uv.x*input.uv.y*(1.0-input.uv.x)*(1.0-input.uv.y), 0.2, 0.8 );
   col = lerp( col, lerp( max( col, float3(0.0, 0.0, 0.0)), pow( abs( f.xyz ), float3( 1.4, 1.4, 1.4 ) ) * fvig, f.w * f.w), float3( cfg_use_frame, cfg_use_frame, cfg_use_frame ) );

   return float4( col, 1.0 )* float4( cfg_modulate, 1.0 );
}
