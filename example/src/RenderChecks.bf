using System;
using GameCore;
using NoGraphicsAPI;

namespace Example;

static class RenderChecks
{
    [CRepr]
    struct LineVertex
    {
        public Vector3 Position;
        public uint32 Color;
    }

    [CRepr]
    struct SkinVertex
    {
        public Vector3 Position;
        public uint32 Joints;
        public Vector4 Weights;
    }

    static void SetTarget(RenderCommandBuffer commandBuffer, RenderTexture target, bool clearDepth = false)
    {
        var view = commandBuffer;
        if (view.Target != target)
            Runtime.FatalError("Unexpected command buffer target");
        view.View = .Identity;
        view.Projection = .Identity;
        view.Viewport = .() { width = target.Width, height = target.Height };
        view.ClearColorBuffer = true;
        view.ClearDepthBuffer = clearDepth;
    }

    static bool ReadColor(RenderTexture target, uint8[] pixels, int x, int y, int channel)
    {
        if (!RenderManager.ReadTexture(target.TextureHandle, pixels.Ptr, (.)pixels.Count))
            return false;
        int pixel = (y * target.Width + x) * 4;
        for (int index = 0; index < 3; ++index)
            if (index == channel ? pixels[pixel + index] < 240 : pixels[pixel + index] > 10)
                return false;
        return true;
    }

    public static bool Run()
    {
        var mesh = ResourceManager.GetResource<Shader>("shaders/mesh");
        var fullscreen = ResourceManager.GetResource<Shader>("shaders/fullscreen_aspect_texture");
        var debug = ResourceManager.GetResource<Shader>("shaders/debug_draw3d");
        var font = ResourceManager.GetResource<Shader>("shaders/font_sprite_texture");
        if (mesh == null || fullscreen == null || debug == null || font == null || mesh.Programs.Count < 2
            || fullscreen.Programs.Count == 0 || debug.Programs.Count == 0 || font.Programs.Count == 0) return false;

        var cache = scope PipelineCache(RenderManager.Device);
        var first = cache.Get(mesh.Programs[0], .rgba8_unorm, .undefined, .Opaque);
        if (first == null || cache.Get(mesh.Programs[0], .rgba8_unorm, .undefined, .Opaque) != first || cache.Count != 1)
            return false;
        var biased = RenderState.Opaque;
        biased.Rasterization.depth_bias_constant = 1;
        if (cache.Get(mesh.Programs[0], .rgba8_unorm, .undefined, .Alpha) == null
            || cache.Get(mesh.Programs[0], .rgba16_float, .undefined, .Opaque) == null
            || cache.Get(mesh.Programs[0], .rgba8_unorm, .d24_unorm_s8_uint, biased) == null || cache.Count != 4) return false;
        cache.Clear();
        if (cache.Count != 0)
            return false;

        var target = scope RenderTexture(128, 128, .rgba8_unorm, .d24_unorm_s8_uint);
        var sampled = scope RenderTexture(128, 128);
        var pixels = scope uint8[128 * 128 * 4];
        VertexLayout layout = .();
        layout.Begin();
        layout.Add(.Position, 3, .Float);
        layout.End();
        Vector3[3] positions = .(.(-0.8f, -0.8f, 0.2f), .(0.8f, -0.8f, 0.2f), .(0, 0.8f, 0.2f));
        var nearVertices = GpuBuffer.CreateVertices(&positions, sizeof(Vector3) * 3, layout);
        defer nearVertices.Dispose();
        for (var position in ref positions)
            position.z = 0.8f;
        var farVertices = GpuBuffer.CreateVertices(&positions, sizeof(Vector3) * 3, layout);
        defer farVertices.Dispose();
        var commands1 = RenderManager.AcquireCommandBuffer(target, "Depth");
        var commands2 = RenderManager.AcquireCommandBuffer(sampled, "Sampling");
        SetTarget(commands1, target, true);
        SetTarget(commands2, sampled);
        RenderManager.RenderFullScreenTextureAspect(commands2, target.TextureHandle, fullscreen, .Opaque);
        RenderManager.Draw(commands1, mesh, 0, nearVertices, default, 3, 0, .Identity, .(1,0,0,1), .Zero, state: .DepthTested);
        RenderManager.Draw(commands1, mesh, 0, farVertices, default, 3, 0, .Identity, .(0,0,1,1), .Zero, state: .DepthTested);
        commands1.Finish();
        RenderManager.SubmitCommandBuffer(commands1);
        commands2.Finish();
        RenderManager.SubmitCommandBuffer(commands2);
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 64, 64, 0))
            return false;

        layout.Begin();
        layout.Add(.Position, 3, .Float);
        layout.Add(.TexCoord0, 4, .Uint8, true);
        layout.End();
        LineVertex[2] line = .(.() { Position = .(-0.75f,0,0.5f), Color = 0xFF00FF00 }, .() { Position = .(0.75f,0,0.5f), Color = 0xFF00FF00 });
        var commands3 = RenderManager.AcquireCommandBuffer(sampled);
        var lineVertices = commands3.TransientVertices(&line, sizeof(LineVertex) * 2, layout);
        SetTarget(commands3, sampled);
        RenderManager.Draw(commands3, debug, 0, lineVertices, default, 2, 0, .Identity, .One, .Zero, state: .Opaque, lines: true);
        commands3.Finish();
        RenderManager.SubmitCommandBuffer(commands3);
        if (!RenderManager.Frame())
            return false;
        if (!ReadColor(sampled, pixels, 64, 64, 1) && !ReadColor(sampled, pixels, 64, 63, 1))
            return false;

        layout.Begin();
        layout.Add(.Position, 3, .Float);
        layout.Add(.Indices, 4, .Uint8, true);
        layout.Add(.Weight, 4, .Float);
        layout.End();
        SkinVertex[3] skin;
        for (int index = 0; index < 3; ++index)
            skin[index] = .() { Position = positions[index], Weights = .(1,0,0,0) };
        var commands4 = RenderManager.AcquireCommandBuffer(sampled);
        var skinVertices = commands4.TransientVertices(&skin, sizeof(SkinVertex) * 3, layout);
        Vector4[3] joints = .(.(1,0,0,0), .(0,1,0,0), .(0,0,1,0));
        SetTarget(commands4, sampled);
        RenderManager.Draw(commands4, mesh, 1, skinVertices, default, 3, 0, .Identity, .(0,0,1,1), .Zero, state: .Opaque, instances: &joints, instanceCount: 3);
        commands4.Finish();
        RenderManager.SubmitCommandBuffer(commands4);
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 64, 64, 2))
            return false;

        layout.Begin();
        layout.Add(.Position, 3, .Float);
        layout.End();
        Vector3[6] quad = .(.(0,0,0), .(1,0,0), .(1,1,0), .(0,0,0), .(1,1,0), .(0,1,0));
        var commands5 = RenderManager.AcquireCommandBuffer(sampled);
        var spriteVertices = commands5.TransientVertices(&quad, sizeof(Vector3) * 6, layout);
        Vector4[4] instances = .(.(1,0,0,32), .(0,-1,0,-32), .(0,0,1,1), .(0,0,1,1));
        SetTarget(commands5, sampled);
        RenderManager.Draw(commands5, font, 0, spriteVertices, default, 6, 0, .Identity, .One, .Zero, state: .Opaque,
            instances: &instances, instanceCount: 4, textureScale: .(32,32,0,0));
        commands5.Finish();
        RenderManager.SubmitCommandBuffer(commands5);
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 48, 48, 2))
            return false;
        var commands6 = RenderManager.AcquireCommandBuffer(sampled);
        SetTarget(commands6, sampled);
        commands6.ClearColor = .() { z = 1, w = 1 };
        RenderManager.Draw(commands6, mesh, 0, nearVertices, default, 3, 0, .Identity, .(1,0,0,0.5f), .Zero, state: .Alpha);
        commands6.Finish();
        RenderManager.SubmitCommandBuffer(commands6);
        if (!RenderManager.Frame() || !RenderManager.ReadTexture(sampled.TextureHandle, pixels.Ptr, (.)pixels.Count))
            return false;
        int center = (64 * 128 + 64) * 4;
        if (pixels[center] < 126 || pixels[center] > 129 || pixels[center + 2] < 126 || pixels[center + 2] > 129)
            return false;
        sampled.Resize(96, 80);
        var commands7 = RenderManager.AcquireCommandBuffer(sampled);
        SetTarget(commands7, sampled);
        RenderManager.Draw(commands7, mesh, 0, nearVertices, default, 3, 0, .Identity, .(1,0,0,1), .Zero, state: .Opaque);
        commands7.Finish();
        RenderManager.SubmitCommandBuffer(commands7);
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 48, 40, 0))
            return false;

        if (!CheckCommandBufferRecycling(mesh, nearVertices) || !CheckValmoreFont()
            || !SynchronizationChecks.Run(mesh, nearVertices) || !MultipleTargetChecks.Run(nearVertices, farVertices, fullscreen))
            return false;
        Console.WriteLine("Pipeline cache, command buffer ordering, depth, sampling, lines, skinning, sprites, blending, resize, and Valmore font checks passed");
        return true;
    }

    static bool CheckCommandBufferRecycling(Shader shader, GpuBuffer vertices)
    {
        RenderManager.WaitForIdle();
        RenderManager.ProfilingEnabled = true;
        defer
        {
            RenderManager.WaitForIdle();
            RenderManager.ProfilingEnabled = false;
        }
        var target = scope RenderTexture(32, 32);
        var buffers = scope RenderCommandBuffer[RenderManager.FramesInFlight];
        var readbacks = scope TextureReadback[RenderManager.FramesInFlight];
        defer
        {
            for (var readback in readbacks)
                delete readback;
        }
        var pixels = scope uint8[32 * 32 * 4];
        for (int frameIndex = 0; frameIndex < RenderManager.FramesInFlight; ++frameIndex)
        {
            var commands = RenderManager.AcquireCommandBuffer(target, "Recycling check");
            for (int previous = 0; previous < frameIndex; ++previous)
                if (commands == buffers[previous])
                    return false;
            buffers[frameIndex] = commands;
            SetTarget(commands, target);
            Vector4 color = frameIndex == 0 ? .(1,0,0,1) : frameIndex == 1 ? .(0,1,0,1) : .(0,0,1,1);
            RenderManager.Draw(commands, shader, 0, vertices, default, 3, 0, .Identity, color, .Zero, state: .Opaque);
            readbacks[frameIndex] = new .(commands, target.TextureHandle);
            commands.Finish();
            RenderManager.SubmitCommandBuffer(commands);
            if (!RenderManager.Frame() || commands.Status != .InFlight || readbacks[frameIndex].Ready)
                return false;
        }
        int bufferCount = RenderManager.CommandBufferCount;
        var recycled = RenderManager.AcquireCommandBuffer();
        if (recycled != buffers[0] || !readbacks[0].Ready || recycled.Target != null
            || recycled.ClearColorBuffer || recycled.HasCommands) return false;
        var cancelledReadback = scope TextureReadback(recycled, target.TextureHandle);
        RenderManager.CancelCommandBuffer(recycled);
        if (!cancelledReadback.Cancelled || cancelledReadback.Ready)
            return false;
        for (int frameIndex = 0; frameIndex < 9; ++frameIndex)
        {
            var commands = RenderManager.AcquireCommandBuffer(target);
            SetTarget(commands, target);
            RenderManager.Draw(commands, shader, 0, vertices, default, 3, 0, .Identity, .One, .Zero, state: .Opaque);
            commands.Finish();
            RenderManager.SubmitCommandBuffer(commands);
            if (!RenderManager.Frame())
                return false;
        }
        RenderManager.WaitForIdle();
        if (RenderManager.CommandBufferCount != bufferCount || cancelledReadback.Ready
            || RenderManager.DrawCount != 1 || RenderManager.GpuMilliseconds < 0) return false;
        for (int frameIndex = 0; frameIndex < readbacks.Count; ++frameIndex)
        {
            if (!readbacks[frameIndex].CopyTo(.(pixels.Ptr, pixels.Count)))
                return false;
            for (int channel = 0; channel < 3; ++channel)
            {
                uint8 value = pixels[(16 * 32 + 16) * 4 + channel];
                if (channel == frameIndex ? value < 240 : value > 10)
                    return false;
            }
        }
        Console.WriteLine("Three frames in flight, fence recycling, upload snapshots, cancellation, readback, and bounded pool checks passed");
        return true;
    }

    static bool CheckValmoreFont()
    {
        var font = ResourceManager.GetResource<GameCore.Font>("fonts/valmore");
        if (font == null || font.FontTexture?.Handle == null)
            return false;
        var target = scope RenderTexture(128, 64);
        var commands8 = RenderManager.AcquireCommandBuffer(target);
        SetTarget(commands8, target);
        var transform = Matrix4.CreateTranslation(8, -32, 0);
        font.RenderText(RenderManager.batchRenderer, RenderManager.GetShader(.Font), commands8, .Zero,
            transform, .(0, 1, 0, 1), "Valmore", .(0, 0, 0, 0));
        commands8.Finish();
        RenderManager.SubmitCommandBuffer(commands8);
        if (!RenderManager.Frame())
            return false;
        var renderedPixels = scope uint8[128 * 64 * 4];
        var atlasPixels = scope uint8[font.FontTexture.Width * font.FontTexture.Height * 4];
        if (!RenderManager.ReadTexture(target.TextureHandle, renderedPixels.Ptr, (.)renderedPixels.Count)
            || !RenderManager.ReadTexture(font.FontTexture.Handle, atlasPixels.Ptr, (.)atlasPixels.Count)) return false;
        var expectedCoverage = scope uint8[128 * 64];
        int characterPosition = 8;
        int visiblePixels = 0;
        for (var character in (StringView)"Valmore")
        {
            if (!font.FontGlyphs.TryGetValue((char32)character, let glyph))
                return false;
            for (int y = 0; y < glyph.height; ++y)
                for (int x = 0; x < glyph.width; ++x)
            {
                int destination = (32 - font.FontData.baseHeight + glyph.yOffset + y) * 128 + characterPosition + glyph.xOffset + x;
                int source = ((glyph.y + y) * font.FontTexture.Width + glyph.x + x) * 4;
                expectedCoverage[destination] = atlasPixels[source + 3];
            }
            characterPosition += glyph.xAdvance;
        }
        for (int index = 0; index < expectedCoverage.Count; ++index)
        {
            if (expectedCoverage[index] > 0)
                ++visiblePixels;
            if (Math.Abs((int)renderedPixels[index * 4 + 1] - expectedCoverage[index]) > 1
                || renderedPixels[index * 4] != 0 || renderedPixels[index * 4 + 2] != 0)
            {
                Console.WriteLine("Valmore font pixel mismatch at {}, {}", index % 128, index / 128);
                return false;
            }
        }
        return visiblePixels > 100;
    }
}
