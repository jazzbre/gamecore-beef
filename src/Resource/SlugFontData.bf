using System;
using System.Collections;

namespace GameCore;

public class SlugFontData
{
	private struct CodepointMapping
	{
		public uint32 Codepoint;
		public uint32 GlyphId;
	}

	private struct KerningPair
	{
		public uint64 Key;
		public float Adjustment;
	}

	public const uint32 TextureWidth = 4096;
	public const int MaximumFileSize = 512 * 1024 * 1024;
	private static uint32[256] checksumTable = CreateChecksumTable();
	private List<SlugFontGlyph> glyphs = new .() ~ delete _;
	private List<CodepointMapping> codepointMappings = new .() ~ delete _;
	private List<KerningPair> kerningPairs = new .() ~ delete _;
	private uint32 fallbackGlyphId;
	public float Ascent { get; private set; }
	public float Descent { get; private set; }
	public float LineGap { get; private set; }
	public float LineHeight => Ascent - Descent + LineGap;
	public int GlyphCount => glyphs.Count;
	public uint32 CurveTextureHeight { get; private set; }
	public uint32 BandTextureHeight { get; private set; }
	public int CurveTextureOffset { get; private set; }
	public int BandTextureOffset { get; private set; }
	public String Error = new .() ~ delete _;

	private static uint32[256] CreateChecksumTable()
	{
		uint32[256] table = default;
		for (uint32 index = 0; index < 256; index++)
		{
			uint32 checksum = index;
			for (int bit = 0; bit < 8; bit++)
			{
				checksum = (checksum >> 1) ^ ((checksum & 1) != 0 ? 0xEDB88320U : 0U);
			}
			table[index] = checksum;
		}
		return table;
	}

	private static uint32 ReadUnsigned32(Span<uint8> bytes, int offset)
	{
		return (uint32)bytes[offset] | ((uint32)bytes[offset + 1] << 8) |
			((uint32)bytes[offset + 2] << 16) | ((uint32)bytes[offset + 3] << 24);
	}

	private static uint64 ReadUnsigned64(Span<uint8> bytes, int offset)
	{
		return (uint64)ReadUnsigned32(bytes, offset) | ((uint64)ReadUnsigned32(bytes, offset + 4) << 32);
	}

	private static float ReadFloat(Span<uint8> bytes, int offset)
	{
		uint32 bits = ReadUnsigned32(bytes, offset);
		return *(float*)&bits;
	}

	private bool Fail(StringView message)
	{
		Error.Set(message);
		glyphs.Clear();
		codepointMappings.Clear();
		kerningPairs.Clear();
		Ascent = Descent = LineGap = 0;
		return false;
	}

	public bool Read(Span<uint8> bytes)
	{
		Error.Clear();
		glyphs.Clear();
		codepointMappings.Clear();
		kerningPairs.Clear();
		if (bytes.Length < 288 || bytes.Length > MaximumFileSize)
		{
			return Fail("Invalid Slug font file size");
		}
		if (ReadUnsigned32(bytes, 0) != 0x46474C53 || ReadUnsigned32(bytes, 4) != 0x01200001 ||
			ReadUnsigned32(bytes, 8) != 0x01020304 || ReadUnsigned32(bytes, 12) != 0 ||
			ReadUnsigned64(bytes, 16) != (uint64)bytes.Length || ReadUnsigned32(bytes, 28) != 5 ||
			ReadUnsigned32(bytes, 48) != TextureWidth || ReadUnsigned32(bytes, 60) != 1 ||
			ReadUnsigned32(bytes, 64) != 7 || ReadUnsigned32(bytes, 88) != 80 ||
			ReadUnsigned32(bytes, 92) != 8 || ReadUnsigned32(bytes, 96) != 12 || ReadUnsigned32(bytes, 100) != 8)
		{
			return Fail("Unsupported Slug font header, version, or texture format");
		}
		uint32 checksum = uint32.MaxValue;
		for (int offset = 0; offset < bytes.Length; offset++)
		{
			uint8 value = offset >= 24 && offset < 28 ? 0 : bytes[offset];
			checksum = (checksum >> 8) ^ checksumTable[(checksum ^ value) & 255];
		}
		if ((checksum ^ uint32.MaxValue) != ReadUnsigned32(bytes, 24))
		{
			return Fail("Slug font CRC32 checksum mismatch");
		}
		for (int offset = 104; offset < 128; offset++)
		{
			if (bytes[offset] != 0)
			{
				return Fail("Unsupported Slug font reserved fields");
			}
		}
		Ascent = ReadFloat(bytes, 72);
		Descent = ReadFloat(bytes, 76);
		LineGap = ReadFloat(bytes, 80);
		CurveTextureHeight = ReadUnsigned32(bytes, 52);
		BandTextureHeight = ReadUnsigned32(bytes, 56);
		uint32 unitsPerEm = ReadUnsigned32(bytes, 68);
		uint32 curveCount = ReadUnsigned32(bytes, 84);
		fallbackGlyphId = ReadUnsigned32(bytes, 44);
		uint32 glyphCount = ReadUnsigned32(bytes, 32);
		uint32 mappingCount = ReadUnsigned32(bytes, 36);
		uint32 pairCount = ReadUnsigned32(bytes, 40);
		if (!Ascent.IsFinite || !Descent.IsFinite || !LineGap.IsFinite || !LineHeight.IsFinite ||
			Ascent <= Descent || LineHeight <= 0 || unitsPerEm == 0 || unitsPerEm > 65535 ||
			glyphCount == 0 || glyphCount != BandTextureHeight || mappingCount == 0 || fallbackGlyphId >= glyphCount ||
			CurveTextureHeight == 0 || CurveTextureHeight > 16384 || BandTextureHeight > 16384 ||
			CurveTextureHeight != Math.Max(1UL, ((uint64)curveCount * 2 + TextureWidth - 1) / TextureWidth))
		{
			return Fail("Invalid Slug font metrics or texture dimensions");
		}
		uint32[5] strides = .(80, 8, 12, 16, 16);
		uint64[5] counts = .(glyphCount, mappingCount, pairCount,
			(uint64)TextureWidth * CurveTextureHeight, (uint64)TextureWidth * BandTextureHeight);
		int[5] sectionOffsets = default;
		uint64 previousEnd = 288;
		for (int sectionIndex = 0; sectionIndex < 5; sectionIndex++)
		{
			int directoryOffset = 128 + sectionIndex * 32;
			uint64 sectionOffset = ReadUnsigned64(bytes, directoryOffset + 8);
			uint64 sectionSize = ReadUnsigned64(bytes, directoryOffset + 16);
			if (ReadUnsigned32(bytes, directoryOffset) != sectionIndex + 1 ||
				ReadUnsigned32(bytes, directoryOffset + 4) != strides[sectionIndex] ||
				ReadUnsigned64(bytes, directoryOffset + 24) != counts[sectionIndex] ||
				sectionSize != counts[sectionIndex] * strides[sectionIndex] || sectionOffset != ((previousEnd + 15) & ~15UL) ||
				sectionOffset > (uint64)bytes.Length || sectionSize > (uint64)bytes.Length - sectionOffset)
			{
				return Fail("Invalid, overlapping, or truncated Slug font section");
			}
			for (int offset = (int)previousEnd; offset < (int)sectionOffset; offset++)
			{
				if (bytes[offset] != 0)
				{
					return Fail("Invalid Slug font alignment padding");
				}
			}
			sectionOffsets[sectionIndex] = (int)sectionOffset;
			previousEnd = sectionOffset + sectionSize;
		}
		if (previousEnd != (uint64)bytes.Length)
		{
			return Fail("Unexpected trailing Slug font data");
		}
		CurveTextureOffset = sectionOffsets[3];
		BandTextureOffset = sectionOffsets[4];
		uint32 nextCurve = 0;
		uint32 previousSourceGlyph = 0;
		for (uint32 glyphId = 0; glyphId < glyphCount; glyphId++)
		{
			int offset = sectionOffsets[0] + (int)glyphId * 80;
			uint32 sourceGlyph = ReadUnsigned32(bytes, offset + 4);
			for (int componentOffset = 8; componentOffset <= 32; componentOffset += 4)
			{
				if (!ReadFloat(bytes, offset + componentOffset).IsFinite)
				{
					return Fail("Non-finite Slug glyph metric");
				}
			}
			SlugFontGlyph glyph = .();
			glyph.Advance = ReadFloat(bytes, offset + 8);
			glyph.Bounds = .(ReadFloat(bytes, offset + 20), ReadFloat(bytes, offset + 24), ReadFloat(bytes, offset + 28), ReadFloat(bytes, offset + 32));
			glyph.GlyphLocation = ReadUnsigned32(bytes, offset + 36);
			glyph.BandMaximum = ReadUnsigned32(bytes, offset + 40);
			glyph.BandTransform = .(ReadFloat(bytes, offset + 44), ReadFloat(bytes, offset + 48), ReadFloat(bytes, offset + 52), ReadFloat(bytes, offset + 56));
			glyph.FirstCurve = ReadUnsigned32(bytes, offset + 60);
			glyph.CurveCount = ReadUnsigned32(bytes, offset + 64);
			if (ReadUnsigned32(bytes, offset) != glyphId || sourceGlyph > 65535 ||
				(glyphId == 0 ? sourceGlyph != 0 : sourceGlyph <= previousSourceGlyph) ||
				glyph.Bounds.x > glyph.Bounds.z || glyph.Bounds.y > glyph.Bounds.w || glyph.GlyphLocation != (glyphId << 16) ||
				(glyph.BandMaximum & 65535) >= 8 || (glyph.BandMaximum >> 16) >= 8 ||
				!glyph.BandTransform.x.IsFinite || !glyph.BandTransform.y.IsFinite ||
				!glyph.BandTransform.z.IsFinite || !glyph.BandTransform.w.IsFinite ||
				glyph.BandTransform.x < 0 || glyph.BandTransform.y < 0 ||
				glyph.FirstCurve != nextCurve || glyph.CurveCount > curveCount - nextCurve ||
				ReadUnsigned32(bytes, offset + 68) != (glyph.CurveCount == 0 ? 1U : 0U) || ReadUnsigned64(bytes, offset + 72) != 0)
			{
				return Fail("Invalid Slug glyph bounds, bands, or curve range");
			}
			if (glyph.CurveCount == 0)
			{
				if (glyph.BandMaximum != 0 || glyph.BandTransform != .Zero)
				{
					return Fail("Invalid empty Slug glyph bands");
				}
			}
			else
			{
				uint32 bandCount = Math.Clamp(glyph.CurveCount / 2, 1U, 8U);
				float width = glyph.Bounds.z - glyph.Bounds.x;
				float height = glyph.Bounds.w - glyph.Bounds.y;
				float scaleX = width > 0 ? (float)bandCount / width : 0;
				float scaleY = height > 0 ? (float)bandCount / height : 0;
				if (!width.IsFinite || !height.IsFinite ||
					(glyph.BandMaximum & 65535) != bandCount - 1 || (glyph.BandMaximum >> 16) != bandCount - 1 ||
					!NearlyEqual(glyph.BandTransform.x, scaleX) || !NearlyEqual(glyph.BandTransform.y, scaleY) ||
					!NearlyEqual(glyph.BandTransform.z, -glyph.Bounds.x * scaleX) || !NearlyEqual(glyph.BandTransform.w, -glyph.Bounds.y * scaleY))
				{
					return Fail("Slug band transform does not match glyph bounds");
				}
			}
			nextCurve += glyph.CurveCount;
			previousSourceGlyph = sourceGlyph;
			glyphs.Add(glyph);
		}
		if (nextCurve != curveCount)
		{
			return Fail("Slug glyph ranges do not cover the curve texture");
		}
		for (uint32 mappingIndex = 0; mappingIndex < mappingCount; mappingIndex++)
		{
			int offset = sectionOffsets[1] + (int)mappingIndex * 8;
			CodepointMapping mapping = .() { Codepoint = ReadUnsigned32(bytes, offset), GlyphId = ReadUnsigned32(bytes, offset + 4) };
			if (mapping.Codepoint > 0x10FFFF || (mapping.Codepoint >= 0xD800 && mapping.Codepoint <= 0xDFFF) ||
				mapping.GlyphId >= glyphCount || (mappingIndex == 0 ? mapping.Codepoint != 0 || mapping.GlyphId != 0 : mapping.Codepoint <= codepointMappings.Back.Codepoint))
			{
				return Fail("Invalid Slug character mapping");
			}
			codepointMappings.Add(mapping);
		}
		for (uint32 pairIndex = 0; pairIndex < pairCount; pairIndex++)
		{
			int offset = sectionOffsets[2] + (int)pairIndex * 12;
			uint32 leftGlyphId = ReadUnsigned32(bytes, offset);
			uint32 rightGlyphId = ReadUnsigned32(bytes, offset + 4);
			KerningPair pair = .() { Key = ((uint64)leftGlyphId << 32) | rightGlyphId, Adjustment = ReadFloat(bytes, offset + 8) };
			if (leftGlyphId >= glyphCount || rightGlyphId >= glyphCount || !pair.Adjustment.IsFinite || pair.Adjustment == 0 ||
				(pairIndex > 0 && pair.Key <= kerningPairs.Back.Key))
			{
				return Fail("Invalid Slug kerning pair");
			}
			kerningPairs.Add(pair);
		}
		for (int offset = CurveTextureOffset; offset < bytes.Length; offset += 4)
		{
			if (!ReadFloat(bytes, offset).IsFinite)
			{
				return Fail("Non-finite Slug texture value");
			}
		}
		for (uint32 curveIndex = 0; curveIndex < curveCount; curveIndex++)
		{
			if (ReadUnsigned64(bytes, CurveTextureOffset + (int)curveIndex * 32 + 24) != 0)
			{
				return Fail("Invalid Slug curve texel padding");
			}
		}
		return ValidateBandReferences(bytes);
	}

	private static bool NearlyEqual(float first, float second)
	{
		return Math.Abs(first - second) <= Math.Max(1.0f, Math.Max(Math.Abs(first), Math.Abs(second))) * 0.00001f;
	}

	private bool ValidateBandReferences(Span<uint8> bytes)
	{
		for (int glyphId = 0; glyphId < glyphs.Count; glyphId++)
		{
			let glyph = glyphs[glyphId];
			int rowOffset = BandTextureOffset + glyphId * (int)TextureWidth * 16;
			int horizontalBandCount = (int)(glyph.BandMaximum >> 16) + 1;
			int headerCount = horizontalBandCount + (int)(glyph.BandMaximum & 65535) + 1;
			int expectedOffset = glyph.CurveCount == 0 ? 0 : headerCount;
			for (int headerIndex = 0; headerIndex < headerCount; headerIndex++)
			{
				int headerOffset = rowOffset + headerIndex * 16;
				float countValue = ReadFloat(bytes, headerOffset);
				float offsetValue = ReadFloat(bytes, headerOffset + 4);
				if (countValue < 0 || countValue > TextureWidth || countValue != Math.Floor(countValue) ||
					offsetValue != expectedOffset || countValue > TextureWidth - expectedOffset ||
					ReadUnsigned64(bytes, headerOffset + 8) != 0)
				{
					return Fail("Invalid Slug band header");
				}
				float previousMaximum = float.PositiveInfinity;
				for (int referenceIndex = 0; referenceIndex < (int)countValue; referenceIndex++)
				{
					int referenceOffset = rowOffset + (expectedOffset + referenceIndex) * 16;
					float curveX = ReadFloat(bytes, referenceOffset);
					float curveY = ReadFloat(bytes, referenceOffset + 4);
					if (curveX < 0 || curveX > TextureWidth - 2 || curveX != Math.Floor(curveX) ||
						curveY < 0 || curveY >= CurveTextureHeight || curveY != Math.Floor(curveY) ||
						ReadUnsigned64(bytes, referenceOffset + 8) != 0)
					{
						return Fail("Invalid Slug curve location");
					}
					uint32 curveTexel = (uint32)curveY * TextureWidth + (uint32)curveX;
					if ((curveTexel & 1) != 0 || curveTexel / 2 < glyph.FirstCurve || curveTexel / 2 - glyph.FirstCurve >= glyph.CurveCount)
					{
						return Fail("Slug band references a curve outside its glyph");
					}
					int curveOffset = CurveTextureOffset + (int)curveTexel * 16 + (headerIndex < horizontalBandCount ? 0 : 4);
					float curveMaximum = Math.Max(ReadFloat(bytes, curveOffset), Math.Max(ReadFloat(bytes, curveOffset + 8), ReadFloat(bytes, curveOffset + 16)));
					if (curveMaximum > previousMaximum)
					{
						return Fail("Slug band curves are not sorted");
					}
					previousMaximum = curveMaximum;
				}
				expectedOffset += (int)countValue;
			}
		}
		return true;
	}

	public int FindGlyphId(char32 codepoint)
	{
		int minimum = 0;
		int maximum = codepointMappings.Count;
		while (minimum < maximum)
		{
			int middle = minimum + (maximum - minimum) / 2;
			if (codepointMappings[middle].Codepoint < (uint32)codepoint)
			{
				minimum = middle + 1;
			}
			else
			{
				maximum = middle;
			}
		}
		return (int)(minimum < codepointMappings.Count && codepointMappings[minimum].Codepoint == (uint32)codepoint ? codepointMappings[minimum].GlyphId : fallbackGlyphId);
	}

	public float GetKerning(int leftGlyphId, int rightGlyphId)
	{
		uint64 key = ((uint64)leftGlyphId << 32) | (uint32)rightGlyphId;
		int minimum = 0;
		int maximum = kerningPairs.Count;
		while (minimum < maximum)
		{
			int middle = minimum + (maximum - minimum) / 2;
			if (kerningPairs[middle].Key < key)
			{
				minimum = middle + 1;
			}
			else
			{
				maximum = middle;
			}
		}
		return minimum < kerningPairs.Count && kerningPairs[minimum].Key == key ? kerningPairs[minimum].Adjustment : 0;
	}

	public bool AdvanceCharacter(char32 character, ref Vector2 pen, ref int previousGlyphId, out SlugFontGlyph glyph)
	{
		glyph = default;
		if (character == '\r')
		{
			return false;
		}
		if (character == '\n')
		{
			pen.x = 0;
			pen.y -= LineHeight;
			previousGlyphId = -1;
			return false;
		}
		if (character == '\t')
		{
			float tabWidth = Math.Max(glyphs[FindGlyphId(' ')].Advance * 4, 0.001f);
			pen.x = (Math.Floor(pen.x / tabWidth) + 1) * tabWidth;
			previousGlyphId = -1;
			return false;
		}
		int glyphId = FindGlyphId(character);
		glyph = glyphs[glyphId];
		if (previousGlyphId >= 0)
		{
			pen.x += GetKerning(previousGlyphId, glyphId);
		}
		previousGlyphId = glyphId;
		return true;
	}

	public Vector2 GetTextExtents(StringView text, float fontSize)
	{
		if (glyphs.Count == 0 || text.IsEmpty || !fontSize.IsFinite || fontSize <= 0)
		{
			return .Zero;
		}
		Vector2 pen = .Zero;
		float maximumWidth = 0;
		int previousGlyphId = -1;
		for (let character in text.DecodedChars)
		{
			if (AdvanceCharacter(character, ref pen, ref previousGlyphId, let glyph))
			{
				maximumWidth = Math.Max(maximumWidth, pen.x + glyph.Bounds.z);
				pen.x += glyph.Advance;
			}
			maximumWidth = Math.Max(maximumWidth, pen.x);
		}
		return .(maximumWidth * fontSize, (LineHeight - pen.y) * fontSize);
	}
}
