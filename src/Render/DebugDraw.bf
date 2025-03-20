using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	class DebugDraw
	{
		private const float DebugDrawPointLineScale = 0.1f;
		private static readonly var DebugIndices = new uint16[](0, 1, 2, 1, 2, 3, 2, 3, 4, 3, 4, 5, 4, 5, 6, 5, 6, 7) ~ delete _;
		private static readonly var DebugQuadIndices = new uint16[](0, 1, 2, 0, 2, 3) ~ delete _;

		struct DebugVertex
		{
			public Vector2 position;
			public Vector3 uvAndRadius;
			public uint32 fillColor;
			public uint32 outlineColor;
		}

		private static Shader shader;
		private static bgfx.VertexLayout vertexLayout;

		private static var debugVertices = new List<DebugVertex>() ~ delete _;
		private static var debugIndices = new List<uint16>() ~ delete _;

		// Debug draw
		public static void DrawCircle(Chipmunk2D.Vector2 pos, Chipmunk2D.Real angle, Chipmunk2D.Real radius, Chipmunk2D.DebugColor outlineColor, Chipmunk2D.DebugColor fillColor, void* data = null)
		{
			var r = (float)(radius + DebugDrawPointLineScale);
			var outlineColorRGBA = outlineColor.ToRGBA();
			var fillColorRGBA = fillColor.ToRGBA();
			var vertexStart = (uint16)debugVertices.Count;
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(-1, -1, r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(-1, 1, r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(1, 1, r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(1, -1, r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			for (var index in DebugQuadIndices)
			{
				debugIndices.Add(vertexStart + index);
			}
		}

		public static void DrawCircle(Vector2 pos, float angle, float radius, Color outlineColor, Color fillColor)
		{
			DrawCircle(Chipmunk2D.Vector2.FromVector(pos), angle, radius, .(outlineColor.r, outlineColor.g, outlineColor.b, outlineColor.a), .(fillColor.r, fillColor.g, fillColor.b, fillColor.a));
		}

		public static void DrawSegment(Chipmunk2D.Vector2 a, Chipmunk2D.Vector2 b, Chipmunk2D.DebugColor color, void* data = null)
		{
			DrawFatSegment(a, b, 1, color, color, data);
		}

		public static void DrawSegment(Vector2 a, Vector2 b, Color color)
		{
			Chipmunk2D.DebugColor fillColor = .(color.r, color.g, color.b, color.a);
			DrawFatSegment(Chipmunk2D.Vector2.FromVector(a), Chipmunk2D.Vector2.FromVector(b), 0.5f, fillColor, fillColor);
		}

		public static void DrawAxis(Matrix4 worldMatrix, float size, float radius)
		{
			Vector2 position = worldMatrix.Translation.xy;
			DrawFatSegment(position, Vector3.Transform((Vector3.UnitX * size), worldMatrix).xy, 1.5f, .(1, 0, 0, 1), .(1, 0, 0, 1));
			DrawFatSegment(position, Vector3.Transform((Vector3.UnitY * size), worldMatrix).xy, 1.5f, .(0, 1, 0, 1), .(0, 1, 0, 1));
			DrawFatSegment(position, Vector3.Transform((Vector3.UnitZ * size), worldMatrix).xy, 1.5f, .(0, 0, 1, 1), .(0, 0, 1, 1));
		}

		public static void DrawBounds(Bounds2 bounds, Color color, Matrix4 matrix = .Identity)
		{
			var leftBottom = Vector3.Transform(bounds.min.xy0, matrix).xy;
			var leftTop = Vector3.Transform(.(bounds.min.x, bounds.max.y, 0), matrix).xy;
			var rightTop = Vector3.Transform(bounds.max.xy0, matrix).xy;
			var rightBottom = Vector3.Transform(.(bounds.max.x, bounds.min.y, 0), matrix).xy;
			DrawSegment(leftBottom, rightBottom, color);
			DrawSegment(leftTop, rightTop, color);
			DrawSegment(leftBottom, leftTop, color);
			DrawSegment(rightTop, rightBottom, color);
		}

		public static void DrawFatSegment(Chipmunk2D.Vector2 a, Chipmunk2D.Vector2 b, Chipmunk2D.Real radius, Chipmunk2D.DebugColor outlineColor, Chipmunk2D.DebugColor fillColor, void* data = null)
		{
			var r = (float)(radius + DebugDrawPointLineScale);
			var va = a.ToVector();
			var vb = b.ToVector();

			var t = Vector2.Normalize(vb - va);

			var outlineColorRGBA = outlineColor.ToRGBA();
			var fillColorRGBA = fillColor.ToRGBA();
			var vertexStart = (uint16)debugVertices.Count;

			debugVertices.Add(DebugVertex() { position = .((float)a.x, (float)a.y), uvAndRadius = .((float)(-t.x + t.y), (float)(-t.x - t.y), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)a.x, (float)a.y), uvAndRadius = .((float)(-t.x - t.y), (float)(+t.x - t.y), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)a.x, (float)a.y), uvAndRadius = .((float)(-0.0 + t.y), (float)(-t.x + 0.0), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)a.x, (float)a.y), uvAndRadius = .((float)(-0.0 - t.y), (float)(+t.x + 0.0), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)b.x, (float)b.y), uvAndRadius = .((float)(+0.0 + t.y), (float)(-t.x - 0.0), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)b.x, (float)b.y), uvAndRadius = .((float)(+0.0 - t.y), (float)(+t.x - 0.0), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)b.x, (float)b.y), uvAndRadius = .((float)(+t.x + t.y), (float)(-t.x + t.y), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			debugVertices.Add(DebugVertex() { position = .((float)b.x, (float)b.y), uvAndRadius = .((float)(+t.x - t.y), (float)(+t.x + t.y), r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			for (var index in DebugIndices)
			{
				debugIndices.Add(vertexStart + index);
			}
		}

		public static void DrawFatSegment(Vector2 a, Vector2 b, float radius, Color outlineColor, Color fillColor)
		{
			DrawFatSegment(Chipmunk2D.Vector2.FromVector(a), Chipmunk2D.Vector2.FromVector(b), radius, .(outlineColor.r, outlineColor.g, outlineColor.b, outlineColor.a), .(fillColor.r, fillColor.g, fillColor.b, fillColor.a));
		}

		static Vector2 Perpendicular(Vector2 v)
		{
			return .(v.y, -v.x);
		}

		public static void DrawPolygon(int32 count, Chipmunk2D.Vector2* verts, Chipmunk2D.Real radius, Chipmunk2D.DebugColor outlineColor, Chipmunk2D.DebugColor fillColor, void* data = null)
		{
			float inset = (float) - Math.Max(0.0f, 2.0f * DebugDrawPointLineScale - radius);
			float outset = (float)radius + DebugDrawPointLineScale;
			float r = outset - inset;

			var outlineColorRGBA = outlineColor.ToRGBA();
			var fillColorRGBA = fillColor.ToRGBA();
			var vertexStart = (uint16)debugVertices.Count;

			// Polygon fill triangles.
			for (uint16 i = 0; i < (uint16)count - 2; i++)
			{
				debugIndices.Add(vertexStart + 0);
				debugIndices.Add(vertexStart + 4 * (i + 1));
				debugIndices.Add(vertexStart + 4 * (i + 2));
			}

			// Polygon outline triangles.
			for (uint16 i0 = 0; i0 < (uint16)count; i0++)
			{
				var i1 = (i0 + 1) % (uint16)count;
				debugIndices.Add(vertexStart + 4 * i0 + 0);
				debugIndices.Add(vertexStart + 4 * i0 + 1);
				debugIndices.Add(vertexStart + 4 * i0 + 2);
				debugIndices.Add(vertexStart + 4 * i0 + 0);
				debugIndices.Add(vertexStart + 4 * i0 + 2);
				debugIndices.Add(vertexStart + 4 * i0 + 3);
				debugIndices.Add(vertexStart + 4 * i0 + 0);
				debugIndices.Add(vertexStart + 4 * i0 + 3);
				debugIndices.Add(vertexStart + 4 * i1 + 0);
				debugIndices.Add(vertexStart + 4 * i0 + 3);
				debugIndices.Add(vertexStart + 4 * i1 + 0);
				debugIndices.Add(vertexStart + 4 * i1 + 1);
			}

			for (int i = 0; i < count; i++)
			{
				var v0 = verts[i].ToVector();
				var v_prev = verts[(i + (count - 1)) % count].ToVector();
				var v_next = verts[(i + (count + 1)) % count].ToVector();

				var n1 = Vector2.Normalize(Perpendicular(v0 - v_prev));
				var n2 = Vector2.Normalize(Perpendicular(v_next - v0));
				var of = (n1 + n2) / (Vector2.Dot(n1, n2) + 1.0f);
				var v = v0 + of * inset;

				debugVertices.Add(DebugVertex() { position = .((float)v.x, (float)v.y), uvAndRadius = .(0.0f, 0.0f, 0.0f), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
				debugVertices.Add(DebugVertex() { position = .((float)v.x, (float)v.y), uvAndRadius = .((float)n1.x, (float)n1.y, r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
				debugVertices.Add(DebugVertex() { position = .((float)v.x, (float)v.y), uvAndRadius = .((float)of.x, (float)of.y, r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
				debugVertices.Add(DebugVertex() { position = .((float)v.x, (float)v.y), uvAndRadius = .((float)n2.x, (float)n2.y, r), fillColor = fillColorRGBA, outlineColor = outlineColorRGBA });
			}
		}

		public static void DrawDot(Chipmunk2D.Real size, Chipmunk2D.Vector2 pos, Chipmunk2D.DebugColor color, void* data = null)
		{
			var r = (float)(size * 0.5f * DebugDrawPointLineScale);
			var fillColor = color.ToRGBA();
			var vertexStart = (uint16)debugVertices.Count;
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(-1, -1, r), fillColor = fillColor, outlineColor = fillColor });
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(-1, 1, r), fillColor = fillColor, outlineColor = fillColor });
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(1, 1, r), fillColor = fillColor, outlineColor = fillColor });
			debugVertices.Add(DebugVertex() { position = .((float)pos.x, (float)pos.y), uvAndRadius = .(1, -1, r), fillColor = fillColor, outlineColor = fillColor });
			for (var index in DebugQuadIndices)
			{
				debugIndices.Add(vertexStart + index);
			}
		}

		public static void DrawDot(float size, Vector2 pos, Color color)
		{
			DrawDot(size, Chipmunk2D.Vector2.FromVector(pos), .(color.r, color.g, color.b, color.a));
		}

		public static bool Initialize()
		{
			shader = ResourceManager.GetResource<Shader>("shaders/debug_draw");
			bgfx.vertex_layout_begin(&vertexLayout, bgfx.get_renderer_type());
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Position, 2, bgfx.AttribType.Float, false, false);
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.TexCoord0, 3, bgfx.AttribType.Float, false, false);
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.TexCoord1, 4, bgfx.AttribType.Uint8, true, false);
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.TexCoord2, 4, bgfx.AttribType.Uint8, true, false);
			bgfx.vertex_layout_end(&vertexLayout);
			return true;
		}

		public static void Render(uint16 viewId, bool render = true)
		{
			if (!render || debugVertices.Count == 0 || debugIndices.Count == 0)
			{
				debugVertices.Clear();
				debugIndices.Clear();
				return;
			}
			var tvb = bgfx.TransientVertexBuffer();
			let verticesSize = (uint32)(debugVertices.Count * sizeof(DebugVertex));
			bgfx.alloc_transient_vertex_buffer(&tvb, (uint32)debugVertices.Count, &vertexLayout);
			Internal.MemCpy(tvb.data, &debugVertices[0], (.)verticesSize);
			var tib = bgfx.TransientIndexBuffer();
			let indicesSize = (uint32)(debugIndices.Count * sizeof(uint16));
			bgfx.alloc_transient_index_buffer(&tib, indicesSize, false);
			Internal.MemCpy(tib.data, &debugIndices[0], (.)indicesSize);
			var stateFlags = bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.DepthTestAlways | bgfx.blend_function(bgfx.StateFlags.BlendOne, bgfx.StateFlags.BlendInvSrcAlpha);
			var identity = Matrix4.Identity;
			bgfx.set_transform(identity.Ptr(), 1);
			bgfx.set_state((uint64)stateFlags, 0);
			bgfx.set_transient_vertex_buffer(0, &tvb, 0, (uint32)debugVertices.Count);
			bgfx.set_transient_index_buffer(&tib, 0, (uint32)debugIndices.Count);
			bgfx.submit(viewId, shader.Programs[0], 0, (uint8)bgfx.DiscardFlags.All);
			++RenderManager.statistics.submitCount;
			debugVertices.Clear();
			debugIndices.Clear();
		}

	}
}
