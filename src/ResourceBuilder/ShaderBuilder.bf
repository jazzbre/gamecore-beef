using System;
using System.Collections;
using System.IO;
using JSON_Beef.Serialization;
using JSON_Beef.Types;

namespace GameCore;

[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
public class ShaderBuilder : ResourceBuilder
{
    private static readonly String[] ExtensionsStrings = new String[]("slang") ~ delete _;
    private Dx12ShaderCompiler dx12Compiler = new .() ~ delete _;
    private List<String> includeDirectories = new .() ~ DeleteContainerAndItems!(_);
    private HashSet<String> visitedDependencies = new .() ~ DeleteContainerAndItems!(_);
    private HashSet<String> variantNames = new .() ~ delete _;
    private List<String> variantDefines = new .() ~ delete _;
    private List<uint8> stageBytecode = new .() ~ delete _;
    private List<uint8> packageBytes = new .() ~ delete _;
    public String Error = new .() ~ delete _;
    public override String[] Extensions => ExtensionsStrings;
    public override Type ResourceType => typeof(Shader);

    public static bool IsSharedInclude(StringView path)
    {
        var fileName = scope String();
        Path.GetFileName(path, fileName);
        return fileName.Equals("gamecore.slang", .OrdinalIgnoreCase);
    }

    private ShaderCompiler SelectCompiler(ResourceBuilderPlatform platform)
    {
        switch (platform)
        {
        case .Windows: return dx12Compiler;
        default: Error.Set(scope $"Shader compilation is not implemented for {platform}"); return null;
        }
    }

    public override bool OnCheckBuild(StringView path, StringView hash)
    {
#if RESOURCEBUILD
        let compiler = SelectCompiler(ResourceManager.ActiveResourceBuilderPlatform);
        if (compiler == null) return true;
        return NeedsBuild(path, scope $"{ResourceManager.runtimeResourcesPath}{hash}{compiler.OutputExtension}",
            ResourceManager.buildtimeNgaShaderIncludePath);
#else
        return false;
#endif
    }

    public override bool OnBuild(StringView path, StringView hash)
    {
#if RESOURCEBUILD
        let compiler = SelectCompiler(ResourceManager.ActiveResourceBuilderPlatform);
        if (compiler == null) return false;
        if (!BuildFile(path, scope $"{ResourceManager.runtimeResourcesPath}{hash}{compiler.OutputExtension}",
            ResourceManager.buildtimeNgaShaderIncludePath, compiler))
        { Log.Info(scope $"Shader compilation failed: {path}\n{Error}"); return false; }
        return true;
#else
        return false;
#endif
    }

    private void ConfigureIncludes(StringView platformIncludeDirectory)
    {
        for (var directory in includeDirectories) delete directory;
        includeDirectories.Clear();
        var platformPath = new String();
        Path.GetFullPath(platformIncludeDirectory, platformPath);
        includeDirectories.Add(platformPath);
    }

    public bool NeedsBuild(StringView source, StringView output, StringView platformIncludeDirectory)
    {
        Error.Clear();
        ConfigureIncludes(platformIncludeDirectory);
        for (var dependency in visitedDependencies) delete dependency;
        visitedDependencies.Clear();
        if (!(File.GetLastWriteTimeUtc(output) case .Ok(let outputTime))) return true;
        var manifest = scope $"{source}.json";
        if (File.Exists(manifest) && (!(File.GetLastWriteTimeUtc(manifest) case .Ok(let manifestTime)) || manifestTime > outputTime)) return true;
        var executable = scope String();
        Environment.GetExecutableFilePath(executable);
        if (File.GetLastWriteTimeUtc(executable) case .Ok(let executableTime))
            if (executableTime > outputTime) return true;
        return DependencyNeedsBuild(source, outputTime);
    }

    private bool DependencyNeedsBuild(StringView path, DateTime outputTime)
    {
        var fullPath = scope String();
        Path.GetFullPath(path, fullPath);
#if BF_PLATFORM_WINDOWS
        fullPath.ToLower();
#endif
        if (visitedDependencies.Contains(fullPath)) return false;
        visitedDependencies.Add(new String(fullPath));
        if (!(File.GetLastWriteTimeUtc(fullPath) case .Ok(let inputTime)))
        { Error.Set(scope $"Cannot read shader dependency: {path}"); return true; }
        if (inputTime > outputTime) return true;
        var text = scope String();
        if (File.ReadAllText(fullPath, text) case .Err)
        { Error.Set(scope $"Cannot read shader dependency: {path}"); return true; }
        var sourceDirectory = scope String();
        Path.GetDirectoryPath(fullPath, sourceDirectory);
        for (var line in text.Split('\n'))
        {
            var directive = line;
            directive.Trim();
            if (!directive.StartsWith('#')) continue;
            directive.RemoveFromStart(1);
            directive.TrimStart();
            if (!directive.StartsWith("include")) continue;
            directive.RemoveFromStart(7);
            directive.TrimStart();
            if (directive.IsEmpty || (directive[0] != '"' && directive[0] != '<')) continue;
            char8 closing = directive[0] == '"' ? '"' : '>';
            int end = directive.IndexOf(closing, 1);
            if (end < 0) { Error.Set(scope $"Invalid include in {path}"); return true; }
            var includeName = directive.Substring(1, end - 1);
            var includePath = scope $"{sourceDirectory}/{includeName}";
            if (!File.Exists(includePath))
            {
                for (var directory in includeDirectories)
                {
                    includePath.Set(scope $"{directory}/{includeName}");
                    if (File.Exists(includePath)) break;
                }
            }
            if (DependencyNeedsBuild(includePath, outputTime)) return true;
        }
        return false;
    }

    private bool GetEntryPoint(JSONObject variant, String key, String defaultEntryPoint, out String entryPoint)
    {
        entryPoint = defaultEntryPoint;
        if (variant == null || !variant.ContainsKey(key)) return true;
        if (variant.Get<String>(key, ref entryPoint) case .Err || entryPoint == null || entryPoint.IsEmpty)
        { Error.Set(scope $"Invalid {key} entry point"); return false; }
        return true;
    }

    private bool CompileVariant(StringView source, JSONObject variant, ShaderCompiler compiler, DynMemStream package)
    {
        String name = "Default";
        variantDefines.Clear();
        if (variant != null)
        {
            if (variant.Get<String>("name", ref name) case .Err || name == null || name.IsEmpty)
            { Error.Set("Shader variant requires a nonempty name"); return false; }
            if (variant.ContainsKey("defines"))
            {
                JSONArray defines = null;
                if (variant.Get<JSONArray>("defines", ref defines) case .Err || defines == null)
                { Error.Set("Shader variant defines must be an array"); return false; }
                for (int index = 0; index < defines.Count; ++index)
                {
                    String define = null;
                    if (defines.Get<String>(index, ref define) != .OK || define == null)
                    { Error.Set("Shader defines must be strings"); return false; }
                    variantDefines.Add(define);
                }
            }
        }
        if (!variantNames.Add(name)) { Error.Set(scope $"Duplicate shader variant: {name}"); return false; }
        package.Write<int32>((.)name.Length);
        package.TryWrite(.((uint8*)name.Ptr, name.Length));
        if (!GetEntryPoint(variant, "vertex", "vertexMain", let vertexEntry)) return false;
        if (!GetEntryPoint(variant, "fragment", "fragmentMain", let fragmentEntry)) return false;
        for (int stageIndex = 0; stageIndex < 2; ++stageIndex)
        {
            ShaderStage stage = stageIndex == 0 ? .Vertex : .Fragment;
            if (!compiler.CompileStage(source, stage == .Vertex ? vertexEntry : fragmentEntry, stage,
                variantDefines, includeDirectories, stageBytecode, Error)) return false;
            package.Write<int32>((.)stageBytecode.Count);
            package.TryWrite(stageBytecode);
        }
        return true;
    }

    public bool BuildFile(StringView source, StringView output, StringView platformIncludeDirectory, ShaderCompiler compiler = null)
    {
        Error.Clear();
        if (!source.EndsWith(".slang")) { Error.Set("Shader sources must be native .slang files"); return false; }
        ConfigureIncludes(platformIncludeDirectory);
        var selectedCompiler = compiler ?? dx12Compiler;
        variantNames.Clear();
        defer variantNames.Clear();
        defer variantDefines.Clear();
        packageBytes.Clear();
        var package = scope DynMemStream(packageBytes);
        var manifestPath = scope $"{source}.json";
        var manifest = scope JSONObject();
        JSONArray variants = null;
        if (File.Exists(manifestPath))
        {
            var json = scope String();
            if (File.ReadAllText(manifestPath, json) case .Err)
            { Error.Set("Cannot read shader variant manifest"); return false; }
            json.Trim();
            if (json.IsEmpty || !JSONParser.IsValidJson(json) || JSONParser.ParseObject(json, ref manifest) case .Err)
            { Error.Set("Invalid shader variant manifest"); return false; }
            if (manifest.Get<JSONArray>("variants", ref variants) case .Err || variants == null || variants.Count < 1 || variants.Count > 256)
            { Error.Set("Expected between 1 and 256 shader variants"); return false; }
        }
        int count = variants == null ? 1 : variants.Count;
        package.Write<int32>((.)count);
        for (int index = 0; index < count; ++index)
        {
            JSONObject variant = null;
            if (variants != null && (variants.Get<JSONObject>(index, ref variant) != .OK || variant == null))
            { Error.Set("Shader variant must be an object"); return false; }
            if (!CompileVariant(source, variant, selectedCompiler, package)) return false;
        }
        var outputDirectory = scope String();
        Path.GetDirectoryPath(output, outputDirectory);
        if (!outputDirectory.IsEmpty && Directory.CreateDirectory(outputDirectory) case .Err)
        { Error.Set("Cannot create shader output directory"); return false; }
        if (File.WriteAll(output, packageBytes) case .Err)
        { Error.Set("Cannot write shader package"); return false; }
        return true;
    }
}
