using internal GameCore;
using System;
using System.Threading;
using GameCore;
using NoGraphicsAPI;
using jazzutils;

namespace Example;

class ParallelRecordingChecks
{
    private const int TargetCount = 8;
    private RenderTexture[TargetCount] targets;
    private GpuTexture[TargetCount] outputs;
    private GpuBuffer[TargetCount] storageBuffers;
    private RenderCommandBuffer[TargetCount] graphicsCommands;
    private RenderCommandBuffer[TargetCount] computeCommands;
    private TextureReadback[TargetCount] readbacks;
    private Shader computeShader;
    private Shader graphicsShader;
    private bool recordCompute;
    private int workerMask;
    private int mainThreadId;
    private int backgroundRecordings;

    public ~this()
    {
        RenderManager.WaitForIdle();
        for (int index = 0; index < TargetCount; ++index)
        {
            delete readbacks[index];
            delete targets[index];
            delete outputs[index];
            storageBuffers[index].Dispose();
        }
    }

    private void RecordRange(uint32 startIndex, uint32 endIndex, uint32 workerIndex)
    {
        Interlocked.Or(ref workerMask, 1 << (int)workerIndex);
        if (Thread.CurrentThreadId != mainThreadId)
            Interlocked.Increment(ref backgroundRecordings);
        for (uint32 index = startIndex; index < endIndex; ++index)
        {
            if (recordCompute)
            {
                var commands = computeCommands[index];
                var storage = storageBuffers[index];
                Vector4 initial = .(0.25f + index / 32.0f, 0, 0, 1);
                storage.Update(commands, .((uint8*)&initial, sizeof(Vector4)));
                commands.UseBuffer(storage, .compute, .shader_read | .shader_write);
                RenderManager.Dispatch(commands, computeShader, 0, .() { x = 1, y = 1, z = 1 },
                    storage: storage.Memory.range.gpu);
                uint32 descriptor = outputs[index].GetMipDescriptor(0, true);
                commands.UseBuffer(storage, .compute, .shader_read);
                commands.UseTexture(outputs[index], .compute, .shader_write);
                RenderManager.Dispatch(commands, computeShader, 1, .() { x = 4, y = 4, z = 1 },
                    .((uint8*)&descriptor, sizeof(uint32)), storage.Memory.range.gpu);
                commands.Finish();
            }
            else
            {
                var commands = graphicsCommands[index];
                commands.ClearColorBuffer = true;
                RenderManager.RenderFullScreenTextureAspect(commands, outputs[index], graphicsShader);
                readbacks[index] = new .(commands, targets[index].TextureHandle);
                commands.Finish();
            }
        }
    }

    public bool Run()
    {
        mainThreadId = Thread.CurrentThreadId;
        computeShader = ResourceManager.GetResource<Shader>("shaders/sync_compute");
        graphicsShader = ResourceManager.GetResource<Shader>("shaders/fullscreen_aspect_texture");
        for (int index = 0; index < TargetCount; ++index)
        {
            targets[index] = new .(4, 4);
            outputs[index] = new .(4, 4, .rgba8_unorm, .sampled | .storage);
            storageBuffers[index] = GpuBuffer.CreateStorage(sizeof(Vector4));
        }
        var job = JobSystem.CreateJob(new => RecordRange);
        defer
        {
            delete job.callback;
            job.callback = null;
        }
        for (int frameIndex = 0; frameIndex < 4; ++frameIndex)
        {
            for (int index = 0; index < TargetCount; ++index)
            {
                graphicsCommands[index] = RenderManager.AcquireCommandBuffer(targets[index], "Worker graphics");
                computeCommands[index] = RenderManager.AcquireCommandBuffer(name: "Worker compute");
            }
            recordCompute = false;
            JobSystem.AddJob(job, TargetCount);
            for (int attempt = 0; attempt < 1000 && Interlocked.CompareExchange(ref backgroundRecordings, 0, 0) == 0; ++attempt)
                Thread.Sleep(1);
            JobSystem.WaitJobs(job);
            recordCompute = true;
            JobSystem.AddJob(job, TargetCount);
            JobSystem.WaitJobs(job);
            for (int index = 0; index < TargetCount; ++index)
            {
                var graphics = graphicsCommands[index];
                var compute = computeCommands[index];
                if (graphics.Status != .Executable || compute.Status != .Executable
                    || graphics.NativeCommands == null || compute.NativeCommands == null
                    || graphics.DrawCount != 1 || compute.DispatchCount != 2
                    || graphics.Pipelines.Count == 0 || compute.Pipelines.Count == 0)
                    return false;
                RenderManager.SubmitCommandBuffer(compute);
                RenderManager.SubmitCommandBuffer(graphics);
            }
            if (!RenderManager.Frame())
                return false;
            RenderManager.WaitForIdle();
            for (int index = 0; index < TargetCount; ++index)
            {
                uint8[64] pixels = default;
                if (!readbacks[index].CopyTo(.(&pixels, 64)))
                    return false;
                for (int pixel = 0; pixel < 16; ++pixel)
                    if (Math.Abs((int)pixels[pixel * 4] - (0.5f + index / 32.0f) * 255) > 1
                        || pixels[pixel * 4 + 3] != 255)
                        return false;
                delete readbacks[index];
                readbacks[index] = null;
            }
        }
        Console.WriteLine("Native job recording: worker mask {}, {} background callbacks; four frames of compute-to-draw readbacks passed", workerMask, backgroundRecordings);
        return backgroundRecordings > 0 && (workerMask & (workerMask - 1)) != 0;
    }
}
