using System;
using GameCore;
using NoGraphicsAPI;

namespace Example;

static class MultipleTargetChecks
{
    public static bool Run(GpuBuffer nearVertices, GpuBuffer farVertices, Shader fullscreenShader)
    {
        var shader = ResourceManager.GetResource<Shader>("shaders/multiple_targets");
        if (shader == null || shader.Programs.Count == 0)
            return false;
        Format[2] formats = .(.rgba8_unorm, .rgba16_float);
        var target = scope RenderTexture(32, 32, Span<Format>(&formats[0], 2), .d24_unorm_s8_uint);
        var sampled = scope RenderTexture(32, 32);
        var cache = scope PipelineCache(RenderManager.Device);
        var firstPipeline = cache.Get(shader.Programs[0], Span<Format>(&formats[0], 2), target.DepthFormat, .Opaque);
        if (firstPipeline == null || cache.Get(shader.Programs[0], Span<Format>(&formats[0], 2), target.DepthFormat, .Opaque) != firstPipeline)
            return false;
        formats = .(.rgba16_float, .rgba8_unorm);
        if (cache.Get(shader.Programs[0], Span<Format>(&formats[0], 2), target.DepthFormat, .Opaque) == null || cache.Count != 2)
            return false;
        formats = .(.rgba8_unorm, .rgba16_float);
        if (cache.Get(shader.Programs[0], Span<Format>(&formats[0], 2), target.DepthFormat, .Alpha) == null || cache.Count != 3)
            return false;
        Format[3] threeFormats = .(.rgba8_unorm, .rgba16_float, .rgba8_unorm);
        if (cache.Get(shader.Programs[0], Span<Format>(&threeFormats[0], 3), target.DepthFormat, .Opaque) == null || cache.Count != 4)
            return false;
        for (int iteration = 0; iteration < 2; ++iteration)
        {
            if (iteration == 1)
            {
                target.Resize(48, 48);
                sampled.Resize(48, 48);
            }
            var consumer = RenderManager.AcquireCommandBuffer(sampled, "Sample second MRT attachment");
            consumer.ClearColorBuffer = true;
            RenderManager.RenderFullScreenTextureAspect(consumer, target.GetColorTexture(1), fullscreenShader);
            consumer.Finish();
            var producer = RenderManager.AcquireCommandBuffer(target, "Multiple render targets");
            producer.ClearColorBuffer = true;
            producer.ClearDepthBuffer = true;
            RenderManager.Draw(producer, shader, 0, nearVertices, default, 3, 0, .Identity, .(1, 0, 0, 1), .Zero, state: .DepthTested);
            var firstReadback = scope TextureReadback(producer, target.GetColorTexture(0));
            RenderManager.Draw(producer, shader, 0, farVertices, default, 3, 0, .Identity, .(0, 0, 1, 1), .Zero, state: .DepthTested);
            producer.Finish();
            RenderManager.SubmitCommandBuffer(producer);
            RenderManager.SubmitCommandBuffer(consumer);
            if (!RenderManager.Frame())
                return false;
            RenderManager.WaitForIdle();
            var pixels = scope uint8[target.Width * target.Height * 4];
            int center = (target.Height / 2 * target.Width + target.Width / 2) * 4;
            if (!firstReadback.CopyTo(.(pixels.Ptr, pixels.Count)) || pixels[center] != 255 || pixels[center + 1] != 0)
                return false;
            if (!RenderManager.ReadTexture(target.TextureHandle, pixels.Ptr, (.)pixels.Count)
                || pixels[center] != 255 || pixels[center + 2] != 0 || pixels[0] != 0)
                return false;
            if (!RenderManager.ReadTexture(sampled.TextureHandle, pixels.Ptr, (.)pixels.Count)
                || pixels[center] != 0 || pixels[center + 1] != 255 || pixels[center + 2] != 0 || pixels[1] != 0)
                return false;
        }
        Console.WriteLine("MRT: mixed formats, pipeline keys, shared depth, pass reopening, second-attachment sampling, and resize passed");
        return true;
    }
}
