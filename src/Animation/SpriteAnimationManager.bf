using System;
using System.Collections;

namespace GameCore
{
	static class SpriteAnimationManager
	{
		private const StringView defaultFileName = "data/spriteanimationlist";

		private static var spriteAnimations = new Dictionary<String, SpriteAnimation>() ~ delete _;
		private static var spriteAnimationList = new SpriteAnimationList() ~ delete _;

		public static List<SpriteAnimation> SpriteAnimations => spriteAnimationList.spriteAnimations;

		public static SpriteAnimation Add(String name, String spriteName, int frameCount, float frameRate = 10.0f, SpriteAnimationFlags flags = .Loopable)
		{
			let sprite = Sprite.Find(spriteName);
			if (sprite == null)
			{
				return null;
			}
			// Check
			if (sprite.index + frameCount > sprite.texture.SpriteAtlas.sprites.Count)
			{
				return null;
			}
			// Add
			var spriteAnimation = new SpriteAnimation();
			for (var i = 0; i < frameCount; ++i)
			{
				var spriteFrame = sprite.texture.SpriteAtlas.sprites[sprite.index + i];
				spriteAnimation.spriteNames.Add(new String()..Set(spriteFrame.name));
				spriteAnimation.sprites.Add(spriteFrame);
			}
			spriteAnimation.name.Set(name);
			spriteAnimation.frameRate = frameRate;
			spriteAnimation.flags = flags;
			spriteAnimations.Add(name, spriteAnimation);
			spriteAnimationList.spriteAnimations.Add(spriteAnimation);
			return spriteAnimation;
		}

		public static SpriteAnimation Find(String name)
		{
			if (name.Length == 0)
			{
				return null;
			}
			if (spriteAnimations.Count == 0)
			{
				return null;
			}
			SpriteAnimation spriteAnimation = null;
			spriteAnimations.TryGetValue(name, out spriteAnimation);
			if (spriteAnimation == null)
			{
				Log.Error(scope $"Couldn't find animation {name}!");
			}
			return spriteAnimation;
		}

		static void UpdateDictionary()
		{
			// Fill to dictionary
			spriteAnimations.Clear();
			for (var spriteAnimation in spriteAnimationList.spriteAnimations)
			{
				spriteAnimation.UpdateSprites();
				spriteAnimations.TryAdd(spriteAnimation.name, spriteAnimation);
			}
		}

		public static void SaveEditor()
		{
			spriteAnimationList.Save(scope $"{ResourceManager.buildtimeResourcesPath}/{defaultFileName}.json");
			UpdateDictionary();
		}

		public static void OnInitialize()
		{
			var resource = ResourceManager.GetResource<JsonResource>(defaultFileName);
			if (resource != null)
			{
				spriteAnimationList.Load(resource.JsonName);
				UpdateDictionary();
			}
		}

		public static void OnFinalize()
		{
		}

	}
}
