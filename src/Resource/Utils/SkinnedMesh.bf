using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

namespace Dedkeni
{
	class SkinnedMesh
	{
		public class Part
		{
			public bgfx.VertexLayout vertexLayout;
			public bgfx.VertexBufferHandle vertexBufferHandle;
			public int vertexCount = 0;

			public ~this()
			{
				bgfx.destroy_vertex_buffer(vertexBufferHandle);
				vertexBufferHandle.idx = uint16.MaxValue;
			}

			public bool Load(Stream stream, ref Bounds3 bounds)
			{
				var positions = ReadArray<float>(stream);
				defer delete positions;
				var normals = ReadArray<float>(stream);
				defer delete normals;
				var tangents = ReadArray<float>(stream);
				defer delete tangents;
				var uvs = ReadArray<float>(stream);
				defer delete uvs;
				var colors = ReadArray<uint8>(stream);
				defer delete colors;
				var jointIndices = ReadArray<uint16>(stream);
				defer delete jointIndices;
				var jointWeights = ReadArray<float>(stream);
				defer delete jointWeights;
				// Create layeout
				vertexCount = positions.Count / 3;
				bgfx.vertex_layout_begin(&vertexLayout, bgfx.get_renderer_type());
				bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Position, 3, bgfx.AttribType.Float, false, false);
				if (normals != null)
				{
					bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Normal, 3, bgfx.AttribType.Float, false, false);
				}
				if (tangents != null)
				{
					bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Tangent, 4, bgfx.AttribType.Float, false, false);
				}
				if (uvs != null)
				{
					bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.TexCoord0, 2, bgfx.AttribType.Float, false, false);
				}
				if (colors != null)
				{
					bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Color0, 4, bgfx.AttribType.Uint8, true, false);
				}
				int indicesPerVertex = 0;
				int weightsPerVertex = 0;
				if (jointIndices != null)
				{
					indicesPerVertex = jointIndices.Count / vertexCount;
					bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Indices, 4, bgfx.AttribType.Uint8, true, false);
					bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Weight, 4, bgfx.AttribType.Float, false, false);
					if (jointWeights != null)
					{
						weightsPerVertex = jointWeights.Count / vertexCount;
					}
				}
				bgfx.vertex_layout_end(&vertexLayout);
				// Fill buffer
				uint8[] vertices = new .[vertexLayout.stride * vertexCount];
				defer delete vertices;
				int vertexOffset = 0;
				var vertexIndices = scope uint8[4](0, 0, 0, 0);
				var vertexWeight = Vector4(1, 0, 0, 0);
				for (int i = 0; i < vertexCount; ++i)
				{
					Internal.MemCpy(&vertices[vertexOffset], &positions[i * 3], 12);
					bounds.Add(.(positions[i * 3 + 0], positions[i * 3 + 1], positions[i * 3 + 2]));
					vertexOffset += 12;
					if (normals != null)
					{
						Internal.MemCpy(&vertices[vertexOffset], &normals[i * 3], 12);
						vertexOffset += 12;
					}
					if (tangents != null)
					{
						Internal.MemCpy(&vertices[vertexOffset], &tangents[i * 4], 16);
						vertexOffset += 16;
					}
					if (uvs != null)
					{
						Internal.MemCpy(&vertices[vertexOffset], &uvs[i * 2], 8);
						vertexOffset += 8;
					}
					if (colors != null)
					{
						Internal.MemCpy(&vertices[vertexOffset], &colors[i * 4], 4);
						vertexOffset += 4;
					}
					if (jointIndices != null)
					{
						for (int j = 0; j < indicesPerVertex; ++j)
						{
							vertexIndices[j] = (uint8)jointIndices[i * indicesPerVertex + j];
						}
						Internal.MemCpy(&vertices[vertexOffset], &vertexIndices[0], 4);
						vertexOffset += 4;
						if (jointWeights != null)
						{
							if (weightsPerVertex > 0)
							{
								vertexWeight.x = jointWeights[i * weightsPerVertex + 0];
							}
							if (weightsPerVertex > 1)
							{
								vertexWeight.y = jointWeights[i * weightsPerVertex + 1];
							}
							if (weightsPerVertex > 2)
							{
								vertexWeight.z = jointWeights[i * weightsPerVertex + 2];
							}
							if (weightsPerVertex > 3)
							{
								vertexWeight.w = jointWeights[i * weightsPerVertex + 3];
							}
						}
						Internal.MemCpy(&vertices[vertexOffset], &vertexWeight, 16);
						vertexOffset += 16;
					}
				}
				vertexBufferHandle = bgfx.create_vertex_buffer(bgfx.copy(&vertices[0], (uint32)vertices.Count), &vertexLayout, 0);
				return true;
			}
		}

		public class SubMesh
		{
			public Part[] parts = null ~ DeleteContainerAndItems!(_);
			public uint16[] jointRemaps = null ~ delete _;
			public Matrix4[] inverseBindMatrices = null ~ delete _;
			public int indicesCount = 0;
			public bgfx.IndexBufferHandle indexBufferHandle;
			public Texture texture;
			public Bounds3 bounds = .();

			public ~this()
			{
				bgfx.destroy_index_buffer(indexBufferHandle);
				indexBufferHandle.idx = uint16.MaxValue;
			}

			public bool Load(Stream stream)
			{
				let version = stream.Read<uint32>().Value;
				let count = stream.Read<uint32>().Value;
				parts = new Part[count];
				for (var i = 0; i < (int)count; ++i)
				{
					var part = new Part();
					parts[i] = part;
					if (!part.Load(stream, ref bounds))
					{
						return false;
					}
				}
				var triangleIndices = ReadArray<uint16>(stream);
				defer delete triangleIndices;
				indicesCount = triangleIndices.Count;
				jointRemaps = ReadArray<uint16>(stream);
				inverseBindMatrices = ReadArray<Matrix4>(stream);
				indexBufferHandle = bgfx.create_index_buffer(bgfx.copy(&triangleIndices[0], (uint32)(triangleIndices.Count * sizeof(uint16))), 0);
				return true;
			}
		}

		public uint8[] skeletonData = null;
		public List<SubMesh> subMeshes = new List<SubMesh>() ~ DeleteContainerAndItems!(_);

		private static T[] ReadArray<T>(Stream stream)
		{
			let count = stream.Read<uint32>().Value;
			if (count == 0)
				return null;
			{
			}
			T[] t = new T[count];
			switch (stream.TryRead(Span<uint8>((uint8*)t.Ptr, sizeof(T) * (int)count))) {
			case .Err(let err):
				delete t;
				return null;
			default:
			}
			return t;
		}

		public bool Load(Stream stream, int size)
		{
			let position = stream.Position;
			let endPosition = position + size;
			stream.Seek(stream.Position + 1);
			while (stream.Position != endPosition)
			{
				stream.Seek(stream.Position + 16);
				let version = stream.Read<uint32>().Value;
				var subMesh = new SubMesh();
				if (!subMesh.Load(stream))
				{
					delete subMesh;
					return false;
				}
				subMeshes.Add(subMesh);
			}
			return true;
		}

		public void Render(uint16 viewId, Matrix4 _worldMatrix, Shader shader, Vector4* jointMatrices3x4, int jointCount, Vector4 color = .One, Vector4 settings = .Zero, bgfx.TextureHandle[] textureHandles = null, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int programIndex = 0)
		{
			var stateFlags = _stateFlags != 0 ? _stateFlags : bgfx.StateFlags.WriteRgb | .WriteA | .WriteZ | .DepthTestLequal | RenderManager.GetCullingState(true);
			var samplerFlags = _samplerFlags != 0 ? (uint32)_samplerFlags : (uint32)(bgfx.SamplerFlags.UClamp | bgfx.SamplerFlags.VClamp);
				// Render
			var worldMatrix = _worldMatrix;
			for (var subMesh in subMeshes)
			{
				let part = subMesh.parts[0];
				bgfx.set_transform(worldMatrix.Ptr(), 1);
				bgfx.set_state((uint64)stateFlags, 0);
				bgfx.set_uniform(RenderManager.timeUniformHandle, &RenderManager.ShaderData.x, 1);
				bgfx.set_uniform(RenderManager.colorUniformHandle, &color.x, 1);
				bgfx.set_uniform(RenderManager.settingsUniformHandle, &settings.x, 1);
				bgfx.set_uniform(RenderManager.instanceDataUniformHandle, jointMatrices3x4, (uint16)jointCount * 3);
				bgfx.set_vertex_buffer(0, part.vertexBufferHandle, 0, (uint32)part.vertexCount);
				bgfx.set_index_buffer(subMesh.indexBufferHandle, 0, (uint32)subMesh.indicesCount);
				if (textureHandles != null)
				{
					for (int i = 0; i < textureHandles.Count; ++i)
					{
						bgfx.set_texture((uint8)i, RenderManager.textureUniformHandles[i], textureHandles[i], samplerFlags);
					}
				} else if (subMesh.texture != null)
				{
					bgfx.set_texture(0, RenderManager.textureUniformHandles[0], subMesh.texture.Handle, samplerFlags);
				}
				bgfx.submit(viewId, shader.Programs[programIndex], 0, (uint8)bgfx.DiscardFlags.All);
				++RenderManager.statistics.submitCount;
			}
		}

		public void SetTexture(Texture texture)
		{
			for (var subMesh in subMeshes)
			{
				subMesh.texture = texture;
			}
		}
	}
}
