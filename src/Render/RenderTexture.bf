using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	class RenderTexture
	{
		public int Width { get; private set; }
		public int Height { get; private set; }

		public bgfx.TextureHandle TextureHandle { get; private set; } = .Null;
		public bgfx.TextureHandle DepthHandle { get; private set; } = .Null;
		public bgfx.FrameBufferHandle FrameBufferHandle { get; private set; } = .Null;

		public bgfx.TextureFormat ColorFormat { get; private set; }
		public bgfx.TextureFormat DepthFormat { get; private set; }

		public this(int width, int height, bgfx.TextureFormat colorFormat = .RGBA8, bgfx.TextureFormat depthFormat = .Count)
		{
			ColorFormat = colorFormat;
			DepthFormat = depthFormat;
			Resize(width, height);
		}

		public ~this()
		{
			Resize(0, 0);
		}

		public void Resize(int newWidth, int newHeight)
		{
			if (newWidth == Width && newHeight == Height)
			{
				return;
			}
			if (FrameBufferHandle.Valid)
			{
				bgfx.destroy_frame_buffer(FrameBufferHandle);
				TextureHandle = .Null;
				DepthHandle = .Null;
				FrameBufferHandle = .Null;
			}
			Width = newWidth;
			Height = newHeight;
			if (newWidth == 0 || newHeight == 0)
			{
				return;
			}
			TextureHandle = bgfx.create_texture_2d((uint16)Width, (uint16)Height, false, 1, ColorFormat, (uint64)(bgfx.TextureFlags.Rt | bgfx.TextureFlags.BlitDst), null);
			if (DepthFormat != .Count)
			{
				bgfx.TextureHandle[2] handles;
				handles[0] = TextureHandle;
				DepthHandle = bgfx.create_texture_2d((uint16)Width, (uint16)Height, false, 1, DepthFormat, (uint64)bgfx.TextureFlags.RtWriteOnly, null);
				handles[1] = DepthHandle;
				FrameBufferHandle = bgfx.create_frame_buffer_from_handles(2, &handles, true);
			} else
			{
				DepthHandle = .Null;
				bgfx.TextureHandle[1] handles;
				handles[0] = TextureHandle;
				FrameBufferHandle = bgfx.create_frame_buffer_from_handles(1, &handles, true);
			}
		}
	}
}