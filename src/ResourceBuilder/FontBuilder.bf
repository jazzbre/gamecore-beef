using System;
using System.Collections;
using System.IO;

namespace GameCore
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class FontBuilder : ResourceBuilder
	{
		private static readonly String[] ExtensionsStrings = new String[]("fnt") ~ delete _;

		public override String[] Extensions => ExtensionsStrings; public override Type ResourceType => typeof(Font);

		public override bool OnBuild(StringView path, StringView hash)
		{
#if RESOURCEBUILD
			var fontBinaryPath = scope String()..AppendF("{}{}.json", ResourceManager.runtimeResourcesPath, hash);
			// Fill
			var fontData = new FontData();
			var text = scope String();
			File.ReadAllText(path, text);
			var lines = text.Split('\n');
			var valueSplits = scope List<StringView>();
			int lineIndex = -1;
			for (var line in lines)
			{
				++lineIndex;
				var splits = line.Split(' ');
				FontGlyph fontGlyph = null;
				int index = 0;
				for (var split in splits)
				{
					++index;
					valueSplits.Clear();
					for (var value in split.Split('='))
					{
						valueSplits.Add(value);
					}
					if (lineIndex == 1)
					{
						if (valueSplits.Count != 2)
						{
							continue;
						}
						switch (valueSplits[0]) {
						case "lineHeight":
							fontData.lineHeight = int32.Parse(valueSplits[1]);
							break;
						case "base":
							fontData.baseHeight = int32.Parse(valueSplits[1]);
							break;
						}
					}
					else if (lineIndex >= 4)
					{
						if (index == 1)
						{
							if (valueSplits[0] != "char")
							{
								continue;
							}
							fontGlyph = new FontGlyph();
							fontData.fontGlyphs.Add(fontGlyph);
							continue;
						}
						if (valueSplits.Count != 2)
						{
							continue;
						}
						switch (valueSplits[0]) {
						case "id":
							fontGlyph.id = int32.Parse(valueSplits[1]);
							break;
						case "x":
							fontGlyph.x = int32.Parse(valueSplits[1]);
							break;
						case "y":
							fontGlyph.y = int32.Parse(valueSplits[1]);
							break;
						case "width":
							fontGlyph.width = int32.Parse(valueSplits[1]);
							break;
						case "height":
							fontGlyph.height = int32.Parse(valueSplits[1]);
							break;
						case "xoffset":
							fontGlyph.xOffset = int32.Parse(valueSplits[1]);
							break;
						case "yoffset":
							fontGlyph.yOffset = int32.Parse(valueSplits[1]);
							break;
						case "xadvance":
							fontGlyph.xAdvance = int32.Parse(valueSplits[1]);
							break;
						}
					}
				}
			}
			// Convert to json and save
			let jsonString = JSON_Beef.Serialization.JSONSerializer.Serialize<String>(fontData);
			File.WriteAllText(fontBinaryPath, jsonString.Value);
			delete jsonString.Value;
			delete fontData;
#endif
			return true;
		}

		public override bool OnCheckBuild(StringView path, StringView hash)
		{
			var fontBinaryPath = scope String()..AppendF("{}{}.json", ResourceManager.runtimeResourcesPath, hash);
			var sourceDateTime = SystemUtils.GetLatestTimestamp(path);
			var destinationDateTime = SystemUtils.GetLatestTimestamp(fontBinaryPath);
			return sourceDateTime > destinationDateTime;
		}
	}
}