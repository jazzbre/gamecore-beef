using System;

namespace GameCore;

public struct SlugFontGlyph
{
	public float Advance;
	public Vector4 Bounds;
	public Vector4 BandTransform;
	public uint32 GlyphLocation;
	public uint32 BandMaximum;
	public uint32 FirstCurve;
	public uint32 CurveCount;
}

public enum FontFlags
{
	CenterX = 1 << 0,
	CenterY = 1 << 1,
	RightAlign = 1 << 2,
	TopAlign = 1 << 3,
}
