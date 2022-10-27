using System;
using System.IO;
using System.Collections;

namespace GameCore
{
	enum FontFlags
	{
		CenterX = 1 << 0,
		CenterY = 1 << 1,
		RightAlign = 1 << 2,
		TopAlign = 1 << 3,
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	public class FontGlyph
	{
		[JSON_Beef.Serialized]
		public int32 id;
		[JSON_Beef.Serialized]
		public int32 x;
		[JSON_Beef.Serialized]
		public int32 y;
		[JSON_Beef.Serialized]
		public int32 width;
		[JSON_Beef.Serialized]
		public int32 height;
		[JSON_Beef.Serialized]
		public int32 xOffset;
		[JSON_Beef.Serialized]
		public int32 yOffset;
		[JSON_Beef.Serialized]
		public int32 xAdvance;
		public int index;
		public Vector3 size = .Zero;
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	public class FontData
	{
		[JSON_Beef.Serialized]
		public var fontGlyphs = new List<FontGlyph>() ~ DeleteContainerAndItems!(_);
		[JSON_Beef.Serialized]
		public int32 lineHeight;
		[JSON_Beef.Serialized]
		public int32 baseHeight;
	}

	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	class Font : Resource
	{
		public FontData FontData => fontData;
		public Texture FontTexture { get; private set; }
		public Dictionary<char32, FontGlyph> FontGlyphs { get; private set; }

		private FontData fontData;

		public override void Initialize(System.String name, System.String hash)
		{
			base.Initialize(name, hash);
		}

		protected override void OnLoad()
		{
			// Load font json
			FontGlyphs = new Dictionary<char32, FontGlyph>();
			fontData = new FontData();
			var binaryFile = scope DynMemStream();
			if (!ResourceManager.ReadFile(scope $"{Hash}.json", binaryFile))
			{
				return;
			}
			var jsonText = StringView((char8*)binaryFile.Ptr, (int)binaryFile.Length);
			JSON_Beef.Serialization.JSONDeserializer.Deserialize<FontData>(jsonText, fontData);
			FontTexture = ResourceManager.GetResource<Texture>(scope $"{Name}_0");
			if (FontTexture == null)
			{
				return;
			}
			delete FontTexture.SpriteData;
			FontTexture.SpriteData = new Vector4[fontData.fontGlyphs.Count];
			let ooWidth = 1.0f / (float)FontTexture.Width;
			let ooHeight = 1.0f / (float)FontTexture.Height;
			for (int i = 0; i < fontData.fontGlyphs.Count; ++i)
			{
				var fontGlyph = fontData.fontGlyphs[i];
				fontGlyph.index = i;
				fontGlyph.size = .((float)fontGlyph.width, (float)fontGlyph.height, 0.0f);
				FontGlyphs.Add((char32)fontGlyph.id, fontGlyph);
				FontTexture.SpriteData[i] = .((float)fontGlyph.x * ooWidth, (float)fontGlyph.y * ooHeight, (float)(fontGlyph.x + fontGlyph.width) * ooWidth, (float)(fontGlyph.y + fontGlyph.height) * ooHeight);
			}
		}

		protected override void OnUnload()
		{
			DeleteAndNullify!(FontGlyphs);
			DeleteAndNullify!(fontData);
			FontTexture = null;
		}

		public typealias OnCharacterCallback = delegate void(int index, int lineIndex, ref Matrix4 worldMatrix, ref Color color);

		public void RenderText(SpriteBatchRenderer batchRenderer, Shader shader, uint16 viewId, Vector4 settings, Matrix4 _worldMatrix, Color color, StringView text, Color outlineColor = .Opaque, int shaderProgramIndex = 0, FontFlags fontFlags = 0, OnCharacterCallback characterCallback = null)
		{
			var pivot = Vector2(0.0f, -1.0f);
			var worldMatrix = _worldMatrix;
			var offsetY = (float)(fontData.lineHeight - fontData.baseHeight);
			batchRenderer.Begin(shader, viewId, settings, 0, 0, shaderProgramIndex);
			if (fontFlags != 0)
			{
				var extents = GetTextExtents(text);
				var offset = Vector3.Zero;
				if ((fontFlags & .CenterX) != 0)
				{
					offset.x = -extents.x * 0.5f;
				}
				if ((fontFlags & .CenterY) != 0)
				{
					offset.y = -extents.y * 0.5f;
				}
				if ((fontFlags & .RightAlign) != 0)
				{
					offset.x = -extents.x;
				}
				if ((fontFlags & .TopAlign) != 0)
				{
					offset.y = -extents.y;
				}
				worldMatrix.Translation = Vector3.Transform(offset, worldMatrix);
			}
			int lineCount = 0;
			int index = 0;
			let startPosition = worldMatrix.Translation;
			for (var c in text)
			{
				var glyphWorldMatrix = worldMatrix;
				++index;
				var characterColor = color;
				if (characterCallback != null)
				{
					characterCallback(index - 1, lineCount, ref glyphWorldMatrix, ref characterColor);
				}
				if (c == '\n')
				{
					++lineCount;
					worldMatrix.Translation = startPosition - Vector3.TransformNormal(.(0.0f, (float)fontData.lineHeight * (float)lineCount, 0.0f), worldMatrix);
					continue;
				}
				FontGlyph fontGlyph;
				if (!FontGlyphs.TryGetValue((char32)c, out fontGlyph))
				{
					continue;
				}
				glyphWorldMatrix.Translation += Vector3.TransformNormal(.((float)fontGlyph.xOffset, (float)fontData.lineHeight - (float)fontGlyph.yOffset - offsetY, 0.0f), worldMatrix);
				if (outlineColor.a > 0)
				{
					{
						var outlineGlyphWorldMatrix = glyphWorldMatrix;
						outlineGlyphWorldMatrix.Translation += Vector3.TransformNormal(.(1, -1, 0), worldMatrix);
						batchRenderer.Add(FontTexture, fontGlyph.index, fontGlyph.size, outlineGlyphWorldMatrix, outlineColor, pivot);
					}
				}
				batchRenderer.Add(FontTexture, fontGlyph.index, fontGlyph.size, glyphWorldMatrix, characterColor, pivot);
				worldMatrix.Translation += Vector3.TransformNormal(.((float)fontGlyph.xAdvance, 0.0f, 0.0f), worldMatrix);
			}
			batchRenderer.End();
		}

		public Vector2 GetTextExtents(StringView text, List<float> lineExtents = null)
		{
			var lineWidth = 0.0f;
			var extents = Vector2.Zero;
			extents.y = (float)fontData.lineHeight;
			var position = 0.0f;
			for (var c in text)
			{
				if (c == '\n')
				{
					lineExtents.Add(lineWidth);
					position = 0.0f;
					lineWidth = 0.0f;
					extents.y += (float)fontData.lineHeight;
					continue;
				}
				FontGlyph fontGlyph;
				if (!FontGlyphs.TryGetValue((char32)c, out fontGlyph))
				{
					continue;
				}
				var maxWidth = position + (float)(fontGlyph.xOffset + fontGlyph.width);
				extents.x = Math.Max(extents.x, maxWidth);
				lineWidth = Math.Max(lineWidth, maxWidth);
				position += fontGlyph.xAdvance;
			}
			if (lineExtents != null)
			{
				lineExtents.Add(lineWidth);
			}
			return extents;
		}
	}
}
