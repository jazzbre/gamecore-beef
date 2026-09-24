using System;
using GameCore;
using NoGraphicsAPI;

namespace Example;

static class RenderChecks
{
    [CRepr]
    struct LineVertex { public Vector3 Position; public uint32 Color; }
    [CRepr]
    struct SkinVertex { public Vector3 Position; public uint32 Joints; public Vector4 Weights; }

    static void SetTarget(uint16 viewId, RenderTexture target, bool clearDepth = false)
    {
        var view = RenderManager.GetView(viewId);
        view.Target = target;
        view.View = .Identity; view.Projection = .Identity;
        view.Viewport = .() { width = target.Width, height = target.Height };
        view.ClearColorBuffer = true; view.ClearDepthBuffer = clearDepth;
    }
    static bool ReadColor(RenderTexture target, uint8[] pixels, int x, int y, int channel)
    {
        if (!RenderManager.ReadTexture(target.TextureHandle, pixels.Ptr, (.)pixels.Count)) return false;
        int pixel = (y * target.Width + x) * 4;
        for (int index = 0; index < 3; ++index)
            if (index == channel ? pixels[pixel + index] < 240 : pixels[pixel + index] > 10) return false;
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
        if (first == null || cache.Get(mesh.Programs[0], .rgba8_unorm, .undefined, .Opaque) != first || cache.Count != 1) return false;
        var biased = RenderState.Opaque; biased.Rasterization.depth_bias_constant = 1;
        if (cache.Get(mesh.Programs[0], .rgba8_unorm, .undefined, .Alpha) == null
            || cache.Get(mesh.Programs[0], .rgba16_float, .undefined, .Opaque) == null
            || cache.Get(mesh.Programs[0], .rgba8_unorm, .d24_unorm_s8_uint, biased) == null || cache.Count != 4) return false;
        cache.Clear(); if (cache.Count != 0) return false;

        var target = scope RenderTexture(128, 128, .rgba8_unorm, .d24_unorm_s8_uint);
        var sampled = scope RenderTexture(128, 128);
        var pixels = scope uint8[128 * 128 * 4];
        VertexLayout layout = .(); layout.Begin(); layout.Add(.Position, 3, .Float); layout.End();
        Vector3[3] positions = .(.(-0.8f, -0.8f, 0.2f), .(0.8f, -0.8f, 0.2f), .(0, 0.8f, 0.2f));
        var nearVertices = GpuBuffer.CreateVertices(&positions, sizeof(Vector3) * 3, layout);
        defer nearVertices.Dispose();
        for (var position in ref positions) position.z = 0.8f;
        var farVertices = GpuBuffer.CreateVertices(&positions, sizeof(Vector3) * 3, layout);
        defer farVertices.Dispose();
        SetTarget(1, target, true); SetTarget(2, sampled);
        RenderManager.RenderFullScreenTextureAspect(2, target.TextureHandle, fullscreen, .Opaque);
        RenderManager.Draw(1, mesh, 0, nearVertices, default, 3, 0, .Identity, .(1,0,0,1), .Zero, state: .DepthTested);
        RenderManager.Draw(1, mesh, 0, farVertices, default, 3, 0, .Identity, .(0,0,1,1), .Zero, state: .DepthTested);
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 64, 64, 0)) return false;

        layout.Begin(); layout.Add(.Position, 3, .Float); layout.Add(.TexCoord0, 4, .Uint8, true); layout.End();
        LineVertex[2] line = .(.() { Position = .(-0.75f,0,0.5f), Color = 0xFF00FF00 }, .() { Position = .(0.75f,0,0.5f), Color = 0xFF00FF00 });
        var lineVertices = RenderManager.Context.TransientVertices(&line, sizeof(LineVertex) * 2, layout);
        SetTarget(3, sampled);
        RenderManager.Draw(3, debug, 0, lineVertices, default, 2, 0, .Identity, .One, .Zero, state: .Opaque, lines: true);
        if (!RenderManager.Frame()) return false;
        if (!ReadColor(sampled, pixels, 64, 64, 1) && !ReadColor(sampled, pixels, 64, 63, 1)) return false;

        layout.Begin(); layout.Add(.Position, 3, .Float); layout.Add(.Indices, 4, .Uint8, true); layout.Add(.Weight, 4, .Float); layout.End();
        SkinVertex[3] skin;
        for (int index = 0; index < 3; ++index) skin[index] = .() { Position = positions[index], Weights = .(1,0,0,0) };
        var skinVertices = RenderManager.Context.TransientVertices(&skin, sizeof(SkinVertex) * 3, layout);
        Vector4[3] joints = .(.(1,0,0,0), .(0,1,0,0), .(0,0,1,0));
        SetTarget(4, sampled);
        RenderManager.Draw(4, mesh, 1, skinVertices, default, 3, 0, .Identity, .(0,0,1,1), .Zero, state: .Opaque, instances: &joints, instanceCount: 3);
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 64, 64, 2)) return false;

        layout.Begin(); layout.Add(.Position, 3, .Float); layout.End();
        Vector3[6] quad = .(.(0,0,0), .(1,0,0), .(1,1,0), .(0,0,0), .(1,1,0), .(0,1,0));
        var spriteVertices = RenderManager.Context.TransientVertices(&quad, sizeof(Vector3) * 6, layout);
        Vector4[4] instances = .(.(1,0,0,32), .(0,-1,0,-32), .(0,0,1,1), .(0,0,1,1));
        SetTarget(5, sampled);
        RenderManager.Draw(5, font, 0, spriteVertices, default, 6, 0, .Identity, .One, .Zero, state: .Opaque,
            instances: &instances, instanceCount: 4, textureScale: .(32,32,0,0));
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 48, 48, 2)) return false;
        SetTarget(6, sampled);
        RenderManager.GetView(6).ClearColor = .() { z = 1, w = 1 };
        RenderManager.Draw(6, mesh, 0, nearVertices, default, 3, 0, .Identity, .(1,0,0,0.5f), .Zero, state: .Alpha);
        if (!RenderManager.Frame() || !RenderManager.ReadTexture(sampled.TextureHandle, pixels.Ptr, (.)pixels.Count)) return false;
        int center = (64 * 128 + 64) * 4;
        if (pixels[center] < 126 || pixels[center] > 129 || pixels[center + 2] < 126 || pixels[center + 2] > 129) return false;
        sampled.Resize(96, 80);
        SetTarget(7, sampled);
        RenderManager.Draw(7, mesh, 0, nearVertices, default, 3, 0, .Identity, .(1,0,0,1), .Zero, state: .Opaque);
        if (!RenderManager.Frame() || !ReadColor(sampled, pixels, 48, 40, 0)) return false;

        if (!CheckValmoreFont()) return false;
        Console.WriteLine("Pipeline cache, view ordering, depth, sampling, lines, skinning, sprites, blending, resize, and Valmore font checks passed");
        return true;
    }

    static bool CheckValmoreFont()
    {
        var font = ResourceManager.GetResource<GameCore.Font>("fonts/valmore");
        if (font == null || font.FontTexture?.Handle == null) return false;
        var target = scope RenderTexture(128, 64);
        SetTarget(8, target);
        var transform = Matrix4.CreateTranslation(8, -32, 0);
        font.RenderText(RenderManager.batchRenderer, RenderManager.GetShader(.Font), 8, .Zero,
            transform, .(0, 1, 0, 1), "Valmore", .(0, 0, 0, 0));
        if (!RenderManager.Frame()) return false;
        var renderedPixels = scope uint8[128 * 64 * 4];
        var atlasPixels = scope uint8[font.FontTexture.Width * font.FontTexture.Height * 4];
        if (!RenderManager.ReadTexture(target.TextureHandle, renderedPixels.Ptr, (.)renderedPixels.Count)
            || !RenderManager.ReadTexture(font.FontTexture.Handle, atlasPixels.Ptr, (.)atlasPixels.Count)) return false;
        var expectedCoverage = scope uint8[128 * 64];
        int characterPosition = 8;
        int visiblePixels = 0;
        for (var character in (StringView)"Valmore")
        {
            if (!font.FontGlyphs.TryGetValue((char32)character, let glyph)) return false;
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
            if (expectedCoverage[index] > 0) ++visiblePixels;
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
