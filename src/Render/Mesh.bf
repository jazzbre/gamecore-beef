using NoGraphicsAPI;
using System;
using System.Collections;

namespace GameCore
{
	[CRepr]
	struct MeshVertex
	{
		public Vector2 position;
		public Vector4 uv;
		public uint32 color;

		public this(Vector2 _position, Vector4 _uv, uint32 _color)
		{
			position = _position;
			uv = _uv;
			color = _color;
		}

		public static MeshVertex Lerp(MeshVertex a, MeshVertex b, float delta)
		{
			return .(.Lerp(a.position, b.position, delta), .Lerp(a.uv, b.uv, delta), a.color);
		}
	}

	class Mesh
	{
		public GpuBuffer VertexBufferHandle { get; private set; }
		public GpuBuffer IndexBufferHandle { get; private set; }

		public List<MeshVertex> Vertices { get; private set; }
		public List<uint16> Indices { get; private set; }

		public Vector2 MinBounds { get; private set; }
		public Vector2 MaxBounds { get; private set; }

		public Vector4 MinUV { get; private set; }
		public Vector4 MaxUV { get; private set; }

		public static VertexLayout vertexLayout;

		public this()
		{
			VertexBufferHandle = .Null;
			IndexBufferHandle = .Null;
		}

		public ~this()
		{
			Destroy();
			delete Vertices;
			delete Indices;
		}

		public void Initialize(int vertexCount, int indexCount)
		{
			Destroy();
			if (vertexLayout.hash == 0)
			{
				vertexLayout.Begin();
				vertexLayout.Add(VertexAttribute.Position, 2, VertexComponent.Float, false, false);
				vertexLayout.Add(VertexAttribute.TexCoord0, 4, VertexComponent.Float, false, false);
				vertexLayout.Add(VertexAttribute.Color0, 4, VertexComponent.Uint8, true, false);
				vertexLayout.End();
			}
			if (Vertices == null)
			{
				Vertices = new List<MeshVertex>();
			}
			if (Indices == null)
			{
				Indices = new List<uint16>();
			}
			Vertices.Count = vertexCount;
			Indices.Count = indexCount;
		}

		public void Initialize(int vertexCount)
		{
			Initialize(vertexCount, (vertexCount - 2) * 3);
			int index = 0;
			for (int i = 0; i < Vertices.Count - 2; ++i)
			{
				var vertexIndex = (uint16)i;
				Indices[index++] = 0;
				Indices[index++] = vertexIndex + 1;
				Indices[index++] = vertexIndex + 2;
			}
		}

		public void Create()
		{
			VertexBufferHandle = GpuBuffer.CreateVertices(&Vertices[0], (uint32)(Vertices.Count * sizeof(MeshVertex)), vertexLayout);
			IndexBufferHandle = GpuBuffer.CreateIndices(&Indices[0], (uint32)(Indices.Count * sizeof(uint16)));
			MinBounds = MinBounds = Vertices[0].position;
			MinUV = MaxUV = Vertices[0].uv;
			for (var vertex in Vertices)
			{
				MinBounds = Vector2.Min(MinBounds, vertex.position);
				MaxBounds = Vector2.Max(MaxBounds, vertex.position);
				MinUV = Vector4.Min(MinUV, vertex.uv);
				MaxUV = Vector4.Max(MaxUV, vertex.uv);
			}
		}

		public void Destroy()
		{
			if (VertexBufferHandle.Valid)
			{
				VertexBufferHandle.Dispose();
				VertexBufferHandle = .Null;
			}
			if (IndexBufferHandle.Valid)
			{
				IndexBufferHandle.Dispose();
				IndexBufferHandle = .Null;
			}
		}

		public void Render(uint16 viewId, Matrix4 worldMatrix, Shader shader, GpuTexture[] textureHandles, Color color = Color.White, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0, Span<uint8> parameters = default)
		{
            if (!VertexBufferHandle.Valid || !IndexBufferHandle.Valid) return;
            var renderState = state.GetValueOrDefault(RenderState.Alpha);
            RenderManager.Draw(viewId, shader, programIndex, VertexBufferHandle, IndexBufferHandle, (.)Vertices.Count, (.)Indices.Count,
                worldMatrix, .(color.r, color.g, color.b, color.a), .Zero, textureHandles, renderState, sampler, parameters: parameters);
		}
	}
}
