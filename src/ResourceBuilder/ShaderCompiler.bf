using System;
using System.Collections;

namespace GameCore;

public enum ShaderStage
{
    Vertex,
    Fragment
}

public abstract class ShaderCompiler
{
    public abstract StringView OutputExtension { get; }
    public abstract bool CompileStage(StringView source, StringView entryPoint, ShaderStage stage,
        List<String> defines, List<String> includeDirectories, List<uint8> bytecode, String error);

    protected static void AppendArgument(String arguments, StringView argument)
    {
        arguments.Append(" \"");
        int backslashes = 0;
        for (char8 character in argument)
        {
            if (character == '\\') { ++backslashes; continue; }
            arguments.Append('\\', character == '"' ? backslashes * 2 + 1 : backslashes);
            arguments.Append(character);
            backslashes = 0;
        }
        arguments.Append('\\', backslashes * 2);
        arguments.Append('"');
    }
}
