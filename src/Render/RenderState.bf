using System;
using NoGraphicsAPI;

namespace GameCore;

public struct RenderState
{
    public BlendState Blend = .();
    public RasterizationState Rasterization = .();
    public DepthStencilState Depth = .();
    public uint8 ColorWriteMask = 15;

    public static Self Opaque => .();

    public static Self Alpha
    {
        get
        {
            Self state = .();
            state.Blend.enabled = true;
            state.Blend.color.source = .source_alpha;
            state.Blend.color.destination = .one_minus_source_alpha;
            state.Blend.alpha.destination = .one_minus_source_alpha;
            return state;
        }
    }

    public static Self Premultiplied
    {
        get
        {
            var state = Alpha;
            state.Blend.color.source = .one;
            return state;
        }
    }

    public static Self DepthTested
    {
        get
        {
            Self state = .();
            state.Depth.depth_test = true;
            state.Depth.depth_write = true;
            return state;
        }
    }
}
