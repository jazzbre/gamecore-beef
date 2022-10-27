using System;

namespace GameCore
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	class JsonResourceBuilder : ResourceBuilder
	{
		private static readonly String[] ExtensionsStrings = new String[]("json") ~ delete _;
		public override String[] Extensions => ExtensionsStrings;
		public override Type ResourceType => typeof(JsonResource);

		public override bool OnBuild(StringView path, StringView hash)
		{
			var jsonPath = scope String()..AppendF("{}{}.json", ResourceManager.runtimeResourcesPath, hash);
			SystemUtils.FileCopy(path, jsonPath, true);
			return default;
		}

		public override bool OnCheckBuild(StringView path, StringView hash)
		{
			var jsonPath = scope String()..AppendF("{}{}.json", ResourceManager.runtimeResourcesPath, hash);
			var sourceDateTime = SystemUtils.GetLatestTimestamp(path);
			var destinationDateTime = SystemUtils.GetLatestTimestamp(jsonPath);
			return sourceDateTime > destinationDateTime;
		}
	}
}
