using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

namespace GameCore
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class Shader : Resource
	{
		public List<bgfx.ProgramHandle> Programs { get; private set; }
		private var nameToIndex = new Dictionary<String, int>() ~ delete _;

		this()
		{
			Programs = new List<bgfx.ProgramHandle>();
		}

		~this()
		{
			delete Programs;
		}

		public int FindHandleIndex(String name)
		{
			int index = -1;
			nameToIndex.TryGetValue(name, out index);
			return index;
		}

		protected override void OnLoad()
		{
			var binaryFile = scope DynMemStream();
			if (!ResourceManager.ReadFile(scope $"{Hash}.{RenderManager.ShaderRendererType}.shader", binaryFile))
			{
				return;
			}
			int32 defineCount = binaryFile.Read<int32>().Value;
			var data = scope List<uint8>();
			for (int defineIndex = 0; defineIndex < defineCount; ++defineIndex)
			{
				var defineName = new String();
				SystemUtils.ReadStrSized32(binaryFile, defineName);
				nameToIndex.Add(defineName, Programs.Count);

				int32 vsSize = binaryFile.Read<int32>().Value;
				data.Count = vsSize;
				binaryFile.TryRead(Span<uint8>(data.Ptr, vsSize));

				var vsMemory = bgfx.copy(data.Ptr, (uint32)vsSize);
				var vsHandle = bgfx.create_shader(vsMemory);

				int32 fsSize = binaryFile.Read<int32>().Value;
				data.Count = fsSize;
				binaryFile.TryRead(Span<uint8>(data.Ptr, fsSize));

				var fsMemory = bgfx.copy(data.Ptr, (uint32)fsSize);
				var fsHandle = bgfx.create_shader(fsMemory);

				var handle = bgfx.create_program(vsHandle, fsHandle, true);
				Programs.Add(handle);
			}
		}

		protected override void OnUnload()
		{
			for (var handle in Programs)
			{
				if (handle.idx == uint16.MaxValue)
				{
					continue;
				}
				bgfx.destroy_program(handle);
			}
			Programs.Clear();
			for (var pair in nameToIndex)
			{
				delete pair.key;
			}
			nameToIndex.Clear();
		}
	}
}
