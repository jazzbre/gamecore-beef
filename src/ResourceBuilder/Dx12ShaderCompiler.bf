using System;
using System.Collections;
using System.IO;

namespace GameCore;

public class Dx12ShaderCompiler : ShaderCompiler
{
    public String SlangExecutable = new .("slangc") ~ delete _;
    public override StringView OutputExtension => ".Direct3D12.shader";

    public override bool CompileStage(StringView source, StringView entryPoint, ShaderStage stage,
        List<String> defines, List<String> includeDirectories, List<uint8> bytecode, String error)
    {
        bytecode.Clear();
        var temporaryPath = scope String();
        if (Path.GetTempFileName(temporaryPath) case .Err || temporaryPath.IsEmpty)
        {
            error.Set("Cannot create temporary shader file");
            return false;
        }
        defer File.Delete(temporaryPath);
        var arguments = scope String();
        AppendArgument(arguments, source);
        arguments.Append(" -target dxil -profile sm_6_6 -DNGA_D3D12=1 -matrix-layout-row-major -entry");
        AppendArgument(arguments, entryPoint);
        arguments.Append(stage == .Vertex ? " -stage vertex -o" : stage == .Compute ? " -stage compute -o" : " -stage fragment -o");
        AppendArgument(arguments, temporaryPath);
        arguments.Append(stage == .Vertex ? " -DGAMECORE_STAGE_VERTEX=1" : stage == .Compute ? " -DGAMECORE_STAGE_COMPUTE=1" : " -DGAMECORE_STAGE_FRAGMENT=1");
        for (var directory in includeDirectories)
        {
            arguments.Append(" -I");
            AppendArgument(arguments, directory);
        }
        for (var define in defines)
            AppendArgument(arguments, scope $"-D{define}");
        // Inherit compiler output so diagnostics cannot fill an unread redirected pipe.
        if (SystemUtils.ExecuteProcess(SlangExecutable, arguments) != 0)
        {
            error.Set(scope $"Slang failed for {source}, {entryPoint} ({stage})");
            return false;
        }
        if (File.ReadAll(temporaryPath, bytecode) case .Err)
        {
            error.Set("Cannot read compiled shader");
            return false;
        }
        if (bytecode.Count < 4 || (bytecode.Count & 3) != 0 ||
            bytecode[0] != 'D' || bytecode[1] != 'X' || bytecode[2] != 'B' || bytecode[3] != 'C')
        {
            error.Set("Slang did not produce a DXIL container");
            return false;
        }
        return true;
    }
}
