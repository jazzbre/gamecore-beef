using System;
using System.IO;
using NoGraphicsAPI;

namespace GameCore;

[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
public class SlugFontResource : Resource
{
	public SlugFontData Data { get; private set; } ~ delete _;
	public GpuTexture CurveTexture { get; private set; } ~ delete _;
	public GpuTexture BandTexture { get; private set; } ~ delete _;
	public bool HasFont => Data != null && CurveTexture != null && BandTexture != null;

	public ~this()
	{
		OnUnload();
	}

	protected override void OnLoad()
	{
		let bytes = scope DynMemStream();
		if (!ResourceManager.ReadFile(scope $"{Hash}.slugfont", bytes) || bytes.Length > SlugFontData.MaximumFileSize)
		{
			Log.Error(scope $"Could not read Slug font '{Name}'");
			return;
		}
		LoadBytes(.(bytes.Ptr, (int)bytes.Length));
	}

	public bool LoadBytes(Span<uint8> bytes)
	{
		let parsedData = new SlugFontData();
		if (!parsedData.Read(bytes))
		{
			Log.Error(scope $"Invalid Slug font '{Name}': {parsedData.Error}");
			delete parsedData;
			return false;
		}
		OnUnload();
		Data = parsedData;
		CurveTexture = new .(SlugFontData.TextureWidth, Data.CurveTextureHeight, .rgba32_float, .sampled,
			bytes.Ptr + Data.CurveTextureOffset, SlugFontData.TextureWidth * Data.CurveTextureHeight * 16);
		BandTexture = new .(SlugFontData.TextureWidth, Data.BandTextureHeight, .rgba32_float, .sampled,
			bytes.Ptr + Data.BandTextureOffset, SlugFontData.TextureWidth * Data.BandTextureHeight * 16);
		return true;
	}

	protected override void OnUnload()
	{
		DeleteAndNullify!(CurveTexture);
		DeleteAndNullify!(BandTexture);
		DeleteAndNullify!(Data);
	}

	public Vector2 GetTextExtents(StringView text, float fontSize)
	{
		return Data != null ? Data.GetTextExtents(text, fontSize) : .Zero;
	}
}
