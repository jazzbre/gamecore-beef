using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

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

		public void Render(uint16 viewId, Matrix4 _worldMatrix, Shader shader, Vector4 color = .One, Vector4 settings = .Zero, bgfx.TextureHandle[] textureHandles = null, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int programIndex = 0)
		{
			var stateFlags = _stateFlags != 0 ? _stateFlags : bgfx.StateFlags.WriteRgb | .WriteA | .WriteZ | .DepthTestLequal | RenderManager.GetCullingState(true);
			var samplerFlags = _samplerFlags != 0 ? (uint32)_samplerFlags : (uint32)(bgfx.SamplerFlags.UClamp | bgfx.SamplerFlags.VClamp);
				// Render
			var worldMatrix = _worldMatrix;
			for (var group in Mesh.Groups)
			{
				bgfx.set_transform(worldMatrix.Ptr(), 1);
				bgfx.set_state((uint64)stateFlags, 0);
				var shaderData = RenderManager.ShaderData;
				bgfx.set_uniform(RenderManager.timeUniformHandle, &shaderData.x, 1);
				bgfx.set_uniform(RenderManager.colorUniformHandle, &color.x, 1);
				bgfx.set_uniform(RenderManager.settingsUniformHandle, &settings.x, 1);
				bgfx.set_vertex_buffer(0, group.m_vbh, 0, (uint32)group.m_numVertices);
				bgfx.set_index_buffer(group.m_ibh, 0, (uint32)group.m_numIndices);
				if (textureHandles != null)
				{
					for (int i = 0; i < textureHandles.Count; ++i)
					{
						bgfx.set_texture((uint8)i, RenderManager.textureUniformHandles[i], textureHandles[i], samplerFlags);
					}
				} else if (group.texture != null)
				{
					bgfx.set_texture(0, RenderManager.textureUniformHandles[0], group.texture.Handle, samplerFlags);
				}
				bgfx.submit(viewId, shader.Programs[programIndex], 0, (uint8)bgfx.DiscardFlags.All);
				++RenderManager.statistics.submitCount;
			}
		}
	}
}
