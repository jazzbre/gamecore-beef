using System;
using System.Collections;
using System.IO;

namespace GameCore
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class TextureBuilder : ResourceBuilder
	{
		public static readonly char8[] XmlSplits = new char8[](' ', '\"', '<', '>') ~ delete _;
		private static readonly String[] ExtensionsStrings = new String[]("png") ~ delete _;

		public override String[] Extensions => ExtensionsStrings;

		public override Type ResourceType => typeof(Texture);

		public override bool OnCheckBuild(StringView path, StringView hash)
		{
			var texAtlasPath = scope String()..AppendF("{}{}.json", ResourceManager.runtimeResourcesPath, hash);
			var texBinaryPath = scope String()..AppendF("{}{}.ktx", ResourceManager.runtimeResourcesPath, hash);
			var sourceDateTime = SystemUtils.GetLatestTimestamp(path);
			var destinationDateTime = SystemUtils.GetLatestTimestamp(texBinaryPath, texAtlasPath);
			return sourceDateTime > destinationDateTime;
		}


		[CRepr]
		struct KTXHeader
		{
			public char8[12] identifier;
			public uint32 endianness;
			public uint32 gltype;
			public uint32 gltypesize;
			public uint32 glformat;
			public uint32 glinternalformat;
			public uint32 glbaseinternalformat;
			public uint32 pixelwidth;
			public uint32 pixelheight;
			public uint32 pixeldepth;
			public uint32 arrayelements;
			public uint32 faces;
			public uint32 miplevels;
			public uint32 keypairbytes;
		}

		[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
		class ConvexHullBuild
		{
			public var points = new List<float>() ~ delete _;
		}

		void GenerateConvexHull(uint8* image, int width, int height, int stride, Sprite sprite)
		{
			if (width <= 1 || height <= 1)
			{
				return;
			}
			var points = scope List<Chipmunk2D.Vector2>();
			var pointsHashSet = scope HashSet<int>();
			double centerX = 0;
			double centerY = 0;
			double pixelCount = 0;
			double r = 0, g = 0, b = 0;
			double oo255 = 1.0 / 255.0;
			// Horizontal
			for (int y = 0; y < height; ++y)
			{
				var imageLine = &image[y * stride];
				int min = int.MaxValue;
				int max = int.MinValue;
				for (int x = 0; x < width; ++x,imageLine += 4)
				{
					if (imageLine[3] > 0)
					{
						r += (double)imageLine[0] * oo255;
						g += (double)imageLine[1] * oo255;
						b += (double)imageLine[2] * oo255;
						min = Math.Min(min, x);
						max = Math.Max(max, x);
						pixelCount += 1;
						centerX += x;
						centerY += y;
					}
				}
				if (min <= max)
				{
					if (pointsHashSet.Add(y * width + min))
					{
						points.Add(.(min, y));
					}
					if (min != max)
					{
						if (pointsHashSet.Add(y * width + max))
						{
							points.Add(.(max, y));
						}
					}
				}
			}
			// Vertical
			for (int x = 0; x < width; ++x)
			{
				var imageLine = &image[x * 4];
				int min = int.MaxValue;
				int max = int.MinValue;
				for (int y = 0; y < height; ++y,imageLine += stride)
				{
					if (imageLine[3] > 0)
					{
						min = Math.Min(min, y);
						max = Math.Max(max, y);
					}
				}
				if (min <= max)
				{
					if (pointsHashSet.Add(min * width + x))
					{
						points.Add(.(x, min));
					}
					if (min != max)
					{
						if (pointsHashSet.Add(max * width + x))
						{
							points.Add(.(x, max));
						}
					}
				}
			}
			if (pixelCount > 0)
			{
				sprite.center = .((float)(centerX / pixelCount) / (float)width, ((float)height - (float)(centerY / pixelCount)) / (float)height);
				sprite.averageColor = .((float)(r / pixelCount), (float)(g / pixelCount), (float)(b / pixelCount), 1.0f);
			}
			if (points.Count == 0)
			{
				return;
			}
			let ooWidth = 1.0f / (double)(width - 1);
			let ooHeight = 1.0f / (double)(height - 1);
			for (int i = 0; i < points.Count; ++i)
			{
				points[i].x *= ooWidth;
				points[i].y = (height - 1 - points[i].y) * ooHeight;
			}
			// Compute convex hull
			var count = Chipmunk2D.Space.ConvexHullInplace(points.Count, &points[0], 0.0001);
			for (int i = 0; i < count; ++i)
			{
				var point = Vector2((float)points[i].x, (float)points[i].y);
				sprite.convexHull.Add(point.x);
				sprite.convexHull.Add(point.y);
			}
			sprite.moment = Chipmunk2D.Shape.AreaForPoly(&points[0], points.Count, 0.0);
		}


		bool BuildConvexHull(StringView fileName, SpriteAtlas atlas)
		{
			if (atlas.sprites.Count <= 1)
			{
				return true;
			}
			uint8[] binaryData;
			SystemUtils.ReadBinaryFile(fileName, out binaryData);

			var header = KTXHeader();
			Internal.MemCpy(&header, &binaryData[0], sizeof(KTXHeader));
			var offset = sizeof(KTXHeader) + header.keypairbytes + 4;
			let imageStart = &binaryData[(.)offset];
			let stride = header.pixelwidth * 4;
			for (var sprite in atlas.sprites)
			{
				let spriteStart = imageStart + (sprite.y * stride) + (sprite.x * 4);
				GenerateConvexHull(spriteStart, (.)sprite.width, (.)sprite.height, (.)stride, sprite);
			}
			delete binaryData;
			return true;
		}

		private bool ConvertSpriteAtlas(StringView path, StringView texBinaryPath, String jsonPath)
		{
			var spritePath = scope String();
			// Parse TXT
			spritePath.AppendF("{}.atlasbin", path);
			var atlas = scope SpriteAtlas();
			if (File.Exists(spritePath))
			{
				var binaryFile = scope FileStream();
				switch (binaryFile.Open(spritePath, .Read)) {
				case .Ok:
					break;
				case .Err:
					return false;
				}
				let bitmapCount = binaryFile.Read<uint16>().Value;
				atlas.sprites.Reserve(bitmapCount);
				for (var i = 0; i < bitmapCount; ++i)
				{
					var sprite = new Sprite();
					SystemUtils.ReadStrSized32(binaryFile, sprite.name);
					sprite.x = binaryFile.Read<uint16>().Value;
					sprite.y = binaryFile.Read<uint16>().Value;
					sprite.width = binaryFile.Read<uint16>().Value;
					sprite.height = binaryFile.Read<uint16>().Value;
					atlas.sprites.Add(sprite);
				}
			}
			BuildConvexHull(texBinaryPath, atlas);
			// Convert to json and save
			let jsonString = JSON_Beef.Serialization.JSONSerializer.Serialize<String>(atlas);
			File.WriteAllText(jsonPath, jsonString.Value);
			delete jsonString.Value;
			return true;
		}

		public override bool OnBuild(StringView path, StringView hash)
		{
#if RESOURCEBUILD
			var texAtlasPath = scope String()..AppendF("{}{}.json", ResourceManager.runtimeResourcesPath, hash);
			var texBinaryPath = scope String()..AppendF("{}{}.ktx", ResourceManager.runtimeResourcesPath, hash);
			var toolPath = scope String();
			toolPath.Set(ResourceManager.buildtimeBgfxToolsPath);
			toolPath.Append("texturecrelease");
			SystemUtils.NormalizePath(toolPath);
			var commandLine = scope String();
			commandLine.Clear();
			commandLine.AppendF("-f \"{0}\" -o \"{1}\" -t RGBA8 --linear", path, texBinaryPath);
			// Build terxture
			if (SystemUtils.ExecuteProcess(toolPath, commandLine) != 0)
			{
				var temp = scope String();
				temp.AppendF("{0} texture conversion failed!", path);
				if (SystemUtils.ShowMessageBoxOKCancel("Texture Conversion", temp) == 1)
				{
					System.Environment.Exit(1);
				}
			}
			ConvertSpriteAtlas(path, texBinaryPath, texAtlasPath);
#endif
			return true;
		}
	}
}
