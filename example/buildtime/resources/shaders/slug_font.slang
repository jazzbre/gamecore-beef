// Slug coverage algorithm, Copyright 2017 Eric Lengyel, MIT License.
// Adapted from bgfx examples/51-gpufont/fs_slug.sc.
#include "gamecore.slang"

struct SlugVaryings
{
    float4 position : SV_Position;
    float2 samplePosition : TEXCOORD0;
    nointerpolation float4 bandTransform : TEXCOORD1;
    nointerpolation uint4 glyphBands : TEXCOORD2;
};

SlugVaryings vertexMain(uint vertexId : SV_VertexID)
{
    DrawConstants data = root.Constants[0];
    float4 vertexPosition = ReadAttribute(vertexId, 0);
    float4 sample = ReadAttribute(vertexId, 10);
    float2 dilation = vertexPosition.zw * 0.5;
    float2 localPosition = vertexPosition.xy + dilation + data.Settings.yz;
    SlugVaryings output = {};
    // NGA clip Y points down; glyph outlines use Y up.
#ifdef WORLD
    output.position = mul(mul(float4(data.World[3].xyz, 1), data.View), data.Projection);
    output.position.xy += localPosition * float2(2.0, -2.0) / data.ViewRectangle.zw * output.position.w;
#else
    float2 pixelPosition = data.World[3].xy + float2(localPosition.x, -localPosition.y);
    output.position = float4(pixelPosition * 2.0 / data.ViewRectangle.zw - 1.0, 0, 1);
#endif
    output.samplePosition = sample.xy + dilation / data.Settings.x;
    output.bandTransform = ReadAttribute(vertexId, 11);
    uint glyphLocation = asuint(sample.z);
    uint bandMaximum = asuint(sample.w);
    output.glyphBands = uint4(glyphLocation & 65535, glyphLocation >> 16, bandMaximum & 65535, bandMaximum >> 16);
    return output;
}

float4 LoadSlugTexel(uint slot, int2 location)
{
    Texture2D<float4> texture = ResourceDescriptorHeap[NonUniformResourceIndex(root.Constants[0].Textures[slot])];
    return texture.Load(int3(location, 0));
}

uint GetRootEligibility(float first, float control, float last)
{
    uint signs = (first < 0 ? 1 : 0) + (control < 0 ? 2 : 0) + (last < 0 ? 4 : 0);
    return (0x2E74u >> signs) & 0x0101u;
}

float2 SolveHorizontalCurve(float4 firstAndControl, float2 last)
{
    float2 quadratic = firstAndControl.xy - firstAndControl.zw * 2.0 + last;
    float2 linear = firstAndControl.xy - firstAndControl.zw;
    float2 roots;
    if (abs(quadratic.y) < 1.0 / 65536.0)
    {
        roots = firstAndControl.y * 0.5 / linear.y;
    }
    else
    {
        float discriminant = sqrt(max(linear.y * linear.y - quadratic.y * firstAndControl.y, 0.0));
        roots = (linear.y + float2(-discriminant, discriminant)) / quadratic.y;
    }
    return (quadratic.x * roots - linear.x * 2.0) * roots + firstAndControl.x;
}

float2 SolveVerticalCurve(float4 firstAndControl, float2 last)
{
    float2 quadratic = firstAndControl.xy - firstAndControl.zw * 2.0 + last;
    float2 linear = firstAndControl.xy - firstAndControl.zw;
    float2 roots;
    if (abs(quadratic.x) < 1.0 / 65536.0)
    {
        roots = firstAndControl.x * 0.5 / linear.x;
    }
    else
    {
        float discriminant = sqrt(max(linear.x * linear.x - quadratic.x * firstAndControl.x, 0.0));
        roots = (linear.x + float2(-discriminant, discriminant)) / quadratic.x;
    }
    return (quadratic.y * roots - linear.y * 2.0) * roots + firstAndControl.y;
}

float SlugCoverage(SlugVaryings input)
{
    float2 pixelsPerEm = 1.0 / max(fwidth(input.samplePosition), float2(1.0 / 65536.0));
    int2 bandMaximum = int2(input.glyphBands.zw);
    int2 bandIndex = clamp(int2(input.samplePosition * input.bandTransform.xy + input.bandTransform.zw), int2(0), bandMaximum);
    int2 glyphLocation = int2(input.glyphBands.xy);
    float4 horizontalHeader = LoadSlugTexel(1, glyphLocation + int2(bandIndex.y, 0));
    int horizontalCount = int(horizontalHeader.x + 0.5);
    int horizontalOffset = int(horizontalHeader.y + 0.5);
    float horizontalCoverage = 0;
    float horizontalWeight = 0;
    for (int curveIndex = 0; curveIndex < horizontalCount; curveIndex++)
    {
        int2 curveLocation = int2(LoadSlugTexel(1, glyphLocation + int2(horizontalOffset + curveIndex, 0)).xy + 0.5);
        float4 firstAndControl = LoadSlugTexel(0, curveLocation) - input.samplePosition.xyxy;
        float2 last = LoadSlugTexel(0, curveLocation + int2(1, 0)).xy - input.samplePosition;
        if (max(max(firstAndControl.x, firstAndControl.z), last.x) * pixelsPerEm.x < -0.5)
        {
            break;
        }
        uint eligibility = GetRootEligibility(firstAndControl.y, firstAndControl.w, last.y);
        if (eligibility != 0)
        {
            float2 intersections = SolveHorizontalCurve(firstAndControl, last) * pixelsPerEm.x;
            if ((eligibility & 1) != 0)
            {
                horizontalCoverage += saturate(intersections.x + 0.5);
                horizontalWeight = max(horizontalWeight, saturate(1.0 - abs(intersections.x) * 2.0));
            }
            if (eligibility > 1)
            {
                horizontalCoverage -= saturate(intersections.y + 0.5);
                horizontalWeight = max(horizontalWeight, saturate(1.0 - abs(intersections.y) * 2.0));
            }
        }
    }
    float4 verticalHeader = LoadSlugTexel(1, glyphLocation + int2(bandMaximum.y + 1 + bandIndex.x, 0));
    int verticalCount = int(verticalHeader.x + 0.5);
    int verticalOffset = int(verticalHeader.y + 0.5);
    float verticalCoverage = 0;
    float verticalWeight = 0;
    for (int curveIndex = 0; curveIndex < verticalCount; curveIndex++)
    {
        int2 curveLocation = int2(LoadSlugTexel(1, glyphLocation + int2(verticalOffset + curveIndex, 0)).xy + 0.5);
        float4 firstAndControl = LoadSlugTexel(0, curveLocation) - input.samplePosition.xyxy;
        float2 last = LoadSlugTexel(0, curveLocation + int2(1, 0)).xy - input.samplePosition;
        if (max(max(firstAndControl.y, firstAndControl.w), last.y) * pixelsPerEm.y < -0.5)
        {
            break;
        }
        uint eligibility = GetRootEligibility(firstAndControl.x, firstAndControl.z, last.x);
        if (eligibility != 0)
        {
            float2 intersections = SolveVerticalCurve(firstAndControl, last) * pixelsPerEm.y;
            if ((eligibility & 1) != 0)
            {
                verticalCoverage -= saturate(intersections.x + 0.5);
                verticalWeight = max(verticalWeight, saturate(1.0 - abs(intersections.x) * 2.0));
            }
            if (eligibility > 1)
            {
                verticalCoverage += saturate(intersections.y + 0.5);
                verticalWeight = max(verticalWeight, saturate(1.0 - abs(intersections.y) * 2.0));
            }
        }
    }
    float weightedCoverage = abs(horizontalCoverage * horizontalWeight + verticalCoverage * verticalWeight) /
        max(horizontalWeight + verticalWeight, 1.0 / 65536.0);
    return saturate(max(weightedCoverage, min(abs(horizontalCoverage), abs(verticalCoverage))));
}

float4 fragmentMain(SlugVaryings input) : SV_Target0
{
    float4 color = root.Constants[0].Color;
    color.a *= SlugCoverage(input);
    color.rgb *= color.a;
    return color;
}
