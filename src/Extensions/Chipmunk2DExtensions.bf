using System;

namespace Chipmunk2D
{
	extension Vector2
	{
		public Dedkeni.Vector2 ToVector()
		{
			return .((float)x, (float)y);
		}

		public static Vector2 FromVector(Dedkeni.Vector2 v)
		{
			return .((Chipmunk2D.Real)v.x, (Chipmunk2D.Real)v.y);
		}
	}

	extension Body {
		public void ClearForces() {
			Velocity = .(0,0);
			AngularVelocity = 0;
			Torque = 0;
			Force = .(0,0);
		}
	}
}
