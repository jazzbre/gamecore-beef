using System;
using System.Collections;
using NoGraphicsAPI;

namespace GameCore;

public class PipelineCache
{
    struct Key : IHashable, IEquatable<Key>
    {
        public uint64 Program;
        public uint64 State;
        public Format Color;
        public Format Depth;
        public float DepthBiasConstant;
        public float DepthBiasClamp;
        public float DepthBiasSlope;

        public int GetHashCode()
        {
            int hash = Program.GetHashCode();
            hash = (hash &* 397) ^ State.GetHashCode();
            hash = (hash &* 397) ^ (int)Color;
            hash = (hash &* 397) ^ (int)Depth;
            hash = (hash &* 397) ^ (DepthBiasConstant == 0 ? 0 : DepthBiasConstant.GetHashCode());
            hash = (hash &* 397) ^ (DepthBiasClamp == 0 ? 0 : DepthBiasClamp.GetHashCode());
            return (hash &* 397) ^ (DepthBiasSlope == 0 ? 0 : DepthBiasSlope.GetHashCode());
        }
        public bool Equals(Key other) => Program == other.Program && State == other.State
            && Color == other.Color && Depth == other.Depth && DepthBiasConstant == other.DepthBiasConstant
            && DepthBiasClamp == other.DepthBiasClamp && DepthBiasSlope == other.DepthBiasSlope;
        public static bool operator ==(Key first, Key second) => first.Equals(second);
    }

    private Device* device;
    private Dictionary<Key, PSO*> pipelines = new .() ~ delete _;
    public int Count => pipelines.Count;

    public this(Device* device) { this.device = device; }
    public ~this() { Clear(); }

    // Submit all command buffers referencing this cache before clearing it.
    public void Clear()
    {
        if (pipelines.Count == 0) return;
        GPU.WaitIdle(device);
        for (var entry in pipelines) GPU.DestroyPso(entry.value);
        pipelines.Clear();
    }

    public PSO* Get(ShaderProgram program, Format color, Format depth, RenderState state)
    {
        uint64 packedState = (uint64)state.ColorWriteMask | ((uint64)state.Rasterization.cull << 4)
            | (state.Blend.enabled ? 1UL << 6 : 0)
            | ((uint64)state.Blend.color.source << 7) | ((uint64)state.Blend.color.destination << 11)
            | ((uint64)state.Blend.color.operation << 15) | ((uint64)state.Blend.alpha.source << 18)
            | ((uint64)state.Blend.alpha.destination << 22) | ((uint64)state.Blend.alpha.operation << 26);
        Key key = .() { Program = program.Id, State = packedState, Color = color, Depth = depth,
            DepthBiasConstant = state.Rasterization.depth_bias_constant, DepthBiasClamp = state.Rasterization.depth_bias_clamp,
            DepthBiasSlope = state.Rasterization.depth_bias_slope };
        if (pipelines.TryGetValue(key, let pipeline)) return pipeline;
        ColorTargetDesc target = .();
        target.format = color;
        target.blend = state.Blend;
        target.write_mask = state.ColorWriteMask;
        GraphicsPSODesc description = .();
        description.vertex_spirv = .() { data = program.VertexCode.Ptr, size = (.)program.VertexCode.Count };
        description.fragment_spirv = .() { data = program.FragmentCode.Ptr, size = (.)program.FragmentCode.Count };
        if (color != .undefined) description.color_targets = .() { data = &target, size = 1 };
        description.depth_format = depth;
        if (GPU.GetTextureFormatInfo(depth).stencil) description.stencil_format = depth;
        description.rasterization = state.Rasterization;
        PSO* createdPipeline = GPU.CreateGraphicsPso(device, description);
        if (createdPipeline != null) pipelines.Add(key, createdPipeline);
        return createdPipeline;
    }
}
