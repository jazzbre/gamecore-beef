using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	[CRepr]
	struct Mesh3DVertex
	{
		public Vector3 position;
		public Vector3 normal;
		public Vector4 uv;
		public uint32 color;

		public this(Vector3 _position, Vector3 _normal, Vector4 _uv, uint32 _color)
		{
			position = _position;
			normal = _normal;
			uv = _uv;
			color = _color;
		}

		public static Mesh3DVertex Lerp(Mesh3DVertex a, Mesh3DVertex b, float delta)
		{
			return .(.Lerp(a.position, b.position, delta), .Lerp(a.normal, b.normal, delta), .Lerp(a.uv, b.uv, delta), a.color);
		}
	}

	class Mesh3D
	{
		public bgfx.VertexBufferHandle VertexBufferHandle { get; private set; }
		public bgfx.IndexBufferHandle IndexBufferHandle { get; private set; }

		public List<Mesh3DVertex> Vertices { get; private set; }
		public List<uint16> Indices { get; private set; }

		public Vector3 MinBounds { get; private set; }
		public Vector3 MaxBounds { get; private set; }

		public Vector4 MinUV { get; private set; }
		public Vector4 MaxUV { get; private set; }

		public static bgfx.VertexLayout vertexLayout;

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
				bgfx.vertex_layout_begin(&vertexLayout, bgfx.get_renderer_type());
				bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Position, 3, bgfx.AttribType.Float, false, false);
				bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Normal, 3, bgfx.AttribType.Float, false, false);
				bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.TexCoord0, 4, bgfx.AttribType.Float, false, false);
				bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Color0, 4, bgfx.AttribType.Uint8, true, false);
				bgfx.vertex_layout_end(&vertexLayout);
			}
			if (Vertices == null)
			{
				Vertices = new List<Mesh3DVertex>();
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
			VertexBufferHandle = bgfx.create_vertex_buffer(bgfx.copy(&Vertices[0], (uint32)(Vertices.Count * sizeof(Mesh3DVertex))), &vertexLayout, 0);
			IndexBufferHandle = bgfx.create_index_buffer(bgfx.copy(&Indices[0], (uint32)(Indices.Count * sizeof(uint16))), 0);
			MinBounds = MinBounds = Vertices[0].position;
			MinUV = MaxUV = Vertices[0].uv;
			for (var vertex in Vertices)
			{
				MinBounds = .Min(MinBounds, vertex.position);
				MaxBounds = .Max(MaxBounds, vertex.position);
				MinUV = .Min(MinUV, vertex.uv);
				MaxUV = .Max(MaxUV, vertex.uv);
			}
		}

		public void Destroy()
		{
			if (VertexBufferHandle.idx != uint16.MaxValue)
			{
				bgfx.destroy_vertex_buffer(VertexBufferHandle);
				VertexBufferHandle.idx = uint16.MaxValue;
			}
			if (IndexBufferHandle.idx != uint16.MaxValue)
			{
				bgfx.destroy_index_buffer(IndexBufferHandle);
				IndexBufferHandle.idx = uint16.MaxValue;
			}
		}

		public void Render(uint16 viewId, Matrix4 worldMatrix, Shader shader, bgfx.TextureHandle[] textureHandles, Color color = Color.White, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int programIndex = 0)
		{
			if (!VertexBufferHandle.Valid || !IndexBufferHandle.Valid)
			{
				return;
			}
			var stateFlags = _stateFlags != 0 ? _stateFlags : bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.WriteZ | bgfx.StateFlags.DepthTestLequal | bgfx.blend_function(bgfx.StateFlags.BlendOne, bgfx.StateFlags.BlendInvSrcAlpha);
			var matrix = worldMatrix;
			bgfx.set_transform(matrix.Ptr(), 1);
			bgfx.set_state((uint64)stateFlags, 0);
			bgfx.set_vertex_buffer(0, VertexBufferHandle, 0, (uint32)Vertices.Count);
			bgfx.set_index_buffer(IndexBufferHandle, 0, (uint32)Indices.Count);
			var colorValue = color;
			bgfx.set_uniform(RenderManager.colorUniformHandle, &colorValue.r, 1);
			if (textureHandles != null)
			{
				for (int i = 0; i < textureHandles.Count; ++i)
				{
					bgfx.set_texture((uint8)i, RenderManager.textureUniformHandles[i], textureHandles[i], _samplerFlags != 0 ? (uint32)_samplerFlags : (uint32)(bgfx.SamplerFlags.UClamp | bgfx.SamplerFlags.VClamp));
				}
			}
			bgfx.submit(viewId, shader.Programs[programIndex], 0, (uint8)bgfx.DiscardFlags.All);
			++RenderManager.statistics.submitCount;
		}
	}
}
