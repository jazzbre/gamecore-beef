using System;
using System.Collections;
using System.IO;

namespace Dedkeni
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class ModelBuilder : ResourceBuilder
	{
		private static readonly String[] ExtensionsStrings = new String[]("obj") ~ delete _;

		public override String[] Extensions => ExtensionsStrings;
		public override Type ResourceType => typeof(Model);

		public override bool OnBuild(StringView path, StringView hash)
		{
#if RESOURCEBUILD
			var objBinaryPath = scope String()..AppendF("{}{}.model", ResourceManager.runtimeResourcesPath, hash);
			var toolPath = scope String();
			toolPath.Set(ResourceManager.buildtimeBgfxToolsPath);
			toolPath.Append("geometrycrelease");
			SystemUtils.NormalizePath(toolPath);
			var commandLine = scope String();
			commandLine.Clear();
			commandLine.AppendF("-f \"{0}\" -o \"{1}\"", path, objBinaryPath);
			// Build geometry
			if (SystemUtils.ExecuteProcess(toolPath, commandLine) != 0)
			{
				var temp = scope String();
				temp.AppendF("{0} texture conversion failed!", path);
				if (SystemUtils.ShowMessageBoxOKCancel("Texture Conversion", temp) == 1)
				{
					System.Environment.Exit(1);
				}
			}
#endif
			return true;
		}

		public override bool OnCheckBuild(StringView path, StringView hash)
		{
			var objBinaryPath = scope String()..AppendF("{}{}.model", ResourceManager.runtimeResourcesPath, hash);
			var sourceDateTime = SystemUtils.GetLatestTimestamp(path);
			var destinationDateTime = SystemUtils.GetLatestTimestamp(objBinaryPath);
			return sourceDateTime > destinationDateTime;
		}
	}
}