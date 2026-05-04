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

		private static var debugVertices = new List<DebugVertex>() ~ delete _;
		private static var debugTextsPool = new List<DebugText>() ~ DeleteContainerAndItems!(_);
		private static var debugTexts = new List<DebugText>() ~ DeleteContainerAndItems!(_);

		public static Font DebugFont { get; set; } = null;

		public static void DrawSegment(Vector3 a, Vector3 b, Color color)
		{
			var coloruint = color.ToRGBA();
			debugVertices.Add(DebugVertex() { position = a, color = coloruint });
			debugVertices.Add(DebugVertex() { position = b, color = coloruint });
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
			debugTexts.Add(debugText);
		}

		public static bool Initialize()
		{
			shader = ResourceManager.GetResource<Shader>("shaders/debug_draw3d");
			bgfx.vertex_layout_begin(&vertexLayout, bgfx.get_renderer_type());
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.Position, 3, bgfx.AttribType.Float, false, false);
			bgfx.vertex_layout_add(&vertexLayout, bgfx.Attrib.TexCoord0, 4, bgfx.AttribType.Uint8, true, false);
			bgfx.vertex_layout_end(&vertexLayout);
			return true;
		}

		private static void RenderText(uint16 viewId, DebugText debugText)
		{
			if (DebugFont == null)
			{
				return;
			}
			var matrix = Matrix4.Identity;
			var modelViewMatrix = Matrix4.Identity;
			modelViewMatrix.Translation = debugText.position;
			DebugFont.RenderText(RenderManager.batchRenderer, RenderManager.GetShader(.Font), viewId, .Zero, matrix, debugText.color, debugText.text, .Black, 0, .CenterX | .CenterY, null, modelViewMatrix);
		}

		public static void Render(uint16 viewId, bool render = true)
		{
			if (!render || (debugVertices.Count == 0 && debugTexts.Count == 0))
			{
				Clear();
				return;
			}
			var tvb = bgfx.TransientVertexBuffer();
			let verticesSize = (uint32)(debugVertices.Count * sizeof(DebugVertex));
			bgfx.alloc_transient_vertex_buffer(&tvb, (uint32)debugVertices.Count, &vertexLayout);
			Internal.MemCpy(tvb.data, &debugVertices[0], (.)verticesSize);
			var stateFlags = bgfx.StateFlags.PtLines | bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.WriteZ | bgfx.StateFlags.DepthTestLequal | bgfx.blend_function(bgfx.StateFlags.BlendOne, bgfx.StateFlags.BlendInvSrcAlpha);
			var identity = Matrix4.Identity;
			bgfx.set_transform(identity.Ptr(), 1);
			bgfx.set_state((uint64)stateFlags, 0);
			bgfx.set_transient_vertex_buffer(0, &tvb, 0, (uint32)debugVertices.Count);
			bgfx.submit(viewId, shader.Programs[0], 0, (uint8)bgfx.DiscardFlags.All);
			++RenderManager.statistics.submitCount;

			for (var debugText in debugTexts)
			{
				RenderText(viewId, debugText);
			}
		}

		public static void Clear()
		{
			debugVertices.Clear();
			for (var debugText in debugTexts)
			{
				debugTextsPool.Add(debugText);
			}
			debugTexts.Clear();
		}
	}
}
