using System;
using System.Collections;

namespace GameCore
{
	enum CollisionType
	{
		World,
		WorldUp,
		Player,
		Enemy,
		Pushable,
		Package,
		Area,
		Action,
		Dynamic,
		Water,
		PickUp,
	}

	enum CollisionCategory : uint32
	{
		Default = 1 << 0,
		Player = 1 << 1,
		Tile = 1 << 2,
		Enemy = 1 << 3,
		Danger = 1 << 4,
		Pushable = 1 << 5,
		Ignore = 1 << 6,
		Bounds = 1 << 7,
		Area = 1 << 8,
	}

	static class PhysicsManager
	{
		static Chipmunk2D.Space physicsSpace = new Chipmunk2D.Space() ~ delete _;
		static var frameRate = ConstantFrameRate(1.0f / 180.0f);

		static PhysicsDebugDraw debugDraw = new PhysicsDebugDraw() ~ delete _;

		public static Chipmunk2D.Space PhysicsSpace => physicsSpace;
		public static bool IsDebugDrawEnabled = false;

		public static delegate void(float deltaTime) OnPostStepCallback = null ~ delete _;

		public static bool Initialize()
		{
			physicsSpace.Iterations = 10;
			physicsSpace.CollisionBias = Math.Pow(0.5, 60.0);
			physicsSpace.CollisionSlop = 0.5;
			physicsSpace.Gravity = .(0, -2000.0);
			physicsSpace.SleepTimeThreshold = 0.5;

			debugDraw.Initialize();

			// Setup debug draw
			return true;
		}

		public static void Finalize()
		{
		}

		public static void Update(float deltaTime)
		{
			var count = frameRate.Update(deltaTime);
			while (count-- > 0)
			{
				physicsSpace.Step(frameRate.DeltaTime);
				if (OnPostStepCallback != null)
				{
					OnPostStepCallback(frameRate.DeltaTime);
				}
			}

			if (IsDebugDrawEnabled)
			{
				debugDraw.DebugDraw(physicsSpace);
			}
		}
	}
}
