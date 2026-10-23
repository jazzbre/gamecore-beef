using System;
using NoGraphicsAPI;

namespace GameCore;

public struct RenderState
{
    public BlendState Blend = .();
    public RasterizationState Rasterization = .();
    public DepthStencilState Depth = .();
    public uint8 ColorWriteMask = 15;
    public uint8 SecondaryColorWriteMask = 0;

    public bool HasSameSettings(ref Self other)
    {
        // Native state structs contain padding whose bytes need not match for identical settings.
        return ColorWriteMask == other.ColorWriteMask && SecondaryColorWriteMask == other.SecondaryColorWriteMask &&
            Blend.enabled == other.Blend.enabled &&
            BlendComponentsMatch(Blend.color, other.Blend.color) && BlendComponentsMatch(Blend.alpha, other.Blend.alpha) &&
            Rasterization.cull == other.Rasterization.cull &&
            Rasterization.depth_bias_constant == other.Rasterization.depth_bias_constant &&
            Rasterization.depth_bias_clamp == other.Rasterization.depth_bias_clamp &&
            Rasterization.depth_bias_slope == other.Rasterization.depth_bias_slope &&
            Depth.depth_test == other.Depth.depth_test && Depth.depth_write == other.Depth.depth_write &&
            Depth.depth_compare == other.Depth.depth_compare && Depth.stencil_test == other.Depth.stencil_test &&
            Depth.stencil_read_mask == other.Depth.stencil_read_mask && Depth.stencil_write_mask == other.Depth.stencil_write_mask &&
            StencilFacesMatch(Depth.front, other.Depth.front) && StencilFacesMatch(Depth.back, other.Depth.back);
    }

    private static bool BlendComponentsMatch(BlendComponentState first, BlendComponentState second)
    {
        return first.source == second.source && first.destination == second.destination && first.operation == second.operation;
    }

    private static bool StencilFacesMatch(StencilFaceState first, StencilFaceState second)
    {
        return first.compare == second.compare && first.fail == second.fail && first.pass == second.pass &&
            first.depth_fail == second.depth_fail && first.reference == second.reference;
    }

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
