using System;
using System.IO;
using System.Collections;
using Bgfx;

namespace Dedkeni
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class ShaderBuilder : ResourceBuilder
	{
#if RESOURCEBUILD
		class RendererSettings
		{
			public bgfx.RendererType rendererType;
			public String vsFlags = new String() ~ delete _;
			public String fsFlags = new String() ~ delete _;

			public this(bgfx.RendererType _rendererType, char8* _vsFlags, char8* _fsFlags)
			{
				rendererType = _rendererType;
				vsFlags.Set(StringView(_vsFlags));
				fsFlags.Set(StringView(_fsFlags));
			}
		}

		class PlatformSettings
		{
			public RendererSettings[] rendererSettings = null ~ DeleteContainerAndItems!(_);

			public this(params RendererSettings[] settings)
			{
				rendererSettings = new RendererSettings[settings.Count];
				settings.CopyTo(rendererSettings);
			}
		}
		private static var platformSettings = new PlatformSettings[(int)ResourceBuilderPlatform.Last]
			(
			// Windows
			new PlatformSettings(
			new RendererSettings(.Direct3D11, "--platform windows --profile vs_4_0 -O 3", "--platform windows --profile ps_4_0 -O 3"),
			new RendererSettings(.OpenGL, "--platform windows -O 3", "--platform windows -O 3"),
			new RendererSettings(.Vulkan, "--platform linux -p spirv", "--platform linux -p spirv")),
			// Linux
			new PlatformSettings(
			new RendererSettings(.OpenGL, "--platform linux -O 3", "--platform linux -O 3"),
			new RendererSettings(.Vulkan, "--platform linux -p spirv", "--platform linux -p spirv")),
			// macOS
			new PlatformSettings(
			new RendererSettings(.Metal, "--platform osx -p metal -O 3", "--platform osx -p metal -O 3"),
			new RendererSettings(.OpenGL, "--platform osx -O 3", "--platform osx -O 3")),
			// iOS
			new PlatformSettings(
			new RendererSettings(.Metal, "--platform ios -p metal -O 3", "--platform ios -p metal -O 3"),
			new RendererSettings(.OpenGLES, "--platform ios -O 3", "--platform ios -O 3")),
			// Android
			new PlatformSettings(
			new RendererSettings(.OpenGLES, "--platform android -O 3", "--platform android -O 3"),
			new RendererSettings(.Vulkan, "--platform linux -p spirv", "--platform linux -p spirv")),
			) ~ DeleteContainerAndItems!(_);
#endif

		private static readonly String[] ExtensionsStrings = new String[]("shader") ~ delete _;

		public override String[] Extensions => ExtensionsStrings;
		public override Type ResourceType => typeof(Shader);

		public override bool OnCheckBuild(StringView path, StringView hash)
		{
#if RESOURCEBUILD
			var sourceDateTime = SystemUtils.GetLatestTimestamp(path);
			var platformSetting = platformSettings[(int)ResourceManager.ActiveResourceBuilderPlatform];
			for (var rendererSetting in platformSetting.rendererSettings)
			{
				var binaryPath = scope String()..Set(scope $"{ResourceManager.runtimeResourcesPath}{hash}.{rendererSetting.rendererType}.shader");
				var destinationDateTime = SystemUtils.GetLatestTimestamp(binaryPath);
				if (sourceDateTime > destinationDateTime)
				{
					return true;
				}
			}
#endif
			return false;
		}

		public override bool OnBuild(StringView path, StringView hash)
		{
#if RESOURCEBUILD
			var platformSetting = platformSettings[(int)ResourceManager.ActiveResourceBuilderPlatform];
			while (true)
			{
				var success = true;
				for(var rendererSetting in platformSetting.rendererSettings) {
				var binaryPath = scope String()..Set(scope $"{ResourceManager.runtimeResourcesPath}{hash}.{rendererSetting.rendererType}.shader");
					// Open output file
					var binaryFile = scope FileStream();
					switch (binaryFile.Create(binaryPath, .Write)) {
					case .Ok:
						break;
					case .Err:
						return false;
					}
					// Read shader
					var text = scope String();
					switch (File.ReadAllText(path, text)) {
					case .Ok(let val):
						break;
					case .Err(let err):
						return false;
					}
					var definePartIndex = text.IndexOf("[DEF]");
					var vertexShaderPartIndex = text.IndexOf("[VS]");
					var varyingPartIndex = text.IndexOf("[VAR]");
					var fragmentShaderPartIndex = text.IndexOf("[FS]");
					// Parse defines
					var defineNames = scope List<String>();
					defer ClearAndDeleteItems(defineNames);
					var defines = scope List<String>();
					defer ClearAndDeleteItems(defines);
					if (definePartIndex != -1)
					{
						var definePart = scope String(text, definePartIndex + 5, vertexShaderPartIndex - (definePartIndex + 5));
						definePart.Replace(" ", "");
						var buffer = scope String();
						var name = scope String();
						var nameParsed = false;
						for (var i = 0; i < definePart.Length; ++i)
						{
							if (!nameParsed)
							{
								if (definePart[i] == '\n')
								{
									continue;
								}
								if (definePart[i] == '=')
								{
									defineNames.Add(new String()..Append(name));
									name.Clear();
									nameParsed = true;
								} else
								{
									name.Append(definePart[i]);
								}
								continue;
							}
							else if (definePart[i] == '\n' || i == definePart.Length - 1)
							{
								var define = new String();
								for (var split in buffer.Split(',', .RemoveEmptyEntries))
								{
									define.AppendF("{0};", split);
								}
								if (define.Length > 0)
								{
									defines.Add(define);
								} else
								{
									delete define;
								}
								buffer.Clear();
								nameParsed = false;
								continue;
							}
							buffer.Append(definePart[i]);
						}
					}
					if (defines.Count == 0)
					{
						defines.Add(new String());
						defineNames.Add(new String());
					}
					// Parse vertex shader
					if (vertexShaderPartIndex == -1)
					{
						var temp = scope String();
						temp.AppendF("{0} [VS] vertex shader not found!", path);
						if (SystemUtils.ShowMessageBoxOKCancel("Shader Compile", temp) == 1)
						{
							System.Environment.Exit(1);
						}
						continue;
					}
					// Parse varying
					if (varyingPartIndex == -1)
					{
						var temp = scope String();
						temp.AppendF("{0} [VAR] varying not found!", path);
						if (SystemUtils.ShowMessageBoxOKCancel("Shader Compile", temp) == 1)
						{
							System.Environment.Exit(1);
						}
						continue;
					}
					// Parse fragment shader
					if (fragmentShaderPartIndex == -1)
					{
						var temp = scope String();
						temp.AppendF("{0} [FS] fragment shader not found!", path);
						if (SystemUtils.ShowMessageBoxOKCancel("Shader Compile", temp) == 1)
						{
							System.Environment.Exit(1);
						}
						continue;
					}
					binaryFile.Write((int32)defines.Count).IgnoreError();
					for (var defineIndex = 0; defineIndex < defines.Count; ++defineIndex)
					{
						var define = defines[defineIndex];
						var vsPath = scope String()..AppendF("{}{}.vs", ResourceManager.runtimeResourcesPath, hash);
						var vsTextPart = scope String(text, vertexShaderPartIndex + 4, varyingPartIndex - (vertexShaderPartIndex + 4));
						File.WriteAllText(vsPath, vsTextPart);
						var varPath = scope String()..AppendF("{}{}.var", ResourceManager.runtimeResourcesPath, hash);
						var varTextPart = scope String(text, varyingPartIndex + 5, fragmentShaderPartIndex - (varyingPartIndex + 5));
						File.WriteAllText(varPath, varTextPart);
						var fsPath = scope String()..AppendF("{}{}.fs", ResourceManager.runtimeResourcesPath, hash);
						var fsTextPart = scope String(text, fragmentShaderPartIndex + 4, text.Length - (fragmentShaderPartIndex + 4));
						File.WriteAllText(fsPath, fsTextPart);
						var vsBinaryPath = scope $"{vsPath}.bin";
						var fsBinaryPath = scope $"{fsPath}.bin";
						// Build
						var toolPath = scope String();
						toolPath.Set(ResourceManager.buildtimeBgfxToolsPath);
						toolPath.Append("shadercrelease");
						SystemUtils.NormalizePath(toolPath);
						var includePath = scope String();
						includePath.Set(ResourceManager.buildtimeShaderIncludePath);
						var localIncludePath = scope String();
						Path.GetDirectoryPath(path, localIncludePath);
						var commandLine = scope String();
						commandLine.Clear();
						commandLine.AppendF("-f \"{0}\" -o \"{1}\" --type Vertex --varyingdef \"{2}\" -i \"{3}\" -i \"{4}\" {5} --define {6}", vsPath, vsBinaryPath, varPath, includePath, localIncludePath, StringView(rendererSetting.vsFlags), define);
						// Build vertex shader
						var output = scope String();
						var outputError = scope String();
						if (SystemUtils.ExecuteProcess(toolPath, commandLine, output, outputError) != 0)
						{
							if (SystemUtils.ShowMessageBoxOKCancel("Shader Compile", scope $"'{path}' vertex shader compile defines:'{define}'' failed!\n{output}\n{outputError}") == 1)
							{
								System.Environment.Exit(1);
							}
							success = false;
							break;
						}
						Log.Info(output);
						commandLine.Clear();
						commandLine.AppendF("-f \"{0}\" -o \"{1}\" --type Fragment --varyingdef \"{2}\" -i \"{3}\" -i \"{4}\" {5} --define {6}", fsPath, fsBinaryPath, varPath, includePath, localIncludePath, StringView(rendererSetting.fsFlags), define);
						// Build fragment shader
						if (SystemUtils.ExecuteProcess(toolPath, commandLine, output, outputError) != 0)
						{
							if (SystemUtils.ShowMessageBoxOKCancel("Shader Compile", scope $"'{path}' fragment shader compile defines:'{define}'' failed!\n{output}\n{outputError}") == 1)
							{
								System.Environment.Exit(1);
							}
							success = false;
							break;
						}
						Log.Info(output);
						File.Delete(vsPath);
						File.Delete(varPath);
						File.Delete(fsPath);
						if (success)
						{
							// Read binary files
							uint8[] vsBinaryData = null;
							if (!SystemUtils.ReadBinaryFile(vsBinaryPath, out vsBinaryData))
							{
								SystemUtils.ShowMessageBoxOKCancel("Shader Compile", scope $"'{vsBinaryPath}' vertex shader binary failed!");
								System.Environment.Exit(1);
							}
							uint8[] fsBinaryData = null;
							if (!SystemUtils.ReadBinaryFile(fsBinaryPath, out fsBinaryData))
							{
								SystemUtils.ShowMessageBoxOKCancel("Shader Compile", scope $"'{fsBinaryPath}' fragment shader binary failed!");
								System.Environment.Exit(1);
							}
							binaryFile.WriteStrSized32(defineNames[defineIndex]).IgnoreError();
							binaryFile.Write((int32)vsBinaryData.Count);
							binaryFile.TryWrite(Span<uint8>(vsBinaryData, 0, vsBinaryData.Count));
							binaryFile.Write((int32)fsBinaryData.Count);
							binaryFile.TryWrite(Span<uint8>(fsBinaryData, 0, fsBinaryData.Count));
							delete vsBinaryData;
							delete fsBinaryData;
						}
						File.Delete(vsBinaryPath);
						File.Delete(fsBinaryPath);
					}
					if(!success) {
						break;
					}
				}
				if (success)
				{
					break;
				}
			}
#endif
			return true;
		}
	}
}
