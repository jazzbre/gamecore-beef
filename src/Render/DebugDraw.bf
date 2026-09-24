using NoGraphicsAPI;
using System;
using System.Collections;

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
        private static VertexLayout vertexLayout;

        private static var debugVertices = new List<DebugVertex>() ~ delete _;
        private static var debugIndices = new List<uint16>() ~ delete _;

        // Debug draw

        public static void DrawCircle(Vector2 pos, float angle, float radius, Color outlineColor, Color fillColor)
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

        public static void DrawSegment(Vector2 a, Vector2 b, Color color)
        {
            DrawFatSegment(a, b, 0.5f, color, color);
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

        public static void DrawFatSegment(Vector2 a, Vector2 b, float radius, Color outlineColor, Color fillColor)
        {
            var r = (float)(radius + DebugDrawPointLineScale);
            var t = Vector2.Normalize(b - a);

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

        static Vector2 Perpendicular(Vector2 v)
        {
            return .(v.y, -v.x);
        }

        public static void DrawPolygon(int32 count, Vector2* verts, float radius, Color outlineColor, Color fillColor)
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
                var v0 = verts[i];
                var v_prev = verts[(i + (count - 1)) % count];
                var v_next = verts[(i + (count + 1)) % count];

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

        public static void DrawDot(float size, Vector2 pos, Color color)
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

        public static bool Initialize()
        {
            shader = ResourceManager.GetResource<Shader>("shaders/debug_draw");
            vertexLayout.Begin();
            vertexLayout.Add(VertexAttribute.Position, 2, VertexComponent.Float, false, false);
            vertexLayout.Add(VertexAttribute.TexCoord0, 3, VertexComponent.Float, false, false);
            vertexLayout.Add(VertexAttribute.TexCoord1, 4, VertexComponent.Uint8, true, false);
            vertexLayout.Add(VertexAttribute.TexCoord2, 4, VertexComponent.Uint8, true, false);
            vertexLayout.End();
            return true;
        }

        public static void Render(RenderCommandBuffer commandBuffer, bool render = true)
        {
            if (render && debugVertices.Count > 0 && debugIndices.Count > 0)
            {
                var vertices = commandBuffer.TransientVertices(debugVertices.Ptr, (uint32)(debugVertices.Count * sizeof(DebugVertex)), vertexLayout);
                var indices = commandBuffer.TransientIndices(debugIndices.Ptr, (uint32)(debugIndices.Count * sizeof(uint16)));
                RenderManager.Draw(commandBuffer, shader, 0, vertices, indices, (.)debugVertices.Count, (.)debugIndices.Count,
                    .Identity, .One, .Zero, state: .Premultiplied);
            }
            debugVertices.Clear();
            debugIndices.Clear();
        }

    }
}
