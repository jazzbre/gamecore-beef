using System;
using System.Collections;
using System.IO;

namespace Dedkeni
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class SkinnedModelBuilder : ResourceBuilder
	{
		private static readonly String[] ExtensionsStrings = new String[]("fbx") ~ delete _;

		public override String[] Extensions => ExtensionsStrings;
		public override Type ResourceType => typeof(SkinnedModel);

		class ImportAnimation
		{
			public String name = new .() ~ delete _;
			public List<uint8> data = new .() ~ delete _;
		}

		public override bool OnBuild(StringView path, StringView hash)
		{
#if RESOURCEBUILD
			let exportAnimationOnly = path.Contains("_animation.");
			var fbxBinaryPath = scope String()..AppendF("{}{}.skinnedmodel", ResourceManager.runtimeResourcesPath, hash);
			var directory = new String();
			Directory.GetCurrentDirectory(directory);
			defer { Directory.SetCurrentDirectory(directory); delete directory; }
			Directory.SetCurrentDirectory(ResourceManager.buildtimeTemporaryPath);
			var fbxInputFilename = scope String()..Append(scope $"{ResourceManager.buildtimeTemporaryPath}input.fbx");
			var meshInputFilename = scope String()..Append(scope $"{ResourceManager.buildtimeTemporaryPath}mesh.ozz");
			SystemUtils.NormalizePath(meshInputFilename);
			var skeletonInputFilename = scope String()..Append(scope $"{ResourceManager.buildtimeTemporaryPath}skeleton.ozz");
			SystemUtils.NormalizePath(skeletonInputFilename);
			switch (File.Copy(path, fbxInputFilename, true)) {
			case .Err(let err):
				return false;
			default:
				break;
			}
			{
				var toolPath = scope String();
				toolPath.Set(ResourceManager.buildtimeToolsPath);
				toolPath.Append("fbx2ozz");
				SystemUtils.NormalizePath(toolPath);
				var commandLine = scope String();
				commandLine.Clear();
				commandLine.Append(scope $"--file=\"{fbxInputFilename}\"");
				// Build geometry
				if (SystemUtils.ExecuteProcess(toolPath, commandLine) != 0)
				{
					if (SystemUtils.ShowMessageBoxOKCancel("FBX Conversion", scope $"{path} FBX conversion failed!") == 1)
					{
						System.Environment.Exit(1);
					}
					return false;
				}
			}
			if(!exportAnimationOnly)
			{
				var toolPath = scope String();
				toolPath.Set(ResourceManager.buildtimeToolsPath);
				toolPath.Append("sample_fbx2mesh");
				SystemUtils.NormalizePath(toolPath);
				var commandLine = scope String();
				commandLine.Clear();
				commandLine.Append(scope $"--file=\"{fbxInputFilename}\" --mesh=\"{meshInputFilename}\" --skeleton=\"{skeletonInputFilename}\"");
				// Build geometry
				if (SystemUtils.ExecuteProcess(toolPath, commandLine) != 0)
				{
					if (SystemUtils.ShowMessageBoxOKCancel("FBX Conversion", scope $"{path} FBX mesh conversion failed!") == 1)
					{
						System.Environment.Exit(1);
					}
					return false;
				}
			}
			// Build
			var meshData = scope List<uint8>();
			var skeletonData = scope List<uint8>();
			var animations = new List<ImportAnimation>();
			defer { DeleteContainerAndItems!(animations); }
			var files = new List<String>();
			SystemUtils.FindFiles(ResourceManager.buildtimeTemporaryPath, "*.*", ref files);
			defer { DeleteContainerAndItems!(files); }
			for(var file in files) {
				Log.Info(scope $"{file}");
				List<uint8> data = null;
				if(file.EndsWith("mesh.ozz")) {
					if(!exportAnimationOnly) {
						data = meshData;
					}
				} else if(file.EndsWith("skeleton.ozz")) {
					data = skeletonData;
				} else if(file.EndsWith(".ozz")) {
					var importAnimation = new ImportAnimation();
					animations.Add(importAnimation);
					data = importAnimation.data;
					Path.GetFileNameWithoutExtension(file, importAnimation.name);
				}
				if (data != null) {
					switch(File.ReadAll(file, data)) {
					case .Err(let err):
						if (SystemUtils.ShowMessageBoxOKCancel("FBX Conversion", scope $"{path} FBX import failed!") == 1)
						{
							System.Environment.Exit(1);
						}
						return false;
					default:
					}
				}
				//File.Delete(file).IgnoreError();
			}
			var header = SkinnedModel.Header();
			header.skeletonSize = (uint32)skeletonData.Count;
			header.meshSize = (uint32)meshData.Count;
			header.animationCount = (uint32)animations.Count;
			var binaryFile = scope FileStream();
			switch (binaryFile.Create(fbxBinaryPath, .Write)) {
			case .Err:
				if (SystemUtils.ShowMessageBoxOKCancel("FBX Conversion", scope $"{path} FBX save failed!") == 1)
				{
					System.Environment.Exit(1);
				}
				return false;
			default:
			}
			binaryFile.Write(header).IgnoreError();
			if(skeletonData.Count>0) {
				binaryFile.TryWrite(skeletonData);
			}
			if(meshData.Count>0) {
				binaryFile.TryWrite(meshData);
			}
			for(var animation in animations) {
				binaryFile.WriteStrSized32(animation.name);
				binaryFile.Write((uint32)animation.data.Count);
				binaryFile.TryWrite(animation.data);
			}
#endif
			return true;
		}

		public override bool OnCheckBuild(StringView path, StringView hash)
		{
			var objBinaryPath = scope String()..AppendF("{}{}.skinnedmodel", ResourceManager.runtimeResourcesPath, hash);
			var sourceDateTime = SystemUtils.GetLatestTimestamp(path);
			var destinationDateTime = SystemUtils.GetLatestTimestamp(objBinaryPath);
			return sourceDateTime > destinationDateTime;
		}
	}
}