using System;
using System.Collections;
using System.IO;

namespace GameCore;

[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
public class Shader : Resource
{
    public List<ShaderProgram> Programs = new .() ~ DeleteContainerAndItems!(_);
    private Dictionary<String, int> nameToIndex = new .() ~ delete _;
    public ~this() { OnUnload(); }
    public int FindHandleIndex(String name) { return nameToIndex.TryGetValue(name, let index) ? index : -1; }
    public bool LoadCompiledFile(StringView path)
    {
        var stream = scope FileStream();
        if (stream.Open(path, .Read) case .Err) return false;
        return ReadPrograms(stream);
    }
    private bool ReadPrograms(Stream stream)
    {
        OnUnload();
        if (!(stream.Read<int32>() case .Ok(let count)) || count <= 0 || count > 256) return false;
        for (int index = 0; index < count; ++index)
        {
            var name = new String();
            SystemUtils.ReadStrSized32(stream, name);
            var program = new ShaderProgram();
            if (!ReadStage(stream, program.VertexCode) || !ReadStage(stream, program.FragmentCode))
            { delete name; delete program; OnUnload(); return false; }
            nameToIndex.Add(name, Programs.Count); Programs.Add(program);
        }
        return true;
    }
    private bool ReadStage(Stream stream, List<uint32> code)
    {
        if (!(stream.Read<int32>() case .Ok(let size)) || size < 4 || size > 64 * 1024 * 1024 || (size & 3) != 0) return false;
        code.Count = size / 4;
        if (stream.TryRead(.((uint8*)code.Ptr, size)) case .Err) return false;
        return code[0] == 0x43425844;
    }
    protected override void OnLoad()
    {
        var stream = scope DynMemStream();
        if (ResourceManager.ReadFile(scope $"{Hash}.Direct3D12.shader", stream)) ReadPrograms(stream);
    }
    protected override void OnUnload()
    {
        for (var program in Programs) delete program;
        Programs.Clear();
        for (var entry in nameToIndex) delete entry.key;
        nameToIndex.Clear();
    }
}
