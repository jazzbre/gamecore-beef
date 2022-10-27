using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

namespace Dedkeni
{
	class VertexLayoutReader
	{
		struct AttribToId
		{
			public bgfx.Attrib attr;
			public uint16 id;

			public this(bgfx.Attrib _attr, uint16 _id)
			{
				attr = _attr;
				id = _id;
			}
		}

		struct AttribTypeToId
		{
			public bgfx.AttribType type;
			public uint16 id;

			public this(bgfx.AttribType _type, uint16 _id)
			{
				type = _type;
				id = _id;
			}
		};

		static readonly var s_attribToId = new AttribToId[]
			(
			.(bgfx.Attrib.Position, 0x0001),
			.(bgfx.Attrib.Normal, 0x0002),
			.(bgfx.Attrib.Tangent, 0x0003),
			.(bgfx.Attrib.Bitangent, 0x0004),
			.(bgfx.Attrib.Color0, 0x0005),
			.(bgfx.Attrib.Color1, 0x0006),
			.(bgfx.Attrib.Color2, 0x0018),
			.(bgfx.Attrib.Color3, 0x0019),
			.(bgfx.Attrib.Indices, 0x000e),
			.(bgfx.Attrib.Weight, 0x000f),
			.(bgfx.Attrib.TexCoord0, 0x0010),
			.(bgfx.Attrib.TexCoord1, 0x0011),
			.(bgfx.Attrib.TexCoord2, 0x0012),
			.(bgfx.Attrib.TexCoord3, 0x0013),
			.(bgfx.Attrib.TexCoord4, 0x0014),
			.(bgfx.Attrib.TexCoord5, 0x0015),
			.(bgfx.Attrib.TexCoord6, 0x0016),
			.(bgfx.Attrib.TexCoord7, 0x0017)
			) ~ delete _;

		static readonly var s_attribTypeToId = new AttribTypeToId[]
			(
			.(bgfx.AttribType.Uint8, 0x0001),
			.(bgfx.AttribType.Uint10, 0x0005),
			.(bgfx.AttribType.Int16, 0x0002),
			.(bgfx.AttribType.Half, 0x0003),
			.(bgfx.AttribType.Float, 0x0004)
			) ~ delete _;

		static bgfx.Attrib idToAttrib(uint16 id)
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

		static bgfx.AttribType idToAttribType(uint16 id)
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

		public static bool Read(Stream stream, ref bgfx.VertexLayout vertex_layout)
		{
			var numAttrs = stream.Read<uint8>().Value;
			var stride = stream.Read<uint16>().Value;
			bgfx.vertex_layout_begin(&vertex_layout, bgfx.get_renderer_type());
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
					bgfx.vertex_layout_add(&vertex_layout, attr, num, type, normalized, asInt);
					vertex_layout.offset[(int)attr] = offset;
				}
			}
			bgfx.vertex_layout_end(&vertex_layout);
			vertex_layout.stride = stride;
			return true;
		}
	}
}
