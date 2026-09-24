#include "gamecore.slang"

[numthreads(1, 1, 1)]
void incrementBuffer(uint3 position : SV_DispatchThreadID)
{
    root.Storage[0] = root.Storage[0] + float4(0.25, 0, 0, 0);
}

[numthreads(1, 1, 1)]
void writeTexture(uint3 position : SV_DispatchThreadID)
{
    RWTexture2D<float4> destination = ResourceDescriptorHeap[root.Constants[0].Parameters[0]];
    destination[position.xy] = root.Storage[0];
}
