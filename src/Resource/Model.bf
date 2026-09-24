using NoGraphicsAPI;
using System;
using System.Collections;
using System.IO;
using System.Diagnostics;

namespace GameCore
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class Model : Resource
	{
		public StaticMesh Mesh { get; private set; }

		protected override void OnLoad()
		{
			Mesh = new StaticMesh();
			Mesh.Load(scope $"{Hash}.model");
		}

		protected override void OnUnload()
		{
			DeleteAndNullify!(Mesh);
		}

		public void Render(uint16 viewId, Matrix4 _worldMatrix, Shader shader, Vector4 color = .One, Vector4 settings = .Zero, GpuTexture[] textureHandles = null, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0, bool useSH = false)
		{
            var renderState = state.GetValueOrDefault(.DepthTested);
            renderState.Rasterization.cull = RenderManager.GetCullingState(true);
            for (var group in Mesh.Groups)
            {
                var textures = textureHandles;
                var fallback = scope GpuTexture[](group.texture != null ? group.texture.Handle : null);
                if (textures == null) textures = fallback;
                RenderManager.Draw(viewId, shader, programIndex, group.m_vbh, group.m_ibh, group.m_numVertices, group.m_numIndices,
                    _worldMatrix, color, settings, textures, renderState, sampler);
            }
		}
	}
}
