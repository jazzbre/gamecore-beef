using internal GameCore;
using System;
using System.Collections;
using NoGraphicsAPI;

namespace GameCore;

internal struct RenderResourceAccess
{
    public void* Resource;
    public bool IsTexture;
    public Stage Stages;
    public Access Access;
}

internal class RenderResourceTracker
{
    private struct ResourceKey : IHashable, IEquatable<ResourceKey>
    {
        public void* Resource;
        public bool IsTexture;

        public int GetHashCode() => ((int)Resource).GetHashCode() ^ (IsTexture ? 397 : 0);

        public bool Equals(ResourceKey other) => Resource == other.Resource && IsTexture == other.IsTexture;
    }

    private struct ResourceState
    {
        public Stage WriteStages;
        public Access WriteAccess;
        public Stage ReadStages;
        public Access ReadAccess;
        public Stage VisibleReadStages;
        public Access VisibleReadAccess;
    }

    private const Access WriteAccesses = .shader_write | .transfer_write | .color_write | .depth_stencil_write;
    private Dictionary<ResourceKey, ResourceState> states = new .() ~ delete _;
    private List<RenderResourceAccess> accesses = new .() ~ delete _;
    private Stage beforeStages, afterStages;
    private Access beforeAccess, afterAccess;
    private bool externalAccessPending;
    private bool fallbackBarrier;
    private bool reportToManager;
    public uint64 BarrierCount { get; private set; }
    public uint64 FallbackBarrierCount { get; private set; }

    public this(bool reportToManager = true)
    {
        this.reportToManager = reportToManager;
    }

    public void Reset()
    {
        states.Clear();
        accesses.Clear();
        externalAccessPending = false;
        BarrierCount = FallbackBarrierCount = 0;
    }

    public void BeginCommand()
    {
        accesses.Clear();
        beforeStages = afterStages = .none;
        beforeAccess = afterAccess = .none;
        fallbackBarrier = false;
    }

    public void Add(RenderResourceAccess access)
    {
        if (access.Resource == null || access.Access == .none)
            return;
        for (var existing in ref accesses)
        {
            if (existing.Resource == access.Resource && existing.IsTexture == access.IsTexture)
            {
                existing.Stages |= access.Stages;
                existing.Access |= access.Access;
                return;
            }
        }
        accesses.Add(access);
    }

    public void Texture(NoGraphicsAPI.Texture* texture, Stage stages, Access access)
    {
        Add(.() { Resource = texture, IsTexture = true, Stages = stages, Access = access });
    }

    public void Buffer(GpuHeapOwner* owner, Stage stages, Access access)
    {
        Add(.() { Resource = owner, Stages = stages, Access = access });
    }

    public bool Prepare()
    {
        fallbackBarrier = externalAccessPending;
        if (fallbackBarrier)
        {
            states.Clear();
            beforeStages = afterStages = .all_commands;
            beforeAccess = .shader_read | .shader_write | .transfer_read | .transfer_write | .color_write | .depth_stencil_write | .index_read;
            afterAccess = beforeAccess | .color_read | .depth_stencil_read;
        }
        externalAccessPending = false;

        for (var access in accesses)
        {
            ResourceKey key = .() { Resource = access.Resource, IsTexture = access.IsTexture };
            ResourceState previous = default;
            states.TryGetValue(key, out previous);
            bool writes = (access.Access & WriteAccesses) != 0;
            bool readsNeedVisibility = previous.WriteAccess != .none
                && ((access.Stages & ~previous.VisibleReadStages) != 0 || (access.Access & ~previous.VisibleReadAccess) != 0);
            if (writes || readsNeedVisibility)
            {
                Stage sourceStages = previous.WriteStages | (writes ? previous.ReadStages : .none);
                Access sourceAccess = previous.WriteAccess | (writes ? previous.ReadAccess : .none);
                if (sourceStages != .none)
                {
                    beforeStages |= sourceStages;
                    beforeAccess |= sourceAccess;
                    afterStages |= access.Stages;
                    afterAccess |= access.Access;
                }
            }
            if (writes)
            {
                previous = .() { WriteStages = access.Stages, WriteAccess = access.Access };
            }
            else
            {
                previous.ReadStages |= access.Stages;
                previous.ReadAccess |= access.Access;
                previous.VisibleReadStages |= access.Stages;
                previous.VisibleReadAccess |= access.Access;
            }
            states[key] = previous;
        }
        return beforeStages != .none;
    }

    public void Emit(CommandBuffer* commands)
    {
        if (beforeStages == .none)
            return;
        // NGA exposes global barriers; resource histories determine whether and where one is needed.
        GPU.Barrier(commands, beforeStages, beforeAccess, afterStages, afterAccess);
        ++BarrierCount;
        if (fallbackBarrier)
            ++FallbackBarrierCount;
        if (reportToManager)
        {
            ++RenderManager.Synchronization.BarrierCount;
            if (fallbackBarrier)
                ++RenderManager.Synchronization.FallbackBarrierCount;
        }
    }

    public void SynchronizeExternal(CommandBuffer* commands)
    {
        BeginCommand();
        externalAccessPending = true;
        Prepare();
        Emit(commands);
        externalAccessPending = true;
    }

    public void RecordAttachmentWrite(NoGraphicsAPI.Texture* texture, Stage stages, Access access)
    {
        ResourceKey key = .() { Resource = texture, IsTexture = true };
        states[key] = .() { WriteStages = stages, WriteAccess = access };
    }

    public void Forget(void* resource, bool isTexture)
    {
        ResourceKey key = .() { Resource = resource, IsTexture = isTexture };
        states.Remove(key);
    }
}
