using NoGraphicsAPI;
using System;
using System.Collections;
using System.IO;
using System.Diagnostics;

namespace GameCore
{
	class SkinnedMesh
	{
		public class Part
		{
			public VertexLayout vertexLayout;
			public GpuBuffer vertexBufferHandle;
			public int vertexCount = 0;

			public ~this()
			{
				vertexBufferHandle.Dispose();
				vertexBufferHandle = .Null;
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
				vertexLayout.Begin();
				vertexLayout.Add(VertexAttribute.Position, 3, VertexComponent.Float, false, false);
				if (normals != null)
				{
					vertexLayout.Add(VertexAttribute.Normal, 3, VertexComponent.Float, false, false);
				}
				if (tangents != null)
				{
					vertexLayout.Add(VertexAttribute.Tangent, 4, VertexComponent.Float, false, false);
				}
				if (uvs != null)
				{
					vertexLayout.Add(VertexAttribute.TexCoord0, 2, VertexComponent.Float, false, false);
				}
				if (colors != null)
				{
					vertexLayout.Add(VertexAttribute.Color0, 4, VertexComponent.Uint8, true, false);
				}
				int indicesPerVertex = 0;
				int weightsPerVertex = 0;
				if (jointIndices != null)
				{
					indicesPerVertex = jointIndices.Count / vertexCount;
					vertexLayout.Add(VertexAttribute.Indices, 4, VertexComponent.Uint8, true, false);
					vertexLayout.Add(VertexAttribute.Weight, 4, VertexComponent.Float, false, false);
					if (jointWeights != null)
					{
						weightsPerVertex = jointWeights.Count / vertexCount;
					}
				}
				vertexLayout.End();
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
				vertexBufferHandle = GpuBuffer.CreateVertices(&vertices[0], (uint32)vertices.Count, vertexLayout);
				return true;
			}
		}

		public class SubMesh
		{
			public Part[] parts = null ~ DeleteContainerAndItems!(_);
			public uint16[] jointRemaps = null ~ delete _;
			public Matrix4[] inverseBindMatrices = null ~ delete _;
			public int indicesCount = 0;
			public GpuBuffer indexBufferHandle;
			public GameCore.Texture texture;
			public Bounds3 bounds = .();

			public ~this()
			{
				indexBufferHandle.Dispose();
				indexBufferHandle = .Null;
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
				indexBufferHandle = GpuBuffer.CreateIndices(&triangleIndices[0], (uint32)(triangleIndices.Count * sizeof(uint16)));
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

		public void Render(uint16 viewId, Matrix4 _worldMatrix, Shader shader, Vector4* jointMatrices3x4, int jointCount, Vector4 color = .One, Vector4 settings = .Zero, GpuTexture[] textureHandles = null, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0)
		{
            var renderState = state.GetValueOrDefault(.DepthTested);
            renderState.Rasterization.cull = RenderManager.GetCullingState(true);
            for (var subMesh in subMeshes)
            {
                var fallback = scope GpuTexture[](subMesh.texture != null ? subMesh.texture.Handle : null);
                if (subMesh.parts.Count == 0) continue;
                var part = subMesh.parts[0];
                RenderManager.Draw(viewId, shader, programIndex, part.vertexBufferHandle, subMesh.indexBufferHandle,
                        (.)part.vertexCount, (.)subMesh.indicesCount, _worldMatrix, color, settings,
                        textureHandles != null ? textureHandles : fallback, renderState, sampler, jointMatrices3x4, jointCount * 3);
            }
		}

		public void SetTexture(GameCore.Texture texture)
		{
			for (var subMesh in subMeshes)
			{
				subMesh.texture = texture;
			}
		}
	}
}
