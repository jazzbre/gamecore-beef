using System;
using System.Collections;

namespace Dedkeni
{
	class SpriteAnimationController
	{
		public struct Event
		{
			public int frameIndex;
			public SpriteAnimationEvent event;
			public SpriteAnimationEventFlags flags;
		}

		private SpriteAnimation activeSpriteAnimation = null;
		private int activeFrameIndex = 0;
		private float activeFrame = 0.0f;
		private var event = Event();
		private bool firstFrame = false;

		public SpriteAnimation ActiveSpriteAnimation => activeSpriteAnimation;
		public float Speed { get; set; }
		public int Frame => activeFrameIndex;

		public this()
		{
			Speed = 1;
		}

		public Sprite Sprite
		{
			get
			{
				if (activeSpriteAnimation == null)
				{
					return null;
				}
				return activeSpriteAnimation[activeFrameIndex];
			}
		}

		public Event ActiveEvent => event;

		public void SetFrame(int frame)
		{
			if (activeSpriteAnimation == null)
			{
				return;
			}
			if (activeSpriteAnimation.FrameCount == 0)
			{
				return;
			}
			activeFrame = activeFrameIndex = frame % activeSpriteAnimation.FrameCount;
		}

		public bool Play(SpriteAnimation spriteAnimation, bool restart = false)
		{
			if (spriteAnimation == null)
			{
				Stop();
				return false;
			}
			if (!restart && activeSpriteAnimation == spriteAnimation && (spriteAnimation != null && (spriteAnimation.flags & .Loopable) != 0))
			{
				return true;
			}
			activeSpriteAnimation = spriteAnimation;
			activeFrameIndex = 0;
			activeFrame = 0.0f;
			firstFrame = true;
			Update(0.0f);
			return true;
		}

		public void Stop()
		{
			activeSpriteAnimation = null;
			event = .();
		}

		public bool Update(float deltaTime)
		{
			if (activeSpriteAnimation == null)
			{
				return false;
			}
			let previousFrameIndex = activeFrameIndex;
			event = .();
			activeFrameIndex = (int)Math.Floor(activeFrame);
			activeFrame += deltaTime * activeSpriteAnimation.frameRate * Speed;
			var startFrameIndex = 0;
			var endFrameIndex = activeSpriteAnimation.FrameCount;
			if (activeSpriteAnimation.IsStartLoopEnd)
			{
				startFrameIndex = activeSpriteAnimation.startLoopFrameIndex;
				endFrameIndex = activeSpriteAnimation.endLoopFrameIndex;
			}
			var result = false;
			if (Speed > 0)
			{
				if (activeFrame >= endFrameIndex)
				{
					if ((activeSpriteAnimation.flags & .Loopable) != 0)
					{
						activeFrame = startFrameIndex;
						event.flags |= .Loop;
					} else
					{
						activeFrame = endFrameIndex - 1;
						event.flags |= .End;
						result = true;
					}
				}
			} else if (Speed < 0)
			{
				if (activeFrame <= startFrameIndex)
				{
					if ((activeSpriteAnimation.flags & .Loopable) != 0)
					{
						activeFrame = endFrameIndex - 1;
						event.flags |= .Loop;
					} else
					{
						activeFrame = startFrameIndex;
						event.flags |= .End;
						result = true;
					}
				}
			}
			// Add event
			if ((firstFrame || previousFrameIndex != activeFrameIndex) && activeFrameIndex < activeSpriteAnimation.events.Count && activeSpriteAnimation.events[activeFrameIndex] != 0)
			{
				event.event = (.)activeSpriteAnimation.events[activeFrameIndex];
			}
			firstFrame = false;
			return result;
		}

	}
}
