using System;
using System.IO;
using GameCore;
using SDL2;
using ImGui;
using NoGraphicsAPI;
using jazzutils;

namespace Example;

class Program
{
	static void RenderOverlay(CommandBuffer* commands, uint32x2 extent, TimelinePoint completion)
	{
		ImGui.NgaRenderFrame(commands, extent, completion);
	}

	private static void RecordTriangle(RenderCommandBuffer commands, Mesh mesh, Shader shader)
	{
		commands.Viewport = .() { width = 128, height = 128 };
		commands.ClearColorBuffer = true;
		commands.View = .Identity;
		commands.Projection = .Identity;
		mesh.Render(commands, .Identity, shader, null, .(1, 0, 0, 1), .Opaque);
		commands.Finish();
	}

	private static void RecordScreen(RenderCommandBuffer commands, Mesh mesh, Shader shader, RenderTexture target)
	{
		commands.ClearColorBuffer = true;
		commands.View = .Identity;
		commands.Projection = .Identity;
		var textures = scope GpuTexture[](target.TextureHandle);
		mesh.Render(commands, .Identity, shader, textures, .White, .Opaque);
		commands.Finish();
	}

	private static void RecordText(RenderCommandBuffer commands, GameCore.Font font, SpriteBatchRenderer batchRenderer, Shader shader)
	{
		var textTransform = Matrix4.CreateScale(2);
		textTransform.Translation = .(32, -48, 0);
		font.RenderText(batchRenderer, shader, commands, .Zero, textTransform, .White, "Valmore - GameCore NGA", .Black);
		commands.Finish();
	}

	private static int RunHeadlessChecks()
	{
		if (!RenderManager.InitializeDevice(null))
			return 1;
		defer RenderManager.ShutdownDevice();
		if (!JobSystem.Initialize(4))
			return 1;
		defer JobSystem.Finalize();
		var resourceDirectory = scope String();
		Directory.GetCurrentDirectory(resourceDirectory);
		ResourceManager.Initialize(resourceDirectory, "", 0, 0, true, scope $"{resourceDirectory}/../..");
		defer ResourceManager.Finalize();
		if (!RenderManager.Initialize())
			return 1;
		defer RenderManager.Finalize();
		return RenderChecks.Run() ? 0 : 1;
	}

	public static int Main(String[] arguments)
	{
		if (arguments.Count > 0 && arguments[0] == "--headless-smoke-test")
			return RunHeadlessChecks();
		bool smokeTest = arguments.Count > 0 && arguments[0] == "--smoke-test";
		if (SDL.Init(.Video | .Events) != 0)
			return 1;
		defer SDL.Quit();
		var window = SDL.CreateWindow("GameCore NGA DX12", .Centered, .Centered, 960, 640, .Shown | .Resizable);
		if (window == null)
			return 1;
		defer SDL.DestroyWindow(window);
		if (!RenderManager.InitializeDevice(ImGui.NgaGetNativeWindow(window)))
		{
			Console.WriteLine("NGA rendering failed");
			return 1;
		}
		defer RenderManager.ShutdownDevice();
		RenderManager.ProfilingEnabled = true;
		var context = ImGui.CreateContext();
		defer ImGui.DestroyContext(context);
		ImGui.GetIO().ConfigFlags |= .NavEnableKeyboard | .DockingEnable;
		ImGui.GetIO().IniFilename = null;

		if (!RenderManager.InitializeImGui(window))
			return 1;
		defer ImGui.NgaFinalize();

		if (!JobSystem.Initialize(4))
			return 1;
		defer JobSystem.Finalize();
		var resourceDirectory = scope String();
		Directory.GetCurrentDirectory(resourceDirectory);
		Console.WriteLine("Example resources: {}", resourceDirectory);
		ResourceManager.Initialize(resourceDirectory, "", 0, 0, true, scope $"{resourceDirectory}/../..");
		defer ResourceManager.Finalize();
		if (!RenderManager.Initialize())
			return 1;
		defer RenderManager.Finalize();
		var valmoreFont = ResourceManager.GetResource<GameCore.Font>("fonts/valmore");
		if (valmoreFont == null || valmoreFont.FontGlyphs.Count == 0 || valmoreFont.FontTexture?.Handle == null)
			return 1;
		var shader = ResourceManager.GetResource<Shader>("shaders/example");
		if (shader == null || shader.Programs.Count == 0)
			return 1;
		var mesh = scope Mesh();
		mesh.Initialize(3, 3);
		mesh.Vertices[0] = .(.(-0.8f, -0.8f), .(0, 0, 0, 0), 0xFFFFFFFF);
		mesh.Vertices[1] = .(.(0.8f, -0.8f), .(1, 0, 0, 0), 0xFFFFFFFF);
		mesh.Vertices[2] = .(.(0, 0.8f), .(0.5f, 1, 0, 0), 0xFFFFFFFF);
		mesh.Indices[0] = 0;
		mesh.Indices[1] = 1;
		mesh.Indices[2] = 2;
		mesh.Create();
		Format[2] targetFormats = .(.rgba8_unorm, .rgba16_float);
		var target = scope RenderTexture(128, 128, Span<Format>(&targetFormats[0], 2));
		var multipleTargetShader = ResourceManager.GetResource<Shader>("shaders/multiple_targets");
		if (multipleTargetShader == null || multipleTargetShader.Programs.Count == 0)
			return 1;
		var textBatchRenderer = scope SpriteBatchRenderer();
		var fontShader = RenderManager.GetShader(.Font);
		RenderCommandBuffer targetCommands = null;
		RenderCommandBuffer screenCommands = null;
		RenderCommandBuffer textCommands = null;
		var triangleRecordingJob = JobSystem.CreateJob(new [&] (startIndex, endIndex, workerIndex) => RecordTriangle(targetCommands, mesh, multipleTargetShader));
		var screenRecordingJob = JobSystem.CreateJob(new [&] (startIndex, endIndex, workerIndex) => RecordScreen(screenCommands, mesh, shader, target));
		var textRecordingJob = JobSystem.CreateJob(new [&] (startIndex, endIndex, workerIndex) => RecordText(textCommands, valmoreFont, textBatchRenderer, fontShader));
		var pixels = scope uint8[128 * 128 * 4];
		bool quitting = false;
		int frameCount = 0;
		while (!quitting)
		{
			SDL.Event event;
			while (SDL.PollEvent(out event) != 0)
			{
				ImGui.NgaProcessEvent(&event);
				if (event.type == .Quit)
					quitting = true;
			}
			if (quitting)
				break;
			ResourceManager.Update(false);
			ImGui.NgaNewFrame();
			ImGui.NewFrame();
			ImGui.DockSpaceOverViewport(flags: .PassthruCentralNode);
			ImGui.Begin("GameCore render target");
			ImGui.TextUnformatted("DX12, GameCore mesh, texture sampling, and shared ImGui heaps");
			if (RenderManager.HasGpuTiming)
			{
				ImGui.TextUnformatted(scope $"GPU frame {RenderManager.CompletedFrame}: {RenderManager.GpuMilliseconds} ms");
				for (int index = 0; index < RenderManager.CommandBufferTimingCount; ++index)
				{
					var timing = RenderManager.GetCommandBufferTiming(index);
					if (timing.HasGpuTiming)
						ImGui.TextUnformatted(scope $"{timing.Name}: {timing.GpuMilliseconds} ms");
				}
			}
			ImGui.Image(target.TextureHandle.ImageId, .(256, 256));
			ImGui.SameLine();
			ImGui.Image(target.GetColorTexture(1).ImageId, .(256, 256));
			ImGui.End();
			ImGui.Render();

			targetCommands = RenderManager.AcquireCommandBuffer(target, "Triangle target");
			screenCommands = RenderManager.AcquireSwapchainCommandBuffer("Screen");
			textCommands = RenderManager.AcquireSwapchainCommandBuffer("Text");
			JobSystem.AddJob(triangleRecordingJob, 1);
			JobSystem.AddJob(screenRecordingJob, 1);
			JobSystem.AddJob(textRecordingJob, 1);
			JobSystem.WaitJobs(triangleRecordingJob);
			JobSystem.WaitJobs(screenRecordingJob);
			JobSystem.WaitJobs(textRecordingJob);
			RenderManager.SubmitCommandBuffer(targetCommands);
			RenderManager.SubmitCommandBuffer(screenCommands);
			RenderManager.SubmitCommandBuffer(textCommands);
			if (!RenderManager.Frame( => RenderOverlay))
			{
				Console.WriteLine("NGA rendering failed");
				return 1;
			}
			if (smokeTest)
			{
				if (!RenderManager.ReadTexture(target.TextureHandle, pixels.Ptr, (.)pixels.Count))
					return 1;
				int center = (64 * 128 + 64) * 4;
				if (pixels[center] < 240 || pixels[center + 1] > 10 || pixels[center + 2] > 10)
				{
					Console.WriteLine("GPU readback failed: center pixel {}, {}, {}", pixels[center], pixels[center + 1], pixels[center + 2]);
					return 1;
				}
				if (frameCount == 2)
					SDL.SetWindowSize(window, 800, 600);
				if (++frameCount == 8)
					break;
			}
		}
		if (smokeTest && !RenderChecks.Run())
		{
			Console.WriteLine("Extended renderer checks failed");
			return 1;
		}
		Console.WriteLine("Rendered {} frames; GPU readback passed", frameCount);
		return 0;
	}
}
