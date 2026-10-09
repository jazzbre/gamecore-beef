using System;
using System.Collections;
using System.IO;

namespace GameCore;

[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
public class SlugFontResourceBuilder : ResourceBuilder
{
	private static readonly String[] ExtensionsStrings = new String[]("ttf", "otf", "slugfont") ~ delete _;
	public override String[] Extensions => ExtensionsStrings;
	public override Type ResourceType => typeof(SlugFontResource);

	private void GetConverterPath(String path)
	{
		path.Set(scope $"{ResourceManager.buildtimeToolsPath}slugconvert.exe");
	}

	public override bool OnCheckBuild(StringView path, StringView hash)
	{
		let destination = scope $"{ResourceManager.runtimeResourcesPath}{hash}.slugfont";
		if (!(File.GetLastWriteTimeUtc(destination) case .Ok(let outputTime)))
		{
			return true;
		}
		if (!(File.GetLastWriteTimeUtc(path) case .Ok(let sourceTime)))
		{
			return true;
		}
		if (sourceTime.Ticks > outputTime.Ticks)
		{
			return true;
		}
		if (!path.EndsWith(".slugfont", .OrdinalIgnoreCase))
		{
			let converterPath = scope String();
			GetConverterPath(converterPath);
			return File.GetLastWriteTimeUtc(converterPath) case .Ok(let converterTime) && converterTime.Ticks > outputTime.Ticks;
		}
		return false;
	}

	public override bool OnBuild(StringView path, StringView hash)
	{
#if RESOURCEBUILD
		let destination = scope $"{ResourceManager.runtimeResourcesPath}{hash}.slugfont";
		if (path.EndsWith(".slugfont", .OrdinalIgnoreCase))
		{
			let bytes = scope List<uint8>();
			let fontData = scope SlugFontData();
			if (File.ReadAll(path, bytes) case .Err || bytes.Count > SlugFontData.MaximumFileSize || !fontData.Read(.(bytes.Ptr, bytes.Count)))
			{
				Log.Error(scope $"Invalid prebuilt Slug font '{path}': {fontData.Error}");
				return false;
			}
			return SystemUtils.FileCopy(path, destination, true);
		}
		let converterPath = scope String();
		GetConverterPath(converterPath);
		if (!File.Exists(converterPath))
		{
			Log.Error(scope $"Slug font converter missing: {converterPath}");
			return false;
		}
		let arguments = scope $"\"{path}\" \"{destination}\" --charset latin";
		if (SystemUtils.ExecuteProcess(converterPath, arguments) != 0)
		{
			Log.Error(scope $"Slug font conversion failed: {path}");
			return false;
		}
		return File.Exists(destination);
#else
		return false;
#endif
	}
}
