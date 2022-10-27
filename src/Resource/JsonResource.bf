using System;

namespace Dedkeni
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	class JsonResource : Resource
	{
		private var jsonName = new String() ~ delete _;

		public String JsonName => jsonName;

		public override void Initialize(System.String name, System.String hash)
		{
			jsonName.Set(scope $"{hash}.json");
			base.Initialize(name, hash);
		}

		protected override void OnLoad()
		{
		}

		protected override void OnUnload()
		{
		}
	}
}
