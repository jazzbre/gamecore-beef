using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

namespace Dedkeni
{
	class StaticMesh
	{
		static readonly uint32 kChunkVertexBuffer = 0x01204256;
		static readonly uint32 kChunkIndexBuffer = 0x00204249;
		static readonly uint32 kChunkPrimitive = 0x00495250;

		[CRepr]
		public struct Sphere
		{
			public Vector3 center;
			public float radius;
		}

		[CRepr]
		public struct Aabb
		{
			public Vector3 min;
			public Vector3 max;
		}

		[CRepr]
		public struct Obb
		{
			public float[16] mtx;
		}

		[CRepr]
		public struct Primitive
		{
			public uint32 m_startIndex;
			public uint32 m_numIndices;
			public uint32 m_startVertex;
			public uint32 m_numVertices;
			public Sphere m_sphere;
			public Aabb m_aabb;
			public Obb m_obb;
		}

		public class Group
		{
			public String name = new String() ~ delete _;
			public bgfx.VertexBufferHandle m_vbh;
			public bgfx.IndexBufferHandle m_ibh;
			public uint16 m_numVertices;
			public uint32 m_numIndices;
			public Sphere m_sphere;
			public Aabb m_aabb;
			public Obb m_obb;
			public List<Primitive> m_prims = new List<Primitive>() ~ delete _;
			public Texture texture;

			public ~this()
			{
				bgfx.destroy_vertex_buffer(m_vbh);
				bgfx.destroy_index_buffer(m_ibh);
			}
		}

		public bgfx.VertexLayout vertexLayout;
		private List<Group> groups = new List<Group>() ~ DeleteContainerAndItems!(_);

		public bgfx.VertexLayout VertexLayout => vertexLayout;
		public List<Group> Groups => groups;

		public bool Load(StringView fileName)
		{
			var binaryFile = scope DynMemStream();
			if (!ResourceManager.ReadFile(fileName, binaryFile))
			{
				return false;
			}
			Group group = null;
			while (true)
			{
				uint32 chunk = 0;
				switch (binaryFile.Read<uint32>()) {
				case .Ok(var val):
					chunk = val;
				default:
				}
				if (chunk == 0)
				{
					break;
				}
				switch (chunk) {
				case kChunkVertexBuffer:
					if (group == null)
					{
						group = new Group();
					}
					group.m_sphere = binaryFile.Read<Sphere>().Value;
					group.m_aabb = binaryFile.Read<Aabb>().Value;
					group.m_obb = binaryFile.Read<Obb>().Value;
					VertexLayoutReader.Read(binaryFile, ref vertexLayout);
					group.m_numVertices = binaryFile.Read<uint16>().Value;
					let stride = vertexLayout.stride;
					var vertices = scope uint8[(int)group.m_numVertices * (int)stride];
					binaryFile.TryRead(vertices).IgnoreError();
					group.m_vbh = bgfx.create_vertex_buffer(bgfx.copy(&vertices[0], (uint32)vertices.Count), &vertexLayout, 0);
					break;
				case kChunkIndexBuffer:
					if (group == null)
					{
						group = new Group();
					}
					group.m_numIndices = binaryFile.Read<uint32>().Value;
					var indices = scope uint8[sizeof(uint16) * (int)group.m_numIndices];
					binaryFile.TryRead(indices).IgnoreError();
					group.m_ibh = bgfx.create_index_buffer(bgfx.copy(&indices[0], (uint32)indices.Count), 0);
					break;
				case kChunkPrimitive:
					SystemUtils.ReadStrSized16(binaryFile, group.name);
					let count = binaryFile.Read<uint16>().Value;
					for (var i = 0; i < count; ++i)
					{
						var name = scope String();
						SystemUtils.ReadStrSized16(binaryFile, name);
						var primitive = Primitive();
						primitive.m_startIndex = binaryFile.Read<uint32>().Value;
						primitive.m_numIndices = binaryFile.Read<uint32>().Value;
						primitive.m_startVertex = binaryFile.Read<uint32>().Value;
						primitive.m_numVertices = binaryFile.Read<uint32>().Value;
						primitive.m_sphere = binaryFile.Read<Sphere>().Value;
						primitive.m_aabb = binaryFile.Read<Aabb>().Value;
						primitive.m_obb = binaryFile.Read<Obb>().Value;
						group.m_prims.Add(primitive);
					}
					groups.Add(group);
					group = null;
					break;
				}
			}
			return true;
		}

		public void SetTexture(Texture texture)
		{
			for (var group in groups)
			{
				group.texture = texture;
			}
		}
	}
}
