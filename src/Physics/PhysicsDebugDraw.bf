using System;
using System.Collections;
using Bgfx;

namespace Dedkeni
{
	class PhysicsDebugDraw
	{
		private Chipmunk2D.DebugDrawOptions debugDrawOptions;

		private static Chipmunk2D.DebugColor DrawColorForShapeCallback(void* shape, void* data)
		{
			return Chipmunk2D.DebugColor(0.3f, 0.4f, 0.3f, 0.5f);
		}

		public void Initialize()
		{
			debugDrawOptions.drawCircle = => DebugDraw.DrawCircle;
			debugDrawOptions.drawSegment = => DebugDraw.DrawSegment;
			debugDrawOptions.drawFatSegment = => DebugDraw.DrawFatSegment;
			debugDrawOptions.drawPolygon = => DebugDraw.DrawPolygon;
			debugDrawOptions.drawDot = => DebugDraw.DrawDot;

			debugDrawOptions.flags = .Shapes | .Constraints | .DrawCollisionPoints;
			debugDrawOptions.shapeOutlineColor = .(0xEE / 255.0f, 0xE8 / 255.0f, 0xD5 / 255.0f, 1.0f);
			debugDrawOptions.colorForShape = => DrawColorForShapeCallback;
			debugDrawOptions.constraintColor = .(0.0f, 0.75f, 0.0f, 0.7f);
			debugDrawOptions.collisionPointColor = .(1.0f, 0.0f, 0.0f, 0.7f);
		}

		public void DebugDraw(Chipmunk2D.Space physicsSpace)
		{
			physicsSpace.DebugDraw(ref debugDrawOptions);
		}

	}
}
