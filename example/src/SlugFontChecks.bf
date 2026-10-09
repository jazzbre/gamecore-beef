using System;
using System.IO;
using System.Collections;
using GameCore;

namespace Example;

static class SlugFontChecks
{
	private const int TargetWidth = 768;
	private const int TargetHeight = 384;

	public static bool Run()
	{
		let font = ResourceManager.GetResource<SlugFontResource>("fonts/exo2-black");
		if (font == null || !font.HasFont)
		{
			Console.WriteLine("Exo 2 Slug font did not load");
			return false;
		}
		let data = font.Data;
		let builder = scope SlugFontResourceBuilder();
		let fontSource = scope $"{ResourceManager.buildtimeResourcesPath}fonts/Exo2-Black.ttf";
		if (builder.OnCheckBuild(fontSource, font.Hash))
		{
			Console.WriteLine("Font rebuilt unexpectedly: source {} converter {} output {}",
				SystemUtils.GetLatestTimestamp(fontSource), SystemUtils.GetLatestTimestamp(scope $"{ResourceManager.buildtimeToolsPath}slugconvert.exe"),
				SystemUtils.GetLatestTimestamp(scope $"{ResourceManager.runtimeResourcesPath}{font.Hash}.slugfont"));
			return false;
		}
		let widthAt32 = font.GetTextExtents("AV", 32).x;
		if (Math.Abs(font.GetTextExtents("AV", 64).x - widthAt32 * 2) > 0.001f ||
			font.GetTextExtents("AV", 32).x >= font.GetTextExtents("A V", 32).x ||
			Math.Abs(font.GetTextExtents("A\nV", 32).y - data.LineHeight * 64) > 0.001f ||
			font.GetTextExtents("AV\r", 32) != font.GetTextExtents("AV", 32) ||
			font.GetTextExtents("\t", 32).x <= 0 ||
			data.FindGlyphId('č') == data.FindGlyphId((char32)0x10FFFF))
		{
			Console.WriteLine("Slug layout failed: AV32 {} AV64 {} A V {} multiline {} line {} CR {} tab {} Unicode {} fallback {}",
				widthAt32, font.GetTextExtents("AV", 64).x, font.GetTextExtents("A V", 32).x,
				font.GetTextExtents("A\nV", 32).y, data.LineHeight * 64,
				font.GetTextExtents("AV\r", 32), font.GetTextExtents("A\tV", 32).x,
				data.FindGlyphId('č'), data.FindGlyphId((char32)0x10FFFF));
			return false;
		}
		let bytes = scope List<uint8>();
		if (File.ReadAll(scope $"{ResourceManager.runtimeResourcesPath}{font.Hash}.slugfont", bytes) case .Err)
		{
			return false;
		}
		let invalidData = scope SlugFontData();
		let copiedHash = "slug-font-check-copy";
		let copiedFontPath = scope $"{ResourceManager.runtimeResourcesPath}{copiedHash}.slugfont";
		defer File.Delete(copiedFontPath).IgnoreError();
		let prebuiltSource = scope $"{ResourceManager.runtimeResourcesPath}{font.Hash}.slugfont";
		if (!builder.OnBuild(prebuiltSource, copiedHash) || builder.OnCheckBuild(prebuiltSource, copiedHash))
		{
			Console.WriteLine("Prebuilt Slug font copy or timestamp check failed");
			return false;
		}
		bytes[bytes.Count - 1] ^= 1;
		if (invalidData.Read(.(bytes.Ptr, bytes.Count)) || invalidData.GlyphCount != 0 || invalidData.Error.IsEmpty)
		{
			Console.WriteLine("Slug checksum corruption was accepted");
			return false;
		}
		let invalidFontPath = scope $"{ResourceManager.runtimeResourcesPath}slug-font-check-invalid.slugfont";
		defer File.Delete(invalidFontPath).IgnoreError();
		{
			let stream = scope FileStream();
			if (stream.Create(invalidFontPath) case .Err || stream.TryWrite(Span<uint8>(bytes.Ptr, bytes.Count)) case .Err)
			{
				return false;
			}
		}
		if (builder.OnBuild(invalidFontPath, copiedHash))
		{
			Console.WriteLine("Builder accepted a corrupt prebuilt Slug font");
			return false;
		}
		let copiedBytes = scope List<uint8>();
		if (File.ReadAll(copiedFontPath, copiedBytes) case .Err || !invalidData.Read(.(copiedBytes.Ptr, copiedBytes.Count)))
		{
			Console.WriteLine("Failed prebuilt conversion replaced the previous valid output");
			return false;
		}
		Vector2 tabPen = .(1.0f, 0.0f);
		int previousTabGlyph = data.FindGlyphId('A');
		if (data.AdvanceCharacter('\t', ref tabPen, ref previousTabGlyph, let tabGlyph) || previousTabGlyph != -1 || tabPen.x <= 1)
		{
			return false;
		}
		if (invalidData.Read(.(bytes.Ptr, 287)))
		{
			return false;
		}
		let target = scope RenderTexture(TargetWidth, TargetHeight);
		let commands = RenderManager.AcquireCommandBuffer(target, "Slug font checks");
		commands.ClearColorBuffer = true;
		commands.ClearColor = default;
		commands.View = .Identity;
		commands.Projection = .Identity;
		commands.Viewport = .() { width = TargetWidth, height = TargetHeight };
		let renderer = RenderManager.FontRenderer;
		renderer.DrawText(commands, font, "Exo 2: AV čšž ČŠŽ", .(16, 40), 16, .White, shadowColor: .(0, 0, 0, 0));
		renderer.DrawText(commands, font, "Exo 2: AV čšž ČŠŽ", .(16, 100), 32, .White, shadowColor: .(0, 0, 0, 0));
		renderer.DrawText(commands, font, "AV čšž", .(16, 190), 64, .White, shadowColor: .(0, 0, 0, 0));
		renderer.DrawText(commands, font, "Tabs:\tAV\nNext line", .(16, 250), 24, .White, shadowColor: .(0, 0, 0, 0));
		renderer.DrawWorldText(commands, font, "World", .(0.5f, 0.5f, 0.5f), 32, .White, shadowColor: .(0, 0, 0, 0));
		if (!commands.Finish())
		{
			RenderManager.CancelCommandBuffer(commands);
			return false;
		}
		RenderManager.SubmitCommandBuffer(commands);
		if (!RenderManager.Frame())
		{
			return false;
		}
		let pixels = new uint8[TargetWidth * TargetHeight * 4];
		defer delete pixels;
		if (!RenderManager.ReadTexture(target.TextureHandle, pixels.Ptr, (uint32)pixels.Count))
		{
			return false;
		}
		int visiblePixels = 0;
		int translucentPixels = 0;
		int worldPixels = 0;
		for (int pixelIndex = 0; pixelIndex < TargetWidth * TargetHeight; pixelIndex++)
		{
			uint8 coverage = pixels[pixelIndex * 4];
			if (coverage != pixels[pixelIndex * 4 + 1] || coverage != pixels[pixelIndex * 4 + 2] || coverage != pixels[pixelIndex * 4 + 3])
			{
				Console.WriteLine("Slug premultiplied alpha check failed");
				return false;
			}
			if (coverage > 0)
			{
				visiblePixels++;
				if (coverage < 255)
				{
					translucentPixels++;
				}
				if (pixelIndex % TargetWidth >= 576 && pixelIndex / TargetWidth >= 240)
				{
					worldPixels++;
				}
			}
		}
		let capturePath = scope String();
		Environment.GetEnvironmentVariable("GAMECORE_SLUG_CAPTURE", capturePath).IgnoreError();
		if (!capturePath.IsEmpty)
		{
			let stream = scope FileStream();
			if (stream.Create(capturePath) case .Err || stream.TryWrite(Span<uint8>(pixels.Ptr, pixels.Count)) case .Err)
			{
				return false;
			}
		}
		if (visiblePixels < 1000 || translucentPixels < 100 || worldPixels < 100)
		{
			Console.WriteLine("Slug glyph coverage missing: visible {}, edge {}, world {}", visiblePixels, translucentPixels, worldPixels);
			return false;
		}
		if (File.Delete(copiedFontPath) case .Err || File.Delete(invalidFontPath) case .Err)
		{
			Console.WriteLine("Could not remove Slug font test files");
			return false;
		}
		Console.WriteLine("Slug font Unicode, sizes, layout, corruption, screen/world coverage, and premultiplied alpha checks passed");
		return true;
	}
}
