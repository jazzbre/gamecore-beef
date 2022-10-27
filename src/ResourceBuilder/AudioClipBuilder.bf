using System;
using System.Collections;
using System.IO;

namespace GameCore
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class AudioClipBuilder : ResourceBuilder
	{
		private static readonly String[] ExtensionsStrings = new String[]("ogg", "wav", "mp3", "flac", "aif") ~ delete _;

		public override String[] Extensions => ExtensionsStrings;

		public override Type ResourceType => typeof(AudioClip);

		public override bool OnBuild(StringView path, StringView hash)
		{
#if RESOURCEBUILD
			var oggBinaryPath = scope String()..AppendF("{}{}.ogg", ResourceManager.runtimeResourcesPath, hash);
			/*
			if( path.Contains("_loop")) {
				SystemUtils.FileCopy(path, oggBinaryPath);
				return true;
			}*/
			// Build
			var toolPath = scope String();
			toolPath.Set(ResourceManager.buildtimeToolsPath);
			toolPath.Append("ffmpeg");
			SystemUtils.NormalizePath(toolPath);
			var filter = path.Contains("_stream") || path.Contains("_loop") ? "" : scope $"-filter_complex \"areverse, afade=d=0.05, areverse\"";
			var commandLine = scope $"-y -i \"{path}\" -c:a libvorbis -aq 1 -ab 32k -ar 22050 {filter} \"{oggBinaryPath}\"";
			// Build vertex shader
			if (SystemUtils.ExecuteProcess(toolPath, commandLine) != 0)
			{
				if (SystemUtils.ShowMessageBoxOKCancel("Audio Convert", scope $"'{path}' audio convert failed!") == 1)
				{
					System.Environment.Exit(1);
				}
			}
#endif
			return true;
		}

		public override bool OnCheckBuild(StringView path, StringView hash)
		{
			var oggBinaryPath = scope String()..AppendF("{}{}.ogg", ResourceManager.runtimeResourcesPath, hash);
			var sourceDateTime = SystemUtils.GetLatestTimestamp(path);
			var destinationDateTime = SystemUtils.GetLatestTimestamp(oggBinaryPath);
			return sourceDateTime > destinationDateTime;
		}
	}
}