using internal GameCore;
using System;
using System.Collections;
using System.Threading;
using System.Diagnostics;
using NoGraphicsAPI;
using ImGui;

namespace GameCore;

public enum RenderShaderType
{
    Font,
    Last
}

public static class RenderManager
{
    public struct Statistics
    {
        public uint64 submitCount, blitCount, dispatchCount;

        public void Clear() mut
        {
            this = default;
        }
    }

    struct RetiredTexture
    {
        public NoGraphicsAPI.Texture* Texture;
        public TextureHeap Memory;
        public RenderView* View;
        public uint32 Descriptor;
        public ImGui.TextureID Image;
    }

    public static uint32 TextureDescriptorCapacity { get; private set; }
    private const uint32 ImGuiTextureCapacity = 256;
    public static readonly Monitor ResourceLock = new .() ~ delete _;
    public static Device* Device;
    public static uint64 CompletedFrame { get; private set; }
    private static UploadBatch[] uploadBatches = new UploadBatch[FramesInFlight] ~ DeleteContainerAndItems!(_);
    private static int uploadBatchIndex;
    private static UploadBatch activeUploadBatch;
    internal static RenderResourceTracker ResourceTracker;

    public struct SynchronizationStatistics
    {
        public uint64 FrameWaitCount;
        public uint64 UploadWaitCount;
        public uint64 ReadbackWaitCount;
        public uint64 ExplicitWaitCount;
        public double CpuWaitMilliseconds;
        public uint64 UploadSubmissionCount;
        public uint64 UploadBytes;
        public uint64 BarrierCount;
        public uint64 FallbackBarrierCount;
    }

    public static SynchronizationStatistics Synchronization;
    private enum WaitReason
    {
        FrameReuse,
        UploadReuse,
        Readback,
        Explicit
    }


    private class FrameResources
    {
        public CommandPool* Pool;
        public TimelinePoint Completion;
        public uint64 FrameNumber;
        public GpuHeap Timestamps;
        public bool RecordedTimings;
        public SwapchainFrame AcquiredFrame;
        public CommandBuffer* Prologue;
        public List<RenderCommandBuffer> Buffers = new .() ~ delete _;
        public List<GpuHeap> RetiredBuffers = new .() ~ delete _;
        public List<RetiredTexture> RetiredTextures = new .() ~ delete _;
        public List<uint32> RetiredDescriptors = new .() ~ delete _;

        public this()
        {
            Pool = GPU.CreateCommandPool(Device, 0);
            Timestamps = GPU.CreateGpuHeap(Device, 2 * sizeof(uint64), .readback);
        }

        public ~this()
        {
            GPU.DestroyGpuHeap(Timestamps);
            GPU.DestroyCommandPool(Pool);
        }
    }

    public const int FramesInFlight = 3;
    private static FrameResources[] frames = new FrameResources[FramesInFlight] ~ DeleteContainerAndItems!(_);
    private static List<RenderCommandBuffer> commandBuffers = new .() ~ DeleteContainerAndItems!(_);
    private static List<RenderCommandBuffer> availableCommandBuffers = new .() ~ delete _;
    private static List<RenderCommandBuffer> submittedCommandBuffers = new .() ~ delete _;
    private static List<NoGraphicsAPI.CommandBuffer*> nativeCommandBuffers = new .() ~ delete _;
    private static int frameIndex;
    private static bool framePrepared;
    private static uint64 submittedFrames;
    public static bool ProfilingEnabled;
    public static float GpuMilliseconds { get; private set; }
    public static bool HasGpuTiming { get; private set; }
    private static List<CommandBufferTiming> completedCommandBufferTimings = new .() ~ DeleteContainerAndItems!(_);
    public static int CommandBufferTimingCount { get; private set; }

    public class CommandBufferTiming
    {
        private String name = new .() ~ delete _;
        public StringView Name => name;
        public float GpuMilliseconds { get; internal set; }
        public bool HasGpuTiming { get; internal set; }
        public uint32 DrawCount { get; internal set; }
        public uint32 TriangleCount { get; internal set; }

        internal void SetName(StringView value)
        {
            name.Set(value);
        }
    }

    public static uint32 DrawCount { get; private set; }
    public static uint32 TriangleCount { get; private set; }
    public static int CommandBufferCount => commandBuffers.Count;
    public static GpuHeap TextureDescriptors, SamplerDescriptors;
    private static TimelinePoint completion;
    private static bool hasSwapchain;
    private static List<GpuHeap> retiredBuffers = new .() ~ delete _;
    private static List<RetiredTexture> retiredTextures = new .() ~ delete _;
    private static List<uint32> retiredDescriptors = new .() ~ delete _;
    private static List<uint32> freeDescriptors = new .() ~ delete _;
    private static uint32 nextDescriptor;
    private static List<SamplerDesc> samplerDescriptions = new .() ~ delete _;
    private static GpuTexture whiteTexture;
    public static Statistics statistics;
    public static SpriteBatchRenderer batchRenderer, entityBatchRenderer;
    public static RenderTexture temporaryRenderTextureWithDepth;
    public static GpuTexture readBackTextureHandle;
    public static bool capture;
    public static int width = 1280, height = 720;
    public static float ooWidth, ooHeight, aspectRatio = 1;
    public static Bounds2 viewBounds;
    public static bool IsRenderTextureYFlipped => true;
    public static Vector4 ShaderData { get; private set; }
    public static GpuBuffer batchVertexBufferHandle, batchIndexBufferHandle, batchTesselatedVertexBufferHandle, batchTesselatedIndexBufferHandle;
    public static int batchVertexCount, batchIndexCount, batchTesselatedVertexCount, batchTesselatedIndexCount;
    public static VertexLayout batchVertexLayout;
    public static Shader[] shaders = new Shader[(int)RenderShaderType.Last] ~ delete _;
    public static SH9 sh9 = new .() ~ delete _;
    public typealias OverlayRenderer = function void(CommandBuffer* commands, uint32x2 extent, TimelinePoint completion);

    public static SamplerDesc LinearClamp
    {
        get
        {
            SamplerDesc sampler = .();
            sampler.address_u = sampler.address_v = sampler.address_w = .clamp_to_edge;
            return sampler;
        }
    }

    public static SamplerDesc PointClamp
    {
        get
        {
            var sampler = LinearClamp;
            sampler.min_filter = sampler.mag_filter = sampler.mip_filter = .nearest;
            return sampler;
        }
    }

    public static CommandBufferTiming GetCommandBufferTiming(int index)
    {
        if (index < 0 || index >= CommandBufferTimingCount)
            Runtime.FatalError("Command buffer timing index out of range");
        return completedCommandBufferTimings[index];
    }

    public static bool InitializeDevice(void* nativeWindow, uint32 textureDescriptorCapacity = 8192)
    {
        if (Device != null)
            return false;
        // DX12 reserves descriptors starting at 32768 for internal buffer access.
        if (textureDescriptorCapacity == 0 || textureDescriptorCapacity > 32768 - ImGuiTextureCapacity)
            return false;
        DeviceDesc description = .();
        description.window = nativeWindow;
        description.swapchain_format = .bgra8_srgb;
        description.timestamp_query_count = 2;
        Device = GPU.CreateDevice(description).device;
        if (Device == null)
            return false;
        TextureDescriptorCapacity = textureDescriptorCapacity;
        hasSwapchain = nativeWindow != null;
        var capabilities = GPU.GetDeviceCaps(Device);
        TextureDescriptors = GPU.CreateGpuHeap(Device, capabilities.texture_descriptor_size * (TextureDescriptorCapacity + ImGuiTextureCapacity), .texture_descriptor_heap);
        SamplerDescriptors = GPU.CreateGpuHeap(Device, capabilities.sampler_descriptor_size * 256, .sampler_descriptor_heap);
        completion = .();
        completion.semaphore = GPU.CreateTimelineSemaphore(Device, 0);
        if (TextureDescriptors.owner == null || SamplerDescriptors.owner == null || completion.semaphore == null)
        {
            ShutdownDevice();
            return false;
        }
        CompletedFrame = submittedFrames = 0;
        GpuMilliseconds = 0;
        HasGpuTiming = false;
        CommandBufferTimingCount = 0;
        frameIndex = 0;
        framePrepared = false;
        for (var frame in ref frames)
            frame = new .();
        ResourceTracker = new .();
        Synchronization = default;
        uploadBatchIndex = 0;
        for (var batch in ref uploadBatches)
            batch = new .();
        uint32 white = uint32.MaxValue;
        whiteTexture = new .(1, 1, .rgba8_unorm, .sampled, &white, 4);
        GetSampler(LinearClamp);
        return true;
    }

    public static bool InitializeImGui(SDL2.SDL.Window* window) => ImGui.NgaInitializeShared(window, Device, .bgra8_srgb, ImGuiTextureCapacity, &TextureDescriptors, &SamplerDescriptors, TextureDescriptorCapacity, 255);

    public static void ShutdownDevice()
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        if (Device == null)
            return;
        WaitForIdle();
        GPU.WaitIdle(Device);
        delete whiteTexture;
        whiteTexture = null;
        CollectResources(retiredBuffers, retiredTextures, retiredDescriptors);
        for (var buffer in commandBuffers)
            delete buffer;
        commandBuffers.Clear();
        availableCommandBuffers.Clear();
        submittedCommandBuffers.Clear();
        nativeCommandBuffers.Clear();
        for (var frame in ref frames)
        {
            delete frame;
            frame = null;
        }
        for (var batch in ref uploadBatches)
        {
            delete batch;
            batch = null;
        }
        delete ResourceTracker;
        ResourceTracker = null;
        GPU.DestroyTimelineSemaphore(completion.semaphore);
        GPU.DestroyGpuHeap(TextureDescriptors);
        GPU.DestroyGpuHeap(SamplerDescriptors);
        GPU.DestroyDevice(Device);
        Device = null;
        TextureDescriptorCapacity = 0;
        GpuMilliseconds = 0;
        HasGpuTiming = false;
        CommandBufferTimingCount = 0;
        for (var timing in completedCommandBufferTimings)
            delete timing;
        completedCommandBufferTimings.Clear();
        nextDescriptor = 0;
        freeDescriptors.Clear();
        samplerDescriptions.Clear();
    }

    public static uint32 AllocateTextureDescriptor()
    {
        if (freeDescriptors.Count > 0)
            return freeDescriptors.PopBack();
        if (nextDescriptor == TextureDescriptorCapacity)
            Runtime.FatalError("GameCore texture descriptor capacity exceeded");
        return nextDescriptor++;
    }

    public static uint32 GetSampler(SamplerDesc sampler)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        for (int index = 0; index < samplerDescriptions.Count; ++index)
        {
            var existing = samplerDescriptions[index];
            if (existing.min_filter == sampler.min_filter && existing.mag_filter == sampler.mag_filter && existing.mip_filter == sampler.mip_filter
                && existing.address_u == sampler.address_u && existing.address_v == sampler.address_v && existing.address_w == sampler.address_w
                && existing.anisotropic == sampler.anisotropic && existing.compare_enabled == sampler.compare_enabled && existing.compare == sampler.compare) return (.)index;
        }
        if (samplerDescriptions.Count >= 255)
            Runtime.FatalError("GameCore sampler capacity exceeded");
        uint32 descriptor = (.)samplerDescriptions.Count;
        samplerDescriptions.Add(sampler);
        GPU.WriteSamplerDescriptor(Device, SamplerDescriptors.range.cpu + descriptor * GPU.GetDeviceCaps(Device).sampler_descriptor_size, sampler);
        return descriptor;
    }

    public static void Retire(GpuHeap memory)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        retiredBuffers.Add(memory);
    }

    public static void RetireTexture(NoGraphicsAPI.Texture* texture, TextureHeap memory, RenderView* view, uint32 descriptor, ImGui.TextureID image)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        retiredTextures.Add(.() { Texture = texture, Memory = memory, View = view, Descriptor = descriptor, Image = image });
    }

    public static void RetireTextureDescriptor(uint32 descriptor)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        retiredDescriptors.Add(descriptor);
    }

    private static void CollectResources(List<GpuHeap> retiredBuffers, List<RetiredTexture> retiredTextures, List<uint32> retiredDescriptors)
    {
        for (var memory in retiredBuffers)
        {
            ResourceTracker?.Forget(memory.owner, false);
            GPU.DestroyGpuHeap(memory);
        }
        retiredBuffers.Clear();
        for (var texture in retiredTextures)
        {
            if (texture.Image != default)
                ImGui.NgaRemoveTexture(texture.Image);
            ResourceTracker?.Forget(texture.Texture, true);
            GPU.DestroyRenderView(texture.View);
            GPU.DestroyTexture(texture.Texture);
            GPU.DestroyTextureHeap(texture.Memory);
            freeDescriptors.Add(texture.Descriptor);
        }
        retiredTextures.Clear();
        freeDescriptors.AddRange(retiredDescriptors);
        retiredDescriptors.Clear();
    }

    private static void WaitForCompletion(TimelinePoint point, WaitReason reason)
    {
        if (point.semaphore == null || point.value == 0 || GPU.TimelineCompletedValue(point.semaphore) >= point.value)
            return;

        var timer = scope Stopwatch();
        timer.Start();
        GPU.WaitTimeline(point);
        timer.Stop();
        Synchronization.CpuWaitMilliseconds += timer.Elapsed.TotalMilliseconds;
        switch (reason)
        {
        case .FrameReuse:
            ++Synchronization.FrameWaitCount;
        case .UploadReuse:
            ++Synchronization.UploadWaitCount;
        case .Readback:
            ++Synchronization.ReadbackWaitCount;
        case .Explicit:
            ++Synchronization.ExplicitWaitCount;
        }
    }

    internal static CommandBuffer* BeginUpload()
    {
        if (activeUploadBatch != null && activeUploadBatch.ByteCount >= 16UL * 1024 * 1024)
            FlushUploads();
        if (activeUploadBatch == null)
        {
            activeUploadBatch = uploadBatches[uploadBatchIndex];
            WaitForCompletion(activeUploadBatch.Completion, .UploadReuse);
            activeUploadBatch.Reset();
            activeUploadBatch.Commands = GPU.BeginCommands(activeUploadBatch.Pool);
        }
        return activeUploadBatch.Commands;
    }

    internal static GpuCpuRange AllocateUpload(uint64 byteCount)
    {
        return activeUploadBatch.Allocate(byteCount);
    }

    public static TimelinePoint FlushUploads()
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        if (activeUploadBatch == null)
            return completion;

        var commands = activeUploadBatch.Commands;
        GPU.Barrier(commands, .transfer | .color_output | .depth_stencil_tests,
            .transfer_write | .color_write | .depth_stencil_write, .all_commands,
            .shader_read | .shader_write | .transfer_read | .transfer_write | .color_read | .color_write | .depth_stencil_read | .depth_stencil_write);
        ++Synchronization.BarrierCount;
        GPU.EndCommands(commands);
        ++completion.value;
        SubmitDesc submission = .();
        submission.commands = .() { data = &commands, size = 1 };
        submission.completion = completion;
        GPU.Submit(Device, submission, 0);
        activeUploadBatch.Completion = completion;
        ++Synchronization.UploadSubmissionCount;
        Synchronization.UploadBytes += activeUploadBatch.ByteCount;
        activeUploadBatch = null;
        uploadBatchIndex = (uploadBatchIndex + 1) % FramesInFlight;
        return completion;
    }

    private static void CompleteFrame(FrameResources frame, WaitReason reason = .FrameReuse)
    {
        if (frame.Completion.value == 0)
            return;
        WaitForCompletion(frame.Completion, reason);
        uint64* frameTicks = (.)frame.Timestamps.range.cpu;
        HasGpuTiming = frame.RecordedTimings && frameTicks[1] >= frameTicks[0];
        GpuMilliseconds = HasGpuTiming ? (frameTicks[1] - frameTicks[0]) * GPU.GetDeviceCaps(Device).timestamp_period_ns / 1000000.0f : 0;
        CommandBufferTimingCount = 0;
        DrawCount = 0;
        TriangleCount = 0;
        for (var buffer in frame.Buffers)
        {
            if (CommandBufferTimingCount == completedCommandBufferTimings.Count)
                completedCommandBufferTimings.Add(new .());
            var timing = completedCommandBufferTimings[CommandBufferTimingCount++];
            timing.SetName(buffer.Name);
            buffer.Complete();
            timing.GpuMilliseconds = buffer.GpuMilliseconds;
            timing.HasGpuTiming = buffer.HasGpuTiming;
            timing.DrawCount = buffer.DrawCount;
            timing.TriangleCount = buffer.TriangleCount;
            DrawCount += buffer.DrawCount;
            TriangleCount += buffer.TriangleCount;
            availableCommandBuffers.Add(buffer);
        }
        frame.Buffers.Clear();
        CompletedFrame = Math.Max(CompletedFrame, frame.FrameNumber);
        CollectResources(frame.RetiredBuffers, frame.RetiredTextures, frame.RetiredDescriptors);
        GPU.ResetCommandPool(frame.Pool);
        frame.Completion = default;
    }

    private static void PrepareFrame()
    {
        if (framePrepared)
            return;
        var frameResources = frames[frameIndex];
        CompleteFrame(frameResources);
        var commands = GPU.BeginCommands(frameResources.Pool);
        frameResources.RecordedTimings = ProfilingEnabled && frameResources.Timestamps.range.cpu != null
            && GPU.GetDeviceCaps(Device).timestamp_period_ns > 0;
        if (frameResources.RecordedTimings)
            GPU.WriteTimestamp(commands, (.)frameResources.Timestamps.range.gpu, .all_commands);
        SwapchainFrame frame = hasSwapchain ? GPU.Acquire(commands) : default;
        if (frame.render_view != null)
        {
            // Overlay-only frames need an initialized swapchain image before loading it.
            ColorAttachment initialColor = .();
            initialColor.render_view = frame.render_view;
            initialColor.load = .clear;
            RenderingDesc initialRendering = .();
            initialRendering.colors = .() { data = &initialColor, size = 1 };
            GPU.BeginRenderPass(commands, initialRendering, .none);
            GPU.EndRenderPass(commands);
        }
        GPU.EndCommands(commands);
        frameResources.AcquiredFrame = frame;
        frameResources.Prologue = commands;
        framePrepared = true;
    }

    public static RenderCommandBuffer AcquireCommandBuffer(RenderTexture target = null, StringView name = default)
    {
        return AcquireCommandBuffer(target, false, name);
    }

    public static RenderCommandBuffer AcquireSwapchainCommandBuffer(StringView name = default)
    {
        if (!hasSwapchain)
            Runtime.FatalError("No swapchain is available");
        return AcquireCommandBuffer(null, true, name);
    }

    private static RenderCommandBuffer AcquireCommandBuffer(RenderTexture target, bool swapchain, StringView name)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        PrepareFrame();
        RenderCommandBuffer buffer;
        if (availableCommandBuffers.Count > 0)
            buffer = availableCommandBuffers.PopBack();
        else
        {
            buffer = new .(Device);
            commandBuffers.Add(buffer);
        }
        buffer.Status = .Recording;
        buffer.ProfilingEnabled = ProfilingEnabled;
        buffer.Name.Set(name);
        buffer.FrameShaderData = ShaderData;
        Internal.MemCpy(&buffer.FrameSphericalHarmonics[0], &sh9.sh[0].x, 9 * sizeof(Vector4));
        buffer.Begin(target, swapchain, frames[frameIndex].AcquiredFrame);
        return buffer;
    }

    public static void SubmitCommandBuffer(RenderCommandBuffer buffer)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        if (buffer.Status != .Executable)
            Runtime.FatalError("Finish command buffer recording before submission");
        buffer.Status = .Queued;
        statistics.submitCount += buffer.DrawCount;
        statistics.dispatchCount += buffer.DispatchCount;
        statistics.blitCount += buffer.CopyCount;
        submittedCommandBuffers.Add(buffer);
    }

    public static void CancelCommandBuffer(RenderCommandBuffer buffer)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        if (buffer.Status != .Recording && buffer.Status != .Executable)
            Runtime.FatalError("Only unsubmitted command buffers can be cancelled");
        buffer.Cancel();
        availableCommandBuffers.Add(buffer);
    }

    public static void WaitForIdle()
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        var uploadsComplete = FlushUploads();
        WaitForCompletion(uploadsComplete, .Explicit);
        for (int offset = 0; offset < FramesInFlight; ++offset)
            if (frames[(frameIndex + offset) % FramesInFlight] != null)
                CompleteFrame(frames[(frameIndex + offset) % FramesInFlight], .Explicit);
    }

    public static bool Frame(OverlayRenderer overlay = null)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        PrepareFrame();
        for (var buffer in commandBuffers)
            if (buffer.Status == .Recording || buffer.Status == .Executable)
                Runtime.FatalError("Submit or cancel acquired command buffers before Frame");
        FlushUploads();
        var frameResources = frames[frameIndex];
        nativeCommandBuffers.Clear();
        var frame = frameResources.AcquiredFrame;
        nativeCommandBuffers.Add(frameResources.Prologue);
        CommandBuffer* commands;
        bool success = true;
        for (var buffer in submittedCommandBuffers)
        {
            ResourceTracker.BeginCommand();
            for (var access in buffer.ResourceSummary)
                ResourceTracker.Add(access);
            if (ResourceTracker.Prepare())
            {
                commands = GPU.BeginCommands(frameResources.Pool);
                ResourceTracker.Emit(commands);
                GPU.EndCommands(commands);
                nativeCommandBuffers.Add(commands);
            }
            nativeCommandBuffers.Add(buffer.NativeCommands);
            success &= buffer.RecordingSucceeded;
            Synchronization.BarrierCount += buffer.BarrierCount;
            buffer.Status = .InFlight;
            frameResources.Buffers.Add(buffer);
        }
        submittedCommandBuffers.Clear();
        completion.value++;
        commands = GPU.BeginCommands(frameResources.Pool);
        if (overlay != null && frame.render_view != null)
        {
            ResourceTracker.SynchronizeExternal(commands);
            GPU.SetTextureDescriptorHeap(commands, GPU.GpuRange(TextureDescriptors));
            GPU.SetSamplerDescriptorHeap(commands, GPU.GpuRange(SamplerDescriptors));
            ColorAttachment color = .();
            color.render_view = frame.render_view;
            RenderingDesc rendering = .();
            rendering.colors = .() { data = &color, size = 1 };
            GPU.BeginRenderPass(commands, rendering, .none);
            overlay(commands, frame.extent, completion);
            GPU.EndRenderPass(commands);
        }
        if (frameResources.RecordedTimings)
            GPU.WriteTimestamp(commands, (uint64*)frameResources.Timestamps.range.gpu + 1, .all_commands);
        GPU.EndCommands(commands);
        nativeCommandBuffers.Add(commands);
        SubmitDesc submission = .();
        submission.commands = .() { data = nativeCommandBuffers.Ptr, size = (.)nativeCommandBuffers.Count };
        submission.completion = completion;
        if (frame.render_view != null)
            GPU.SubmitAndPresent(Device, submission);
        else GPU.Submit(Device, submission, 0);
        frameResources.Completion = completion;
        frameResources.FrameNumber = ++submittedFrames;
        frameResources.RetiredBuffers.AddRange(retiredBuffers);
        retiredBuffers.Clear();
        frameResources.RetiredTextures.AddRange(retiredTextures);
        retiredTextures.Clear();
        frameResources.RetiredDescriptors.AddRange(retiredDescriptors);
        retiredDescriptors.Clear();
        frameIndex = (frameIndex + 1) % FramesInFlight;
        framePrepared = false;
        return success;
    }

    public static bool ReadTexture(GpuTexture texture, void* destination, uint32 capacity, uint32 mip = 0)
    {
        ResourceLock.Enter();
        defer ResourceLock.Exit();
        for (var buffer in commandBuffers)
            if (buffer.Status == .Recording || buffer.Status == .Executable || buffer.Status == .Queued)
                return false;
        if (mip >= texture.MipLevels)
            return false;
        var formatInfo = GPU.GetTextureFormatInfo(texture.Format);
        uint64 blocksX = (Math.Max(1U, texture.Width >> (int)mip) + formatInfo.block_extent.x - 1) / formatInfo.block_extent.x;
        uint64 blocksY = (Math.Max(1U, texture.Height >> (int)mip) + formatInfo.block_extent.y - 1) / formatInfo.block_extent.y;
        uint64 size = blocksX * blocksY * Math.Max(1U, texture.Depth >> (int)mip) * texture.LayerCount * formatInfo.bytes_per_block;
        if (capacity < size)
            return false;
        var memory = GPU.CreateGpuHeap(Device, size, .readback);
        if (memory.range.cpu == null)
            return false;
        FlushUploads();
        var commands = BeginUpload();
        ResourceTracker.BeginCommand();
        ResourceTracker.Texture(texture.Texture, .transfer, .transfer_read);
        ResourceTracker.Prepare();
        ResourceTracker.Emit(commands);
        GPU.CopyTextureToMemory(commands, texture.Texture, GPU.GpuRange(memory), .() { mip_level = mip });
        GPU.Barrier(commands, .transfer, .transfer_write, .host, .host_read);
        ++Synchronization.BarrierCount;
        WaitForCompletion(FlushUploads(), .Readback);
        Internal.MemCpy(destination, memory.range.cpu, (.)size);
        GPU.DestroyGpuHeap(memory);
        return true;
    }

    public static bool CopyTexture(RenderCommandBuffer commandBuffer, GpuTexture source, GpuTexture destination, TextureCopyDesc sourceRegion = default, TextureCopyDesc destinationRegion = default)
    {
        return commandBuffer.CopyTexture(source, destination, sourceRegion, destinationRegion);
    }

    public static Shader GetShader(RenderShaderType type) => shaders[(int)type];

    public static void PreInitialize()
    {
    }

    public static bool Initialize(int maxBatchCount = 128)
    {
        batchRenderer = new .();
        entityBatchRenderer = new .();
        batchVertexLayout.Begin();
        batchVertexLayout.Add(.Position, 3, .Float);
        batchVertexLayout.End();
        CreateQuad(1, 1, maxBatchCount, out batchVertexBufferHandle, out batchIndexBufferHandle, out batchVertexCount, out batchIndexCount);
        CreateQuad(2, 2, maxBatchCount, out batchTesselatedVertexBufferHandle, out batchTesselatedIndexBufferHandle, out batchTesselatedVertexCount, out batchTesselatedIndexCount);
        shaders[(int)RenderShaderType.Font] = ResourceManager.GetResource<Shader>("shaders/font_sprite_texture");
        Resize(width, height);
        return true;
    }

    public static void Resize(int newWidth, int newHeight)
    {
        width = newWidth;
        height = newHeight;
        ooWidth = 1.0f / Math.Max(1, width);
        ooHeight = 1.0f / Math.Max(1, height);
        aspectRatio = width * ooHeight;
        viewBounds = .(.Zero, .(width, height));
        if (temporaryRenderTextureWithDepth == null)
            temporaryRenderTextureWithDepth = new .(width, height, .rgba16_float, .d24_unorm_s8_uint);
        else temporaryRenderTextureWithDepth.Resize(width, height);
    }

    public static void Finalize()
    {
        WaitForIdle();
        DebugDraw3D.Finalize();
        delete batchRenderer;
        delete entityBatchRenderer;
        delete temporaryRenderTextureWithDepth;
        delete readBackTextureHandle;
        batchRenderer = null;
        entityBatchRenderer = null;
        temporaryRenderTextureWithDepth = null;
        readBackTextureHandle = null;
        batchVertexBufferHandle.Dispose();
        batchIndexBufferHandle.Dispose();
        batchTesselatedVertexBufferHandle.Dispose();
        batchTesselatedIndexBufferHandle.Dispose();
    }

    public static void OnPreRender(float timeStep)
    {
        statistics.Clear();
        ShaderData = .((float)Time.Time, (float)(Time.Time * 0.1), timeStep, timeStep != 0 ? 1.0f / timeStep : 0);
    }

    public static void OnPostRender()
    {
    }

    public static void FixProjectionMatrix(ref Matrix4 projection)
    {
        projection.d[5] = -projection.d[5];
        projection.v.m31 = -projection.v.m31;
    }

    public static CullMode GetCullingState(bool counterClockwise) => counterClockwise ? .clockwise : .counter_clockwise;

    public static Matrix4 CreatePerspectiveOrtho(float left, float right, float bottom, float top, float near, float far, float offset = 0)
    {
        var projection = Matrix4.CreatePerspectiveOrtho(left, right, bottom, top, near, far, offset, false);
        FixProjectionMatrix(ref projection);
        return projection;
    }

    public static void Draw(RenderCommandBuffer commandBuffer, Shader shader, int programIndex, GpuBuffer vertices, GpuBuffer indices, uint32 vertexCount, uint32 indexCount,
        Matrix4 world, Vector4 color, Vector4 settings, GpuTexture[] textures = null, RenderState? state = null, SamplerDesc? sampler = null,
        Vector4* instances = null, int instanceCount = 0, Vector4 textureScale = .Zero, void* storage = null, bool lines = false, Span<uint8> parameters = default)
    {
        DrawConstants constants = .() { World = world, Color = color, Time = commandBuffer.FrameShaderData, Settings = settings, TextureScale = textureScale };
        constants.Instances = (.)commandBuffer.Upload(instances, (uint64)instanceCount * sizeof(Vector4));
        constants.SphericalHarmonics = (.)commandBuffer.Upload(&commandBuffer.FrameSphericalHarmonics[0], 9 * sizeof(Vector4));
        constants.Parameters = commandBuffer.Upload(parameters.Ptr, (.)parameters.Length);
        uint32 samplerIndex = GetSampler(sampler.GetValueOrDefault(LinearClamp));
        for (int index = 0; index < 8; ++index)
        {
            var texture = textures != null && index < textures.Count && textures[index] != null ? textures[index] : whiteTexture;
            constants.Textures[index] = texture.Descriptor;
            commandBuffer.UseTexture(texture, .vertex | .fragment, .shader_read);
            constants.Samplers[index] = samplerIndex;
        }
        commandBuffer.Draw(shader.Programs[programIndex], vertices, indices, vertexCount, indexCount, constants, state.GetValueOrDefault(.Alpha), storage, lines);
    }

    public static void Dispatch(RenderCommandBuffer commandBuffer, Shader shader, int programIndex, uint32x3 groups, Span<uint8> parameters = default, void* storage = null)
    {
        DrawConstants constants = .() { World = .Identity, Time = commandBuffer.FrameShaderData };
        constants.Parameters = commandBuffer.Upload(parameters.Ptr, (.)parameters.Length);
        commandBuffer.Dispatch(shader.Programs[programIndex], groups, constants, storage);
    }

    public static void RenderMeshes(RenderCommandBuffer commandBuffer, Matrix4 world, Shader shader, int quadCount, Vector4* instances, int instanceCount,
        Vector4 settings, Vector4 textureScale, GpuTexture[] textures, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0, bool tesselated = false)
    {
        Draw(commandBuffer, shader, programIndex, tesselated ? batchTesselatedVertexBufferHandle : batchVertexBufferHandle,
            tesselated ? batchTesselatedIndexBufferHandle : batchIndexBufferHandle,
            (uint32)(quadCount * (tesselated ? batchTesselatedVertexCount : batchVertexCount)), (uint32)(quadCount * (tesselated ? batchTesselatedIndexCount : batchIndexCount)),
            world, .One, settings, textures, state, sampler, instances, instanceCount, textureScale);
    }

    public static void RenderScreenQuad(RenderCommandBuffer commandBuffer, Shader shader, GpuTexture[] textures, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0)
    {
        Draw(commandBuffer, shader, programIndex, batchVertexBufferHandle, batchIndexBufferHandle, 4, 6, .Identity, .One, .Zero, textures, state, sampler);
    }

    public static void RenderScreenQuad(RenderCommandBuffer commandBuffer, Shader shader, GpuTexture texture, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0)
    {
        RenderScreenQuad(commandBuffer, shader, scope GpuTexture[](texture), state, sampler, programIndex);
    }

    public static void BlitWithShader(RenderCommandBuffer commandBuffer, Shader shader, RenderTexture target, GpuTexture[] textures, RenderState? state = null, SamplerDesc? sampler = null, bool clear = true, int shiftScale = 0, int programIndex = 0)
    {
        var view = commandBuffer;
        if (view.Target != target)
            Runtime.FatalError("Blit target must match the acquired command buffer target");
        view.ClearColorBuffer = clear;
        view.ClearDepthBuffer = clear;
        view.Viewport = .() { width = target.Width >> shiftScale, height = target.Height >> shiftScale };
        view.View = .Identity;
        view.Projection = CreatePerspectiveOrtho(0, view.Viewport.width, 0, view.Viewport.height, 0, 1);
        RenderScreenQuad(commandBuffer, shader, textures, state, sampler, programIndex);
    }

    public static void BlitWithShader(RenderCommandBuffer commandBuffer, Shader shader, RenderTexture target, GpuTexture texture, RenderState? state = null, SamplerDesc? sampler = null, bool clear = true, int shiftScale = 0, int programIndex = 0)
    {
        BlitWithShader(commandBuffer, shader, target, scope GpuTexture[](texture), state, sampler, clear, shiftScale, programIndex);
    }

    public static void RenderFullScreenTextureAspect(RenderCommandBuffer commandBuffer, GpuTexture texture, Shader shader, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0)
    {
        Draw(commandBuffer, shader, programIndex, default, default, 6, 0, .Identity, .One, .Zero, scope GpuTexture[](texture), state.GetValueOrDefault(.Opaque), sampler);
    }

    public static void CreateQuad(int tessX, int tessY, int batchCount, out GpuBuffer outVertexBuffer, out GpuBuffer outIndexBuffer, out int vertsPerBatch, out int indicesPerBatch)
    {
        vertsPerBatch = (tessX + 1) * (tessY + 1);
        indicesPerBatch = tessX * tessY * 6;

        int totalVertCount = vertsPerBatch * batchCount;
        int totalIndexCount = indicesPerBatch * batchCount;

        var vertices = scope Vector3[totalVertCount];
        var indices  = scope uint16[totalIndexCount];

        int v = 0;
        int i = 0;
        float instanceIndex = 0.0f;

        for (int batch = 0; batch < batchCount; batch++,instanceIndex += 4.0f)
        {
            int baseVertex = v;

            // Create vertices for this batch
            for (int y = 0; y <= tessY; y++)
            {
                float fy = (float)y / (float)tessY;
                for (int x = 0; x <= tessX; x++)
                {
                    float fx = (float)x / (float)tessX;
                    vertices[v++] = Vector3(fx, fy, instanceIndex);
                }
            }

            // Create indices for this batch
            for (int ty = 0; ty < tessY; ty++)
            {
                for (int tx = 0; tx < tessX; tx++)
                {
                    uint16 v0 = (uint16)(baseVertex + ty * (tessX + 1) + tx);
                    uint16 v1 = (uint16)(v0 + 1);
                    uint16 v2 = (uint16)(v0 + (tessX + 1));
                    uint16 v3 = (uint16)(v2 + 1);

                    // First triangle
                    indices[i++] = v0;
                    indices[i++] = v1;
                    indices[i++] = v3;

                    // Second triangle
                    indices[i++] = v0;
                    indices[i++] = v3;
                    indices[i++] = v2;
                }
            }
        }

        outVertexBuffer = GpuBuffer.CreateVertices(&vertices[0], (uint32)(vertices.Count * sizeof(Vector3)), batchVertexLayout);
        outIndexBuffer = GpuBuffer.CreateIndices(&indices[0], (uint32)(indices.Count * sizeof(uint16)));
    }

}
