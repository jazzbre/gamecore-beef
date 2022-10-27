using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using SoLoud;

namespace Dedkeni
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class AudioClip : Resource
	{
		public SoloudObject Clip { get; private set; }

		public ~this()
		{
			delete Clip;
		}

		protected override void OnLoad()
		{
			var binaryFile = scope DynMemStream();
			if (!ResourceManager.ReadFile(scope $"{Hash}.ogg", binaryFile))
			{
				return;
			}
			if (Name.EndsWith("_stream"))
			{
				var wav = new WavStream();
				var result = wav.loadMem(binaryFile.Ptr, (uint32)binaryFile.Length, 1, 1);
				Log.Info(scope $"AudioClip load {Name} result {result}!");
				Clip = wav;
			} else
			{
				var wav = new Wav();
				var result = wav.loadMem(binaryFile.Ptr, (uint32)binaryFile.Length, 1, 1);
				Log.Info(scope $"AudioClip load {Name} result {result}!");
				Clip = wav;
			}
		}

		protected override void OnUnload()
		{
			DeleteAndNullify!(Clip);
		}
	}
}
