using System;
using GameCore;
using NoGraphicsAPI;

namespace Example;

static class SynchronizationChecks
{
    public static bool Run(Shader meshShader, GpuBuffer vertices)
    {
        if (!CheckUploadBatching() || !CheckComputeDependencies())
            return false;
        var parallelChecks = scope ParallelRecordingChecks();
        return CheckDrawBarriers(meshShader, vertices) && CheckGpuTimings() && parallelChecks.Run();
    }

    private static bool CheckUploadBatching()
    {
        RenderManager.WaitForIdle();
        var before = RenderManager.Synchronization;
        var textures = scope GpuTexture[48];
        defer
        {
            for (var texture in textures)
                delete texture;
        }
        for (int index = 0; index < textures.Count; ++index)
        {
            uint32 pixel = 0xFF000000 | (uint32)(index + 1);
            textures[index] = new .(1, 1, .rgba8_unorm, .sampled, &pixel, 4);
        }
        if (RenderManager.Synchronization.UploadSubmissionCount != before.UploadSubmissionCount
            || RenderManager.Synchronization.UploadWaitCount != before.UploadWaitCount)
            return false;
        RenderManager.FlushUploads();
        if (RenderManager.Synchronization.UploadSubmissionCount != before.UploadSubmissionCount + 1)
            return false;
        var commands = RenderManager.AcquireCommandBuffer(name: "Upload checks");
        var readbacks = scope TextureReadback[48];
        defer
        {
            for (var readback in readbacks)
                delete readback;
        }
        for (int index = 0; index < textures.Count; ++index)
            readbacks[index] = new .(commands, textures[index]);
        commands.Finish();
        RenderManager.SubmitCommandBuffer(commands);
        if (!RenderManager.Frame())
            return false;
        RenderManager.WaitForIdle();
        uint8[4] result = default;
        for (int index = 0; index < readbacks.Count; ++index)
        {
            if (!readbacks[index].CopyTo(.(&result, 4)) || result[0] != index + 1 || result[3] != 255)
                return false;
        }
        uint32 immediatePixel = 0xFF003F00;
        var immediateTexture = scope GpuTexture(1, 1, .rgba8_unorm, .sampled, &immediatePixel, 4);
        if (!RenderManager.ReadTexture(immediateTexture, &result, 4) || result[1] != 63)
            return false;
        Console.WriteLine("48 texture uploads: one batch, no upload waits, staging snapshots and immediate readback verified");
        return true;
    }

    private static void WriteTexture(RenderCommandBuffer commands, Shader shader, GpuBuffer buffer, GpuTexture texture)
    {
        uint32 descriptor = texture.GetMipDescriptor(0, true);
        commands.UseBuffer(buffer, .compute, .shader_read);
        commands.UseTexture(texture, .compute, .shader_write);
        RenderManager.Dispatch(commands, shader, 1, .() { x = 4, y = 4, z = 1 },
            .((uint8*)&descriptor, sizeof(uint32)), buffer.Memory.range.gpu);
    }

    private static bool CheckComputeDependencies()
    {
        var shader = ResourceManager.GetResource<Shader>("shaders/sync_compute");
        var fullscreen = ResourceManager.GetResource<Shader>("shaders/fullscreen_aspect_texture");
        if (shader == null || shader.Programs.Count != 2)
            return false;
        RenderManager.WaitForIdle();
        var output = scope GpuTexture(4, 4, .rgba8_unorm, .sampled | .storage);
        var copied = scope GpuTexture(4, 4, .rgba8_unorm, .sampled);
        var target = scope RenderTexture(4, 4);
        var buffer = GpuBuffer.CreateStorage(sizeof(Vector4));
        defer buffer.Dispose();
        var commands = RenderManager.AcquireCommandBuffer(target, "Compute and graphics dependencies");
        commands.ClearColorBuffer = true;
        Vector4 initial = .(0.25f, 0, 0, 1);
        buffer.Update(commands, .((uint8*)&initial, sizeof(Vector4)));
        commands.UseBuffer(buffer, .compute, .shader_read | .shader_write);
        RenderManager.Dispatch(commands, shader, 0, .() { x = 1, y = 1, z = 1 },
            storage: buffer.Memory.range.gpu);
        WriteTexture(commands, shader, buffer, output);
        RenderManager.RenderFullScreenTextureAspect(commands, output, fullscreen);
        commands.UseBuffer(buffer, .compute, .shader_read | .shader_write);
        RenderManager.Dispatch(commands, shader, 0, .() { x = 1, y = 1, z = 1 },
            storage: buffer.Memory.range.gpu);
        WriteTexture(commands, shader, buffer, output);
        if (!RenderManager.CopyTexture(commands, output, copied))
            return false;
        var drawnReadback = scope TextureReadback(commands, target.TextureHandle);
        var copiedReadback = scope TextureReadback(commands, copied);
        commands.Finish();
        RenderManager.SubmitCommandBuffer(commands);
        var statisticsBefore = RenderManager.Synchronization;
        if (!RenderManager.Frame())
            return false;
        RenderManager.WaitForIdle();
        uint8[64] pixels = default;
        if (!drawnReadback.CopyTo(.(&pixels, 64)) || Math.Abs((int)pixels[0] - 128) > 1)
            return false;
        if (!copiedReadback.CopyTo(.(&pixels, 64)) || Math.Abs((int)pixels[0] - 191) > 1)
            return false;
        if (RenderManager.Synchronization.FallbackBarrierCount != statisticsBefore.FallbackBarrierCount)
            return false;
        var nextCommands = RenderManager.AcquireCommandBuffer(name: "Cross-frame compute writer");
        nextCommands.UseBuffer(buffer, .compute, .shader_read | .shader_write);
        RenderManager.Dispatch(nextCommands, shader, 0, .() { x = 1, y = 1, z = 1 },
            storage: buffer.Memory.range.gpu);
        WriteTexture(nextCommands, shader, buffer, output);
        var sampleCommands = RenderManager.AcquireCommandBuffer(target, "Cross-buffer graphics reader");
        sampleCommands.ClearColorBuffer = true;
        RenderManager.RenderFullScreenTextureAspect(sampleCommands, output, fullscreen);
        var nextReadback = scope TextureReadback(sampleCommands, target.TextureHandle);
        nextCommands.Finish();
        RenderManager.SubmitCommandBuffer(nextCommands);
        sampleCommands.Finish();
        RenderManager.SubmitCommandBuffer(sampleCommands);
        if (!RenderManager.Frame())
            return false;
        RenderManager.WaitForIdle();
        if (!nextReadback.CopyTo(.(&pixels, 64)) || pixels[0] != 255)
            return false;
        Console.WriteLine("Buffer upload, compute/draw/copy hazards, cross-buffer and cross-frame dependencies passed");
        return true;
    }

    private static bool CheckDrawBarriers(Shader shader, GpuBuffer vertices)
    {
        var target = scope RenderTexture(32, 32);
        RenderManager.WaitForIdle();
        RenderManager.ProfilingEnabled = true;
        defer
        {
            RenderManager.WaitForIdle();
            RenderManager.ProfilingEnabled = false;
        }
        for (int mode = 0; mode < 2; ++mode)
        {
            bool hasParameters = mode == 1;
            var commands = RenderManager.AcquireCommandBuffer(target, "Declared draw dependencies");
            commands.ClearColorBuffer = true;
            uint32 unusedParameter = 0;
            for (int draw = 0; draw < 64; ++draw)
                RenderManager.Draw(commands, shader, 0, vertices, default, 3, 0, .Identity, .(1, 0, 0, 1), .Zero,
                    state: .Opaque, parameters: hasParameters ? .((uint8*)&unusedParameter, 4) : default);
            var before = RenderManager.Synchronization;
            commands.Finish();
            RenderManager.SubmitCommandBuffer(commands);
            if (!RenderManager.Frame())
                return false;
            RenderManager.WaitForIdle();
            var after = RenderManager.Synchronization;
            uint64 barriers = after.BarrierCount - before.BarrierCount;
            if (barriers > 2 || after.FallbackBarrierCount != before.FallbackBarrierCount)
                return false;
            Console.WriteLine("64 draws, parameters={}: {} barriers, {} ms GPU, {} ms CPU fence waits",
                hasParameters, barriers, RenderManager.GpuMilliseconds, after.CpuWaitMilliseconds - before.CpuWaitMilliseconds);
        }
        uint8[4096] pixels = default;
        if (!RenderManager.ReadTexture(target.TextureHandle, &pixels, sizeof(decltype(pixels))))
            return false;
        return pixels[(16 * 32 + 16) * 4] > 240;
    }

    private static bool CheckGpuTimings()
    {
        RenderManager.WaitForIdle();
        bool wasProfiling = RenderManager.ProfilingEnabled;
        RenderManager.ProfilingEnabled = true;
        defer
        {
            RenderManager.WaitForIdle();
            RenderManager.ProfilingEnabled = wasProfiling;
        }
        var firstTarget = scope RenderTexture(32, 32);
        var secondTarget = scope RenderTexture(32, 32);
        var first = RenderManager.AcquireCommandBuffer(firstTarget, "First timed buffer");
        first.ClearColorBuffer = true;
        var second = RenderManager.AcquireCommandBuffer(secondTarget, "Second timed buffer");
        second.ClearColorBuffer = true;
        first.Finish();
        RenderManager.SubmitCommandBuffer(first);
        second.Finish();
        RenderManager.SubmitCommandBuffer(second);
        var waitsBefore = RenderManager.Synchronization;
        if (!RenderManager.Frame())
            return false;
        if (RenderManager.Synchronization.ExplicitWaitCount != waitsBefore.ExplicitWaitCount
            || RenderManager.Synchronization.ReadbackWaitCount != waitsBefore.ReadbackWaitCount)
            return false;
        RenderManager.WaitForIdle();
        bool supported = GPU.GetDeviceCaps(RenderManager.Device).timestamp_period_ns > 0;
        if (RenderManager.HasGpuTiming != supported || RenderManager.CommandBufferTimingCount != 2)
            return false;
        var firstTiming = RenderManager.GetCommandBufferTiming(0);
        var secondTiming = RenderManager.GetCommandBufferTiming(1);
        if (firstTiming.Name != "First timed buffer" || secondTiming.Name != "Second timed buffer"
            || firstTiming.HasGpuTiming != supported || secondTiming.HasGpuTiming != supported)
            return false;
        if (firstTiming.GpuMilliseconds < 0 || secondTiming.GpuMilliseconds < 0
            || firstTiming.GpuMilliseconds > RenderManager.GpuMilliseconds + 0.001f
            || secondTiming.GpuMilliseconds > RenderManager.GpuMilliseconds + 0.001f)
            return false;
        var recycled = RenderManager.AcquireCommandBuffer(name: "Reused buffer");
        RenderManager.CancelCommandBuffer(recycled);
        if (firstTiming.Name != "First timed buffer" || secondTiming.Name != "Second timed buffer")
            return false;
        Console.WriteLine("GPU frame: {} ms; {}: {} ms; {}: {} ms",
            RenderManager.GpuMilliseconds, firstTiming.Name, firstTiming.GpuMilliseconds,
            secondTiming.Name, secondTiming.GpuMilliseconds);

        if (!RenderManager.Frame())
            return false;
        RenderManager.WaitForIdle();
        if (RenderManager.HasGpuTiming != supported || RenderManager.CommandBufferTimingCount != 0)
            return false;
        RenderManager.ProfilingEnabled = false;
        var untimed = RenderManager.AcquireCommandBuffer(name: "Untimed buffer");
        untimed.Finish();
        RenderManager.SubmitCommandBuffer(untimed);
        if (!RenderManager.Frame())
            return false;
        RenderManager.WaitForIdle();
        if (RenderManager.HasGpuTiming || RenderManager.GpuMilliseconds != 0
            || RenderManager.CommandBufferTimingCount != 1)
            return false;
        var untimedResult = RenderManager.GetCommandBufferTiming(0);
        return !untimedResult.HasGpuTiming && untimedResult.GpuMilliseconds == 0 && untimedResult.Name == "Untimed buffer";
    }

}
