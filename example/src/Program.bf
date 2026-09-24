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

    public static int Main(String[] arguments)
    {
        bool smokeTest = arguments.Count > 0 && arguments[0] == "--smoke-test";
        if (SDL.Init(.Video | .Events) != 0) return 1;
        defer SDL.Quit();
        var window = SDL.CreateWindow("GameCore NGA DX12", .Centered, .Centered, 960, 640, .Shown | .Resizable);
        if (window == null) return 1;
        defer SDL.DestroyWindow(window);
        if (!RenderManager.InitializeDevice(ImGui.NgaGetNativeWindow(window)))
        {
            Console.WriteLine("NGA rendering failed");
            return 1;
        }
        defer RenderManager.ShutdownDevice();
        var context = ImGui.CreateContext();
        defer ImGui.DestroyContext(context);
        ImGui.GetIO().IniFilename = null;
        if (!RenderManager.InitializeImGui(window)) return 1;
        defer ImGui.NgaFinalize();

        if (!JobSystem.Initialize(2)) return 1;
        defer JobSystem.Finalize();
        var resourceDirectory = scope String();
        Directory.GetCurrentDirectory(resourceDirectory);
        if (Directory.Exists(scope $"{resourceDirectory}/example/buildtime/resources"))
            resourceDirectory.Append("/example");
        else if (!Directory.Exists(scope $"{resourceDirectory}/buildtime/resources")
            && !Directory.Exists(scope $"{resourceDirectory}/runtime/resources"))
        {
            var executablePath = scope String();
            Environment.GetExecutableFilePath(executablePath);
            var executableDirectory = scope String();
            Path.GetDirectoryPath(executablePath, executableDirectory);
            Path.GetFullPath(scope $"{executableDirectory}/../../../example", resourceDirectory..Clear());
        }
        Console.WriteLine("Example resources: {}", resourceDirectory);
        ResourceManager.Initialize(resourceDirectory, "", 0, 0, true, scope $"{resourceDirectory}/../..");
        defer ResourceManager.Finalize();
        if (!RenderManager.Initialize()) return 1;
        defer RenderManager.Finalize();
        var valmoreFont = ResourceManager.GetResource<GameCore.Font>("fonts/valmore");
        if (valmoreFont == null || valmoreFont.FontGlyphs.Count == 0 || valmoreFont.FontTexture?.Handle == null) return 1;
        var shader = ResourceManager.GetResource<Shader>("shaders/example");
        if (shader == null || shader.Programs.Count == 0) return 1;
        var mesh = scope Mesh();
        mesh.Initialize(3, 3);
        mesh.Vertices[0] = .(.(-0.8f, -0.8f), .(0, 0, 0, 0), 0xFFFFFFFF);
        mesh.Vertices[1] = .(.(0.8f, -0.8f), .(1, 0, 0, 0), 0xFFFFFFFF);
        mesh.Vertices[2] = .(.(0, 0.8f), .(0.5f, 1, 0, 0), 0xFFFFFFFF);
        mesh.Indices[0] = 0; mesh.Indices[1] = 1; mesh.Indices[2] = 2;
        mesh.Create();
        var target = scope RenderTexture(128, 128);
        var identity = Matrix4.Identity;
        var pixels = scope uint8[128 * 128 * 4];
        bool quitting = false;
        int frameCount = 0;
        while (!quitting)
        {
            SDL.Event event;
            while (SDL.PollEvent(out event) != 0)
            {
                ImGui.NgaProcessEvent(&event);
                if (event.type == .Quit) quitting = true;
            }
            if (quitting) break;
            ResourceManager.Update(false);
            ImGui.NgaNewFrame(); ImGui.NewFrame();
            ImGui.Begin("GameCore render target");
            ImGui.TextUnformatted("DX12, GameCore mesh, texture sampling, and shared ImGui heaps");
            ImGui.Image(target.TextureHandle.ImageId, .(256, 256));
            ImGui.End(); ImGui.Render();

            RenderManager.GetView(20).Viewport = .() { x = 0, y = 0, width = 128, height = 128 };
            RenderManager.GetView(20).Target = target;
            RenderManager.GetView(20).ClearColorBuffer = true;
            RenderManager.GetView(20).View = identity; RenderManager.GetView(20).Projection = identity;
            RenderManager.GetView(30).Viewport = .() { x = 0, y = 0, width = 0, height = 0 };
            RenderManager.GetView(30).ClearColorBuffer = true;
            RenderManager.GetView(30).View = identity; RenderManager.GetView(30).Projection = identity;
            var textures = scope GpuTexture[](target.TextureHandle);
            mesh.Render(30, identity, shader, textures, .White, .Opaque);
            mesh.Render(20, identity, shader, null, .(1, 0, 0, 1), .Opaque);
            var textView = RenderManager.GetView(40);
            textView.Viewport = .() { width = 0, height = 0 };
            textView.ClearColorBuffer = false;
            var textTransform = Matrix4.CreateScale(2);
            textTransform.Translation = .(32, -48, 0);
            valmoreFont.RenderText(RenderManager.batchRenderer, RenderManager.GetShader(.Font), 40,
                .Zero, textTransform, .White, "Valmore - GameCore NGA", .Black);
            if (!RenderManager.Frame(=> RenderOverlay))
            {
                Console.WriteLine("NGA rendering failed");
                return 1;
            }
            if (smokeTest)
            {
                if (!RenderManager.ReadTexture(target.TextureHandle, pixels.Ptr, (.)pixels.Count)) return 1;
                int center = (64 * 128 + 64) * 4;
                if (pixels[center] < 240 || pixels[center + 1] > 10 || pixels[center + 2] > 10)
                {
                    Console.WriteLine("GPU readback failed: center pixel {}, {}, {}", pixels[center], pixels[center + 1], pixels[center + 2]);
                    return 1;
                }
                if (frameCount == 2) SDL.SetWindowSize(window, 800, 600);
                if (++frameCount == 8) break;
            }
        }
        if (smokeTest && !RenderChecks.Run()) { Console.WriteLine("Extended renderer checks failed"); return 1; }
        Console.WriteLine("Rendered {} frames; GPU readback passed", frameCount);
        return 0;
    }
}
