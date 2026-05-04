using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	class SH9
	{
		public Vector3[9] sh;

		public this()
		{
			Clear();
		}

		public void Clear()
		{
			for (int i = 0; i < 9; ++i)
			{
				sh[i] = .Zero;
			}
		}

		public void AddLight(Vector3 dir, Vector3 color, float intensity = 1.0f)
		{
			float x = dir.x;
			float y = dir.y;
			float z = dir.z;

			// SH basis functions (real SH, L2)
			Vector3 scaledColor = color * intensity;
			sh[0] = scaledColor * 0.282095f;
			sh[1] = scaledColor * 0.488603f * y;
			sh[2] = scaledColor * 0.488603f * z;
			sh[3] = scaledColor * 0.488603f * x;
			sh[4] = scaledColor * 1.092548f * x * y;
			sh[5] = scaledColor * 1.092548f * y * z;
			sh[6] = scaledColor * 0.315392f * (3.0f * z * z - 1.0f);
			sh[7] = scaledColor * 1.092548f * x * z;
			sh[8] = scaledColor * 0.546274f * (x * x - y * y);
		}
	}
}