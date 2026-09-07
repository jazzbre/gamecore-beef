using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	class DebugDraw3D
	{
		struct DebugVertex
		{
			public Vector3 position;
			public uint32 color;
		}

		class DebugText
		{
			public Vector3 position = .Zero;
			public String text = new .() ~ delete _;
			public Color color = .Black;
		}

		private static Shader shader;
		private static bgfx.VertexLayout vertexLayout;
		private static bgfx.VertexLayout cubeVertexLayout;

		private static var debugVertices = new List<DebugVertex>() ~ delete _;
		private static var debug2DVertices = new List<DebugVertex>() ~ delete _;
		private static var debugSolidVertices = new List<DebugVertex>() ~ delete _;
		private static var debugCubes = new List<Vector4>() ~ delete _;
		private static var debugTextsPool = new List<DebugText>() ~ DeleteContainerAndItems!(_);
		private static var debug2DTexts = new List<DebugText>() ~ DeleteContainerAndItems!(_);
		private static var debug3DTexts = new List<DebugText>() ~ DeleteContainerAndItems!(_);

		private static bgfx.VertexBufferHandle cube_vertex_buffer_handle = .Null;
		private static bgfx.IndexBufferHandle huge_index_buffer = .Null;

		public static Font DebugFont { get; set; } = null;

		public static void DrawSegment(Vector3 a, Vector3 b, Color color)
		{
			var coloruint = color.ToRGBA();
			debugVertices.Add(DebugVertex() { position = a, color = coloruint });
			debugVertices.Add(DebugVertex() { position = b, color = coloruint });
		}

		public static void DrawSegment(Vector2 start, Vector2 end, Color color, float thickness = 1.0f)
		{
			var segment = end - start;
			float segmentLength = segment.Length;
			if ((segmentLength <= 0.001f) || (thickness <= 0.0f))
			{
				return;
			}

			var perpendicular = Vector2(-segment.y, segment.x) * (thickness * 0.5f / segmentLength);
			var startLeft = (start + perpendicular).xy0;
			var startRight = (start - perpendicular).xy0;
			var endLeft = (end + perpendicular).xy0;
			var endRight = (end - perpendicular).xy0;
			uint32 packedColor = color.ToRGBA();

			debug2DVertices.Add(DebugVertex() { position = startLeft, color = packedColor });
			debug2DVertices.Add(DebugVertex() { position = endLeft, color = packedColor });
			debug2DVertices.Add(DebugVertex() { position = endRight, color = packedColor });
			debug2DVertices.Add(DebugVertex() { position = startLeft, color = packedColor });
			debug2DVertices.Add(DebugVertex() { position = endRight, color = packedColor });
			debug2DVertices.Add(DebugVertex() { position = startRight, color = packedColor });
		}

		public static void DrawTriangle(Vector3 a, Vector3 b, Vector3 c, Color color)
		{
			var coloruint = color.ToRGBA();
			debugVertices.Add(DebugVertex() { position = a, color = coloruint });
			debugVertices.Add(DebugVertex() { position = b, color = coloruint });
			debugVertices.Add(DebugVertex() { position = b, color = coloruint });
			debugVertices.Add(DebugVertex() { position = c, color = coloruint });
			debugVertices.Add(DebugVertex() { position = c, color = coloruint });
			debugVertices.Add(DebugVertex() { position = a, color = coloruint });
		}

		public static void DrawSolidTriangle(Vector3 a, Vector3 b, Vector3 c, Color color)
		{
			var coloruint = color.ToRGBA();
			debugSolidVertices.Add(DebugVertex() { position = a, color = coloruint });
			debugSolidVertices.Add(DebugVertex() { position = b, color = coloruint });
			debugSolidVertices.Add(DebugVertex() { position = c, color = coloruint });
		}

		public static void DrawSphere(Vector3 center, float radius, Color color, int32 segments = 24)
		{
			if (radius <= 0.0f)
			{
				return;
			}

			int32 safeSegments = Math.Max(segments, 6);
			DrawRing(center, radius, Vector3.Right, Vector3.Up, color, safeSegments);
			DrawRing(center, radius, Vector3.Right, Vector3.Forward, color, safeSegments);
			DrawRing(center, radius, Vector3.Forward, Vector3.Up, color, safeSegments);
		}

		public static void Sphere(Vector3 center, float radius, Color color, int32 segments = 24)
		{
			DrawSphere(center, radius, color, segments);
		}

		public static void DrawBox(Vector3 center, Vector3 size, Color color)
		{
			var half = size * 0.5f;
			DrawBoxEdges(
				center + Vector3(-half.x, -half.y, -half.z),
				center + Vector3(half.x, -half.y, -half.z),
				center + Vector3(half.x,  half.y, -half.z),
				center + Vector3(-half.x,  half.y, -half.z),
				center + Vector3(-half.x, -half.y,  half.z),
				center + Vector3(half.x, -half.y,  half.z),
				center + Vector3(half.x,  half.y,  half.z),
				center + Vector3(-half.x,  half.y,  half.z),
				color);
		}

		public static void DrawBox(Matrix4 worldMatrix, Vector3 halfExtents, Color color)
		{
			DrawBoxEdges(
				TransformBoxCorner(worldMatrix, -halfExtents.x, -halfExtents.y, -halfExtents.z),
				TransformBoxCorner(worldMatrix,  halfExtents.x, -halfExtents.y, -halfExtents.z),
				TransformBoxCorner(worldMatrix,  halfExtents.x,  halfExtents.y, -halfExtents.z),
				TransformBoxCorner(worldMatrix, -halfExtents.x,  halfExtents.y, -halfExtents.z),
				TransformBoxCorner(worldMatrix, -halfExtents.x, -halfExtents.y,  halfExtents.z),
				TransformBoxCorner(worldMatrix,  halfExtents.x, -halfExtents.y,  halfExtents.z),
				TransformBoxCorner(worldMatrix,  halfExtents.x,  halfExtents.y,  halfExtents.z),
				TransformBoxCorner(worldMatrix, -halfExtents.x,  halfExtents.y,  halfExtents.z),
				color);
		}

		public static void DrawSolidBox(Vector3 center, Vector3 size, Color color)
		{
			var half = size * 0.5f;
			var p0 = center + Vector3(-half.x, -half.y, -half.z);
			var p1 = center + Vector3(half.x, -half.y, -half.z);
			var p2 = center + Vector3(half.x,  half.y, -half.z);
			var p3 = center + Vector3(-half.x,  half.y, -half.z);
			var p4 = center + Vector3(-half.x, -half.y,  half.z);
			var p5 = center + Vector3(half.x, -half.y,  half.z);
			var p6 = center + Vector3(half.x,  half.y,  half.z);
			var p7 = center + Vector3(-half.x,  half.y,  half.z);
			DrawSolidTriangle(p0, p1, p2, color);
			DrawSolidTriangle(p0, p2, p3, color);
		}

		public static void Box(Vector3 center, Vector3 size, Color color)
		{
			DrawBox(center, size, color);
		}

		public static void Box(Matrix4 worldMatrix, Vector3 halfExtents, Color color)
		{
			DrawBox(worldMatrix, halfExtents, color);
		}

		public static void DrawCube(Vector3 center, float size, Color color)
		{
			Vector4 p = center.xyz0;
			p.w = size;
			debugCubes.Add(p);
			debugCubes.Add(color.xyzw);
		}

		private static void DrawRing(Vector3 center, float radius, Vector3 axisA, Vector3 axisB, Color color, int32 segments)
		{
			float angleStep = Math.PI_f * 2.0f / (float)segments;
			var previous = center + axisA * radius;
			for (int32 i = 1; i <= segments; ++i)
			{
				float angle = angleStep * (float)i;
				var next = center + axisA * (Math.Cos(angle) * radius) + axisB * (Math.Sin(angle) * radius);
				DrawSegment(previous, next, color);
				previous = next;
			}
		}

		private static Vector3 TransformBoxCorner(Matrix4 worldMatrix, float x, float y, float z)
		{
			return Vector3.Transform(Vector3(x, y, z), worldMatrix);
		}

		private static void DrawBoxEdges(Vector3 nearBottomLeft, Vector3 nearBottomRight, Vector3 nearTopRight, Vector3 nearTopLeft, Vector3 farBottomLeft, Vector3 farBottomRight, Vector3 farTopRight, Vector3 farTopLeft, Color color)
		{
			DrawSegment(nearBottomLeft, nearBottomRight, color);
			DrawSegment(nearBottomRight, nearTopRight, color);
			DrawSegment(nearTopRight, nearTopLeft, color);
			DrawSegment(nearTopLeft, nearBottomLeft, color);

			DrawSegment(farBottomLeft, farBottomRight, color);
			DrawSegment(farBottomRight, farTopRight, color);
			DrawSegment(farTopRight, farTopLeft, color);
			DrawSegment(farTopLeft, farBottomLeft, color);

			DrawSegment(nearBottomLeft, farBottomLeft, color);
			DrawSegment(nearBottomRight, farBottomRight, color);
			DrawSegment(nearTopRight, farTopRight, color);
			DrawSegment(nearTopLeft, farTopLeft, color);
		}

		private static DebugText PopDebugText()
		{
			if (debugTextsPool.Count > 0)
			{
				return debugTextsPool.PopBack();
			}
			return new DebugText();
		}

		public static void DrawText(Vector3 position, StringView text, Color color)
		{
			var debugText = PopDebugText();
			debugText.position = position;
			debugText.text.Set(text);
			debugText.color = color;
			debug3DTexts.Add(debugText);
		}

		public static void DrawText(Vector2 position, StringView text, Color color)
		{
			var debugText = PopDebugText();
			debugText.position = position.xy0;
			debugText.text.Set(text);
			debugText.color = color;
			debug2DTexts.Add(debugText);
		}

		static uint32 NUM_CUBE_INDICES = 3 * 3 * 2;

		public static bool Initialize()
		{
			shader = ResourceManager.GetResource<Shader>("shaders/debug_draw3d");
			bgfx.vertex_layout_begin(&vertexLayout, bgfx.get_renderer_type());
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Position, 3, bgfx.AttribType.Float, false, false);
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.TexCoord0, 4, bgfx.AttribType.Uint8, true, false);
			bgfx.vertex_layout_end(&vertexLayout);

			bgfx.vertex_layout_begin(&cubeVertexLayout, bgfx.get_renderer_type());
			bgfx.vertex_layout_add(&cubeVertexLayout, bgfx.Attrib.Position, 4, bgfx.AttribType.Float, false, false);
			bgfx.vertex_layout_end(&cubeVertexLayout);

			uint32 num_instances  = 64 * 64 * 64;

			let cube_indices = scope uint32[](
				0, 2, 1, 2, 3, 1,
				5, 4, 1, 1, 4, 0,
				0, 4, 6, 0, 6, 2,
				6, 5, 7, 6, 4, 5,
				2, 6, 3, 6, 7, 3,
				7, 1, 3, 7, 5, 1
				);
			uint32 NUM_CUBE_VERTICES = 8;
			uint32 num_indices  = num_instances  * NUM_CUBE_INDICES;
			var indices = new uint32[num_indices];
			defer delete indices;
			for (uint32 i = 0; i < num_indices; ++i)
			{
				let cube = i / NUM_CUBE_INDICES;
				let cube_local = i % NUM_CUBE_INDICES;
				indices[i] = cube_indices[cube_local] + cube * NUM_CUBE_VERTICES;
			}
			huge_index_buffer = bgfx.create_index_buffer(bgfx.copy(&indices[0], (uint32)(indices.Count * sizeof(uint32))), (uint16)bgfx.BufferFlags.Index32);
			return true;
		}

		private static void RenderText(uint16 viewId, DebugText debugText, int shaderProgramIndex)
		{
			if (DebugFont == null)
			{
				return;
			}
			var matrix = Matrix4.Identity;
			var modelViewMatrix = Matrix4.Identity;
			modelViewMatrix.Translation = debugText.position;
			DebugFont.RenderText(RenderManager.batchRenderer, RenderManager.GetShader(.Font), viewId, .Zero, matrix, debugText.color, debugText.text, .Black, shaderProgramIndex, 0, null, modelViewMatrix);
		}

		public static void Render(uint16 viewId, bool render = true)
		{
			if (!render || (debugVertices.Count == 0 && debug2DVertices.Count == 0 && debug2DTexts.Count == 0 && debug3DTexts.Count == 0 && debugSolidVertices.Count == 0 && debugCubes.Count == 0))
			{
				Clear();
				return;
			}

			let solidVerticesSize = (uint32)(debugSolidVertices.Count * sizeof(DebugVertex));
			if (solidVerticesSize > 0)
			{
				var tvb = bgfx.TransientVertexBuffer();
				bgfx.alloc_transient_vertex_buffer(&tvb, (uint32)debugSolidVertices.Count, &vertexLayout);
				Internal.MemCpy(tvb.data, &debugSolidVertices[0], (.)solidVerticesSize);
				var stateFlags = bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.WriteZ | bgfx.StateFlags.DepthTestLequal | bgfx.blend_function(bgfx.StateFlags.BlendOne, bgfx.StateFlags.BlendInvSrcAlpha);
				var identity = Matrix4.Identity;
				bgfx.set_transform(identity.Ptr(), 1);
				bgfx.set_state((uint64)stateFlags, 0);
				bgfx.set_transient_vertex_buffer(0, &tvb, 0, (uint32)debugSolidVertices.Count);
				bgfx.submit(viewId, shader.Programs[0], 0, (uint8)bgfx.DiscardFlags.All);
				++RenderManager.statistics.submitCount;
			}

			let verticesSize = (uint32)(debugVertices.Count * sizeof(DebugVertex));
			if (verticesSize > 0)
			{
				var tvb = bgfx.TransientVertexBuffer();
				bgfx.alloc_transient_vertex_buffer(&tvb, (uint32)debugVertices.Count, &vertexLayout);
				Internal.MemCpy(tvb.data, &debugVertices[0], (.)verticesSize);
				var stateFlags = bgfx.StateFlags.PtLines | bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.WriteZ | bgfx.StateFlags.DepthTestLequal | bgfx.blend_function(bgfx.StateFlags.BlendOne, bgfx.StateFlags.BlendInvSrcAlpha);
				var identity = Matrix4.Identity;
				bgfx.set_transform(identity.Ptr(), 1);
				bgfx.set_state((uint64)stateFlags, 0);
				bgfx.set_transient_vertex_buffer(0, &tvb, 0, (uint32)debugVertices.Count);
				bgfx.submit(viewId, shader.Programs[0], 0, (uint8)bgfx.DiscardFlags.All);
				++RenderManager.statistics.submitCount;
			}

			let cubeVerticesSize = (uint32)(debugCubes.Count * sizeof(Vector4));
			if (cubeVerticesSize > 0)
			{
				if (cube_vertex_buffer_handle.Valid)
				{
					bgfx.destroy_vertex_buffer(cube_vertex_buffer_handle);
				}
				cube_vertex_buffer_handle = bgfx.create_vertex_buffer(bgfx.copy(&debugCubes[0], (.)cubeVerticesSize), &cubeVertexLayout, (uint16)bgfx.BufferFlags.ComputeRead);
				var stateFlags = bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.WriteZ | bgfx.StateFlags.DepthTestLequal | bgfx.blend_function(bgfx.StateFlags.BlendOne, bgfx.StateFlags.BlendInvSrcAlpha);
				var identity = Matrix4.Identity;
				bgfx.set_transform(identity.Ptr(), 1);
				bgfx.set_state((uint64)stateFlags, 0);
				bgfx.set_compute_vertex_buffer(0, cube_vertex_buffer_handle, bgfx.Access.Read);
				uint32 instanceCount = ((uint32)debugCubes.Count / 2);
				bgfx.set_index_buffer(huge_index_buffer, 0, instanceCount * NUM_CUBE_INDICES);
				bgfx.set_vertex_count(instanceCount * 8);
				bgfx.submit(viewId, shader.Programs[1], 0, (uint8)bgfx.DiscardFlags.All);
				++RenderManager.statistics.submitCount;
			}

			let screenVerticesSize = (uint32)(debug2DVertices.Count * sizeof(DebugVertex));
			if (screenVerticesSize > 0)
			{
				var screenVertexBuffer = bgfx.TransientVertexBuffer();
				bgfx.alloc_transient_vertex_buffer(&screenVertexBuffer, (uint32)debug2DVertices.Count, &vertexLayout);
				Internal.MemCpy(screenVertexBuffer.data, &debug2DVertices[0], (.)screenVerticesSize);
				var stateFlags = bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.blend_function(bgfx.StateFlags.BlendSrcAlpha, bgfx.StateFlags.BlendInvSrcAlpha);
				var identity = Matrix4.Identity;
				bgfx.set_transform(identity.Ptr(), 1);
				bgfx.set_state((uint64)stateFlags, 0);
				bgfx.set_transient_vertex_buffer(0, &screenVertexBuffer, 0, (uint32)debug2DVertices.Count);
				bgfx.submit(viewId, shader.Programs[2], 0, (uint8)bgfx.DiscardFlags.All);
				++RenderManager.statistics.submitCount;
			}

			for (var debugText in debug2DTexts)
			{
				RenderText(viewId, debugText, 0);
			}
			for (var debugText in debug3DTexts)
			{
				RenderText(viewId, debugText, 1);
			}
			Clear();
		}

		public static void Clear()
		{
			debugVertices.Clear();
			debug2DVertices.Clear();
			debugSolidVertices.Clear();
			debugCubes.Clear();
			for (var debugText in debug2DTexts)
			{
				debugTextsPool.Add(debugText);
			}
			debug2DTexts.Clear();
			for (var debugText in debug3DTexts)
			{
				debugTextsPool.Add(debugText);
			}
			debug3DTexts.Clear();
		}
	}
}
