using System;
using System.IO;

namespace Dedkeni
{
	static class ImageUtils
	{
		[CRepr]
		struct TGAHeader
		{
			public uint8 idlength = 0;
			public uint8 colourmaptype = 0;
			public uint8 datatypecode = 2;
			public uint8 colourmaporiginLo = 0;
			public uint8 colourmaporiginHi = 0;
			public uint8 colourmaplengthLo = 0;
			public uint8 colourmaplengthHi = 0;
			public uint8 colourmapdepth = 0;
			public uint8 x_originLo = 0;
			public uint8 x_originHi = 0;
			public uint8 y_originLo = 0;
			public uint8 y_originHi = 0;
			public uint8 widthLo = 0;
			public uint8 widthHi = 0;
			public uint8 heightLo = 0;
			public uint8 heightHi = 0;
			public uint8 bitsperpixel = 32;
			public uint8 imagedescriptor = 0x28;
		};

		public static bool SaveTGA(StringView fileName, int width, int height, int stride, uint8* data)
		{
			var header = TGAHeader();
			var file = scope FileStream();
			switch (file.Create(fileName, .Write)) {
			case .Ok:
				break;
			case .Err:
				return false;
			}
			header.widthLo = (uint8)(width & 255);
			header.widthHi = (uint8)((width >> 8) & 255);
			header.heightLo = (uint8)(height & 255);
			header.heightHi = (uint8)((height >> 8) & 255);
			file.Write(header);
			for (int y = 0; y < height; ++y)
			{
				file.TryWrite(Span<uint8>(data + stride * y, width * 4));
			}
			file.Close();

			return true;
		}
	}
}
