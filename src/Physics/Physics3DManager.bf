using System;
using System.Collections;
#if USEPHYSX
using PhysX;
#endif

namespace GameCore
{
	static class Physics3DManager
	{
		#if USEPHYSX
		public static PxFoundation* Foundation { get; private set; };
		public static PxDefaultCpuDispatcher* Dispatcher { get; private set; };
		public static PxPhysics* Physics { get; private set; };
		public static PxScene* Scene { get; private set; };
		#endif

		static Physics3DDebugDraw debugDraw = new Physics3DDebugDraw() ~ delete _;
		public static bool IsDebugDrawEnabled = false;

		static var frameRate = ConstantFrameRate(1.0f / 60.0f);


		public static bool Initialize()
		{
			#if USEPHYSX
			Foundation = PhysXAPI.create_foundation();
			Physics = PhysXAPI.create_physics(Foundation);

			Dispatcher = PhysXAPI.DefaultCpuDispatcherCreate(2, null);

			var sceneDesc = PhysX.PxSceneDesc();
			sceneDesc.gravity = PxVec3() { x = 0.0f, y = 0.0f, z = 0.0f };
			sceneDesc.cpuDispatcher = (PxCpuDispatcher*)Dispatcher;
			sceneDesc.filterShader = PhysXAPI.get_default_simulation_filter_shader();
			sceneDesc.tolerancesScale = *PhysXAPI.Physics_getTolerancesScale(Physics);
			Scene = PhysXAPI.Physics_createScene_mut(Physics, &sceneDesc);
			#endif
			debugDraw.Initialize();

			return true;
		}

		public static void Finalize()
		{
			#if USEPHYSX
			PhysXAPI.Scene_release_mut(Scene);
			PhysXAPI.DefaultCpuDispatcher_release_mut(Dispatcher);
			PhysXAPI.Physics_release_mut(Physics);
			PhysXAPI.Foundation_release_mut(Foundation);
			#endif
		}

		public static void Update(float deltaTime)
		{
			if (IsDebugDrawEnabled)
			{
				#if USEPHYSX
				PhysXAPI.Scene_setVisualizationParameter_mut(Scene, (uint32)PxVisualizationParameter.eSCALE, 1.0f);
				PhysXAPI.Scene_setVisualizationParameter_mut(Scene, (uint32)PxVisualizationParameter.eWORLD_AXES, 1.0f);
				PhysXAPI.Scene_setVisualizationParameter_mut(Scene, (uint32)PxVisualizationParameter.eBODY_AXES, 1.0f);
				PhysXAPI.Scene_setVisualizationParameter_mut(Scene, (uint32)PxVisualizationParameter.eACTOR_AXES, 1.0f);
				PhysXAPI.Scene_setVisualizationParameter_mut(Scene, (uint32)PxVisualizationParameter.eCOLLISION_SHAPES, 1.0f);
				#endif
			}
			else
			{
				#if USEPHYSX
				PhysXAPI.Scene_setVisualizationParameter_mut(Scene, (uint32)PxVisualizationParameter.eSCALE, 0.0f);
				#endif
				DebugDraw3D.Clear();
				return;
			}

			var count = frameRate.Update(deltaTime);
			while (count-- > 0)
			{
				#if USEPHYSX
				PhysXAPI.Scene_simulate_mut(Scene, frameRate.DeltaTime, null, null, 0, true);
				PhysXAPI.Scene_fetchResults_mut(Scene, true, null);

				if (IsDebugDrawEnabled && count == 0)
				{
					debugDraw.DebugDraw(Scene);
				}
				#endif
			}
		}
	}
}