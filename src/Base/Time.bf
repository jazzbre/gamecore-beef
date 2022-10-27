using System;
using System.Collections;
using SDL2;

namespace GameCore
{
	public static class Time
	{
		private static double startTime = -1.0;
		private static var deltaTimes = new List<float>() ~ delete _;
		private static double ooFrequency = 0.0f;

		public static float FixedFrameTime { get; set; }

		public static double RealTime => (double)SDL.GetPerformanceCounter() * ooFrequency;

		public static float TimeScale { get; set; }
		public static double Time { get; private set; }
		public static double ScaledTime { get; private set; }
		public static float DeltaTime { get; private set; }
		public static uint FrameCounter { get; private set; }
		public static int SmoothCount { get; set; }

		public static float MaxDeltaTime { get; set; }

		public static this()
		{
			ooFrequency = 1.0 / (double)SDL.GetPerformanceFrequency();
			TimeScale = 1.0f;
			SmoothCount = 10;
			MaxDeltaTime = 1.0f / 10.0f;
		}

		public static void Update()
		{
			++FrameCounter;
			var newTime = RealTime;
			if (startTime < 0.0)
			{
				startTime = newTime;
			}
			newTime -= startTime;
			if (Time > 0.0)
			{
				var deltaTime = (float)(newTime - Time);
				deltaTime = Math.Min(MaxDeltaTime, deltaTime);
				while (deltaTimes.Count >= SmoothCount)
				{
					deltaTimes.PopFront();
				}
				deltaTimes.Add(deltaTime);
				if (FixedFrameTime > 0)
				{
					DeltaTime = FixedFrameTime;
				} else
				{
					DeltaTime = 0.0f;
					for (var delta in deltaTimes)
					{
						DeltaTime += delta;
					}
					DeltaTime /= (float)deltaTimes.Count;
					DeltaTime *= TimeScale;
				}
			}
			Time = newTime;
			ScaledTime += DeltaTime;
		}
	}
}
