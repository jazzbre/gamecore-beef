using NoGraphicsAPI;
using System;
using System.Collections;
using System.IO;
using System.Diagnostics;

namespace GameCore
{
	class VertexLayoutReader
	{
		struct AttribToId
		{
			public VertexAttribute attr;
			public uint16 id;

			public this(VertexAttribute _attr, uint16 _id)
			{
				attr = _attr;
				id = _id;
			}
		}

		struct AttribTypeToId
		{
			public VertexComponent type;
			public uint16 id;

			public this(VertexComponent _type, uint16 _id)
			{
				type = _type;
				id = _id;
			}
		};

		static readonly var s_attribToId = new AttribToId[]
			(
			.(VertexAttribute.Position, 0x0001),
			.(VertexAttribute.Normal, 0x0002),
			.(VertexAttribute.Tangent, 0x0003),
			.(VertexAttribute.Bitangent, 0x0004),
			.(VertexAttribute.Color0, 0x0005),
			.(VertexAttribute.Color1, 0x0006),
			.(VertexAttribute.Color2, 0x0018),
			.(VertexAttribute.Color3, 0x0019),
			.(VertexAttribute.Indices, 0x000e),
			.(VertexAttribute.Weight, 0x000f),
			.(VertexAttribute.TexCoord0, 0x0010),
			.(VertexAttribute.TexCoord1, 0x0011),
			.(VertexAttribute.TexCoord2, 0x0012),
			.(VertexAttribute.TexCoord3, 0x0013),
			.(VertexAttribute.TexCoord4, 0x0014),
			.(VertexAttribute.TexCoord5, 0x0015),
			.(VertexAttribute.TexCoord6, 0x0016),
			.(VertexAttribute.TexCoord7, 0x0017)
			) ~ delete _;

		static readonly var s_attribTypeToId = new AttribTypeToId[]
			(
			.(VertexComponent.Uint8, 0x0001),
			.(VertexComponent.Uint10, 0x0005),
			.(VertexComponent.Int16, 0x0002),
			.(VertexComponent.Half, 0x0003),
			.(VertexComponent.Float, 0x0004)
			) ~ delete _;

		static VertexAttribute idToAttrib(uint16 id)
		{
			for (var attr in s_attribToId)
			{
				if (attr.id == id)
				{
					return attr.attr;
				}
			}
			return .Count;
		}

		static VertexComponent idToAttribType(uint16 id)
		{
			for (var attr in s_attribTypeToId)
			{
				if (attr.id == id)
				{
					return attr.type;
				}
			}
			return .Count;
		}

		public static bool Read(Stream stream, ref VertexLayout vertex_layout)
		{
			var numAttrs = stream.Read<uint8>().Value;
			var stride = stream.Read<uint16>().Value;
			vertex_layout.Begin();
			for (var ii = 0; ii < numAttrs; ++ii)
			{
				var offset = stream.Read<uint16>().Value;
				var attribId = stream.Read<uint16>().Value;
				var num = stream.Read<uint8>().Value;
				var attribTypeId = stream.Read<uint16>().Value;
				var normalized = stream.Read<bool>().Value;
				var asInt = stream.Read<bool>().Value;

				var attr = idToAttrib(attribId);
				var type = idToAttribType(attribTypeId);
				if (attr != .Count && type != .Count)
				{
					vertex_layout.Add(attr, num, type, normalized, asInt);
					vertex_layout.offset[(int)attr] = offset;
				}
			}
			vertex_layout.End();
			vertex_layout.stride = stride;
			return true;
		}
	}
}
