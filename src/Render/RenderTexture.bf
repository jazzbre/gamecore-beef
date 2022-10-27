using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	class RenderTexture
	{
		public int Width { get; private set; }
		public int Height { get; private set; }

		public bgfx.TextureHandle TextureHandle { get; private set; }
		public bgfx.TextureHandle DepthHandle { get; private set; }
		public bgfx.FrameBufferHandle FrameBufferHandle { get; private set; }

		public this(int width, int height, bgfx.TextureFormat colorFormat = .RGBA8, bgfx.TextureFormat depthFormat = .Count)
		{
			Width = width;
			Height = height;
			TextureHandle = bgfx.create_texture_2d((uint16)Width, (uint16)Height, false, 1, colorFormat, (uint64)(bgfx.TextureFlags.Rt | bgfx.TextureFlags.BlitDst), null);
			if (depthFormat != .Count)
			{
				bgfx.TextureHandle[2] handles;
				handles[0] = TextureHandle;
				DepthHandle = bgfx.create_texture_2d((uint16)Width, (uint16)Height, false, 1, depthFormat, (uint64)bgfx.TextureFlags.RtWriteOnly, null);
				handles[1] = DepthHandle;
				FrameBufferHandle = bgfx.create_frame_buffer_from_handles(2, &handles, true);
			} else
			{
				DepthHandle = .() { idx = uint16.MaxValue };
				bgfx.TextureHandle[1] handles;
				handles[0] = TextureHandle;
				FrameBufferHandle = bgfx.create_frame_buffer_from_handles(1, &handles, true);
			}
		}

		public ~this()
		{
			bgfx.destroy_texture(TextureHandle);
			bgfx.destroy_frame_buffer(FrameBufferHandle);
		}
	}
}