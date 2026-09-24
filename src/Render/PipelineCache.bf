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
        public Format[RenderTexture.MaxColorAttachments] Colors;
        public int ColorCount;
        public Format Depth;
        public float DepthBiasConstant;
        public float DepthBiasClamp;
        public float DepthBiasSlope;

        public int GetHashCode()
        {
            int hash = Program.GetHashCode();
            hash = (hash &* 397) ^ State.GetHashCode();
            hash = (hash &* 397) ^ ColorCount;
            for (int index = 0; index < ColorCount; ++index)
                hash = (hash &* 397) ^ (int)Colors[index];
            hash = (hash &* 397) ^ (int)Depth;
            hash = (hash &* 397) ^ (DepthBiasConstant == 0 ? 0 : DepthBiasConstant.GetHashCode());
            hash = (hash &* 397) ^ (DepthBiasClamp == 0 ? 0 : DepthBiasClamp.GetHashCode());
            return (hash &* 397) ^ (DepthBiasSlope == 0 ? 0 : DepthBiasSlope.GetHashCode());
        }

        public bool Equals(Key other)
        {
            if (Program != other.Program || State != other.State || ColorCount != other.ColorCount
                || Depth != other.Depth || DepthBiasConstant != other.DepthBiasConstant
                || DepthBiasClamp != other.DepthBiasClamp || DepthBiasSlope != other.DepthBiasSlope)
                return false;
            for (int index = 0; index < ColorCount; ++index)
                if (Colors[index] != other.Colors[index])
                    return false;
            return true;
        }

        public static bool operator ==(Key first, Key second) => first.Equals(second);
    }

    private Device* device;
    private Dictionary<Key, PSO*> pipelines = new .() ~ delete _;
    private Dictionary<uint64, PSO*> computePipelines = new .() ~ delete _;
    public int Count => pipelines.Count + computePipelines.Count;

    public this(Device* device)
    {
        this.device = device;
    }

    public ~this()
    {
        Clear();
    }

    // Submit all command buffers referencing this cache before clearing it.

    public void Clear()
    {
        if (Count == 0)
            return;
        GPU.WaitIdle(device);
        for (var entry in pipelines)
            GPU.DestroyPso(entry.value);
        pipelines.Clear();
        for (var entry in computePipelines)
            GPU.DestroyPso(entry.value);
        computePipelines.Clear();
    }

    public PSO* GetCompute(ShaderProgram program)
    {
        if (program == null || !program.IsCompute)
            return null;
        if (computePipelines.TryGetValue(program.Id, let pipeline))
            return pipeline;
        var createdPipeline = GPU.CreateComputePso(device, .() { data = program.ComputeCode.Ptr, size = (.)program.ComputeCode.Count });
        if (createdPipeline != null)
            computePipelines.Add(program.Id, createdPipeline);
        return createdPipeline;
    }

    public PSO* Get(ShaderProgram program, Format color, Format depth, RenderState state)
    {
        var color;
        return Get(program, Span<Format>(&color, color == .undefined ? 0 : 1), depth, state);
    }

    public PSO* Get(ShaderProgram program, Span<Format> colors, Format depth, RenderState state)
    {
        if (colors.Length > RenderTexture.MaxColorAttachments)
            Runtime.FatalError("Too many pipeline color attachments");
        if (program == null || program.IsCompute)
            return null;
        uint64 packedState = (uint64)state.ColorWriteMask | ((uint64)state.Rasterization.cull << 4)
        | (state.Blend.enabled ? 1UL << 6 : 0)
        | ((uint64)state.Blend.color.source << 7) | ((uint64)state.Blend.color.destination << 11)
        | ((uint64)state.Blend.color.operation << 15) | ((uint64)state.Blend.alpha.source << 18)
        | ((uint64)state.Blend.alpha.destination << 22) | ((uint64)state.Blend.alpha.operation << 26);
        Key key = .() { Program = program.Id, State = packedState, ColorCount = colors.Length, Depth = depth,
            DepthBiasConstant = state.Rasterization.depth_bias_constant, DepthBiasClamp = state.Rasterization.depth_bias_clamp,
            DepthBiasSlope = state.Rasterization.depth_bias_slope };
        for (int index = 0; index < colors.Length; ++index)
            key.Colors[index] = colors[index];
        if (pipelines.TryGetValue(key, let pipeline))
            return pipeline;
        ColorTargetDesc[RenderTexture.MaxColorAttachments] targets = default;
        for (int index = 0; index < colors.Length; ++index)
            targets[index] = .() { format = colors[index], blend = state.Blend, write_mask = state.ColorWriteMask };
        GraphicsPSODesc description = .();
        description.vertex_spirv = .() { data = program.VertexCode.Ptr, size = (.)program.VertexCode.Count };
        description.fragment_spirv = .() { data = program.FragmentCode.Ptr, size = (.)program.FragmentCode.Count };
        description.color_targets = .() { data = &targets[0], size = (.)colors.Length };
        description.depth_format = depth;
        if (GPU.GetTextureFormatInfo(depth).stencil)
            description.stencil_format = depth;
        description.rasterization = state.Rasterization;
        PSO* createdPipeline = GPU.CreateGraphicsPso(device, description);
        if (createdPipeline != null)
            pipelines.Add(key, createdPipeline);
        return createdPipeline;
    }
}
