using System;
using System.Collections;
using NoGraphicsAPI;

namespace GameCore;

public class SlugFontRenderer
{
	[CRepr]
	private struct GlyphVertex
	{
		public Vector4 Position;
		public Vector4 Sample;
		public Vector4 BandTransform;
	}

	private List<GlyphVertex> vertices = new .() ~ delete _;
	private List<uint32> indices = new .() ~ delete _;
	private GpuTexture[] textures = new GpuTexture[2] ~ delete _;
	private VertexLayout vertexLayout;

	public this()
	{
		vertexLayout.Begin();
		vertexLayout.Add(.Position, 4, .Float);
		vertexLayout.Add(.TexCoord0, 4, .Float);
		vertexLayout.Add(.TexCoord1, 4, .Float);
		vertexLayout.End();
	}

	public void DrawText(RenderCommandBuffer commands, SlugFontResource font, StringView text, Vector2 baselinePosition,
		float fontSize, Color color, FontFlags alignment = 0, Color shadowColor = .Black)
	{
		Draw(commands, font, text, baselinePosition.xy0, fontSize, color, alignment, shadowColor, false);
	}

	public void DrawWorldText(RenderCommandBuffer commands, SlugFontResource font, StringView text, Vector3 worldPosition,
		float fontSize, Color color, FontFlags alignment = 0, Color shadowColor = .Black)
	{
		Draw(commands, font, text, worldPosition, fontSize, color, alignment, shadowColor, true);
	}

	private void AddVertex(SlugFontGlyph glyph, Vector2 pen, Vector2 sample, Vector2 normal, float fontSize)
	{
		uint32 glyphLocation = glyph.GlyphLocation;
		uint32 bandMaximum = glyph.BandMaximum;
		vertices.Add(.()
		{
			Position = .((pen.x + sample.x) * fontSize, (pen.y + sample.y) * fontSize, normal.x, normal.y),
			Sample = .(sample.x, sample.y, *(float*)&glyphLocation, *(float*)&bandMaximum),
			BandTransform = glyph.BandTransform
		});
	}

	private void Draw(RenderCommandBuffer commands, SlugFontResource font, StringView text, Vector3 anchor,
		float fontSize, Color color, FontFlags alignment, Color shadowColor, bool worldSpace)
	{
		if (commands == null || font == null || !font.HasFont || text.IsEmpty || !fontSize.IsFinite || fontSize <= 0)
		{
			return;
		}
		let shader = RenderManager.GetShader(.Font);
		if (shader == null || shader.Programs.Count < 2)
		{
			return;
		}
		vertices.Clear();
		indices.Clear();
		Vector2 alignmentOffset = .Zero;
		if (alignment != 0)
		{
			let extents = font.GetTextExtents(text, fontSize);
			if ((alignment & .CenterX) != 0)
			{
				alignmentOffset.x = -extents.x * 0.5f;
			}
			if ((alignment & .RightAlign) != 0)
			{
				alignmentOffset.x = -extents.x;
			}
			if ((alignment & .CenterY) != 0)
			{
				alignmentOffset.y = -extents.y * 0.5f;
			}
			if ((alignment & .TopAlign) != 0)
			{
				alignmentOffset.y = -extents.y;
			}
		}
		Vector2 pen = .Zero;
		int previousGlyphId = -1;
		for (let character in text.DecodedChars)
		{
			if (!font.Data.AdvanceCharacter(character, ref pen, ref previousGlyphId, let glyph))
			{
				continue;
			}
			if (glyph.CurveCount > 0)
			{
				uint32 firstVertex = (uint32)vertices.Count;
				let glyphPen = pen + alignmentOffset / fontSize;
				AddVertex(glyph, glyphPen, .(glyph.Bounds.x, glyph.Bounds.y), .(-1, -1), fontSize);
				AddVertex(glyph, glyphPen, .(glyph.Bounds.z, glyph.Bounds.y), .(1, -1), fontSize);
				AddVertex(glyph, glyphPen, .(glyph.Bounds.z, glyph.Bounds.w), .(1, 1), fontSize);
				AddVertex(glyph, glyphPen, .(glyph.Bounds.x, glyph.Bounds.w), .(-1, 1), fontSize);
				indices.Add(firstVertex);
				indices.Add(firstVertex + 1);
				indices.Add(firstVertex + 2);
				indices.Add(firstVertex + 2);
				indices.Add(firstVertex + 3);
				indices.Add(firstVertex);
			}
			pen.x += glyph.Advance;
		}
		if (indices.Count == 0)
		{
			return;
		}
		let vertexBuffer = commands.TransientVertices(vertices.Ptr, (uint32)(vertices.Count * sizeof(GlyphVertex)), vertexLayout);
		let indexBuffer = commands.TransientIndices(indices.Ptr, (uint32)(indices.Count * sizeof(uint32)), .uint32);
		let world = Matrix4.CreateTranslation(anchor);
		textures[0] = font.CurveTexture;
		textures[1] = font.BandTexture;
		int programIndex = worldSpace ? 1 : 0;
		if (shadowColor.a > 0)
		{
			RenderManager.Draw(commands, shader, programIndex, vertexBuffer, indexBuffer, (uint32)vertices.Count, (uint32)indices.Count,
				world, shadowColor.xyzw, .(fontSize, 1, -1, 0), textures, .Premultiplied, RenderManager.PointClamp);
		}
		RenderManager.Draw(commands, shader, programIndex, vertexBuffer, indexBuffer, (uint32)vertices.Count, (uint32)indices.Count,
			world, color.xyzw, .(fontSize, 0, 0, 0), textures, .Premultiplied, RenderManager.PointClamp);
		textures[0] = textures[1] = null;
	}
}
