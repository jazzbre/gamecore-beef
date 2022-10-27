using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

namespace GameCore
{
	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class SkinnedModel : Resource
	{
		public SkinnedMesh Mesh { get; private set; }
		public Ozz.Skeleton Skeleton { get; private set; }
		public Dictionary<String, Ozz.Animation> Animations { get; private set; }
		public List<Ozz.Animation> AnimationList { get; private set; }

		public struct Header
		{
			public uint32 skeletonSize;
			public uint32 meshSize;
			public uint32 animationCount;
		}

		protected override void OnLoad()
		{
			var binaryFile = scope DynMemStream();
			if (!ResourceManager.ReadFile(scope $"{Hash}.skinnedmodel", binaryFile))
			{
				return;
			}
			var header = binaryFile.Read<Header>().Value;
			if (header.skeletonSize > 0)
			{
				var skeletonData = scope uint8[header.skeletonSize];
				binaryFile.TryRead(skeletonData);
				Skeleton = new Ozz.Skeleton(&skeletonData[0], skeletonData.Count);
			}
			if (header.meshSize > 0)
			{
				Mesh = new SkinnedMesh();
				Mesh.Load(binaryFile, header.meshSize);
			}
			if (header.animationCount > 0)
			{
				Animations = new Dictionary<String, Ozz.Animation>();
				AnimationList = new List<Ozz.Animation>();
				for (int i = 0; i < header.animationCount; ++i)
				{
					var animationName = new String();
					SystemUtils.ReadStrSized32(binaryFile, animationName);
					var animationSize = binaryFile.Read<uint32>().Value;
					var animationData = scope uint8[animationSize];
					binaryFile.TryRead(animationData);
					var animation = new Ozz.Animation(&animationData[0], animationData.Count);
					Animations.Add(animationName, animation);
					AnimationList.Add(animation);
				}
			}
		}

		protected override void OnUnload()
		{
			DeleteAndNullify!(Mesh);
			DeleteAndNullify!(Skeleton);
			DeleteDictionaryAndKeysAndValues!(Animations);
			Animations = null;
			DeleteAndNullify!(AnimationList);
		}

		public void Render(uint16 viewId, Matrix4 _worldMatrix, Shader shader, Vector4* jointMatrices3x4, int jointCount, Vector4 color = .One, Vector4 settings = .Zero, bgfx.TextureHandle[] textureHandles = null, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int programIndex = 0)
		{
			Mesh.Render(viewId, _worldMatrix, shader, jointMatrices3x4, jointCount, color, settings, textureHandles, _stateFlags, _samplerFlags, programIndex);
		}
	}
}