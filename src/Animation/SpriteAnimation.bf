using System;
using System.Collections;

namespace Dedkeni
{
	[Flags]
	enum SpriteAnimationFlags
	{
		None = 0,
		Loopable = 1 << 0,
	}

	enum SpriteAnimationEvent : int16
	{
		None,
		Footstep1 = 100,
		Footstep2,
		Footstep3,
		Footstep4,
		Jump1 = 200,
		Jump2,
		Jump3,
		Jump4,
		Land1 = 300,
		Land2,
		Land3,
		Land4,
		Hit1 = 400,
		Hit2,
		Hit3,
		Hit4,
		Collide1 = 500,
		Collide2,
		Collide3,
		Collide4,
		Effect1 = 600,
		Effect2,
		Effect3,
		Effect4,
		Special1 = 700,
		Special2,
		Special3,
		Special4,
		Special5,
		Special6,
		Special7,
		Special8,
	}

	[Flags]
	enum SpriteAnimationEventFlags
	{
		None,
		Loop = 1 << 0,
		End = 1 << 1,
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	class SpriteAnimation
	{
		[JSON_Beef.Serialized]
		public var name = new String() ~ delete _;
		[JSON_Beef.Serialized]
		public var spriteNames = new List<String>() ~ DeleteContainerAndItems!(_);
		[JSON_Beef.Serialized]
		public var events = new List<int16>() ~ delete _;
		[JSON_Beef.Serialized]
		public float frameRate = 10.0f;
		[JSON_Beef.Serialized]
		public SpriteAnimationFlags flags;
		[JSON_Beef.Serialized]
		public int startLoopFrameIndex = 0;
		[JSON_Beef.Serialized]
		public int endLoopFrameIndex = 0;

		public var sprites = new List<Sprite>() ~ DeleteAndNullify!(_);

		public int FrameCount => sprites.Count;

		public bool IsStartLoopEnd => endLoopFrameIndex > startLoopFrameIndex;

		public Sprite this[int index]
		{
			get
			{
				return sprites[index];
			}
			set
			{
				sprites[index] = value;
				if (spriteNames[index] == null)
				{
					spriteNames[index] = new String();
				}
				spriteNames[index].Set(value != null ? value.name : "");
			}
		}

		public void Resize(int count, Sprite emptySprite = null)
		{
			var previousCount = sprites.Count;
			if (count < previousCount)
			{
				for (int i = count; i < previousCount; ++i)
				{
					delete spriteNames[i];
				}
			}
			sprites.Count = count;
			spriteNames.Count = count;
			events.Count = count;
			if (count > previousCount)
			{
				var sprite = previousCount > 0 ? sprites[previousCount - 1] : emptySprite;
				for (int i = previousCount; i < count; ++i)
				{
					this[i] = sprite;
				}
			}
		}

		public void UpdateSprites(bool fill = true)
		{
			sprites.Clear();
			events.Count = spriteNames.Count;
			if (!fill)
			{
				return;
			}
			for (var spriteName in spriteNames)
			{
				var sprite = Sprite.Find(spriteName);
				if (sprite != null)
				{
					sprites.Add(sprite);
				}
			}
		}
	}
}
