using System;

namespace GameCore
{
	class Water
	{
		public struct Spring
		{
			public float height, speed;

			public void Update(float dampening, float tension, float targetHeight) mut
			{
				float x = targetHeight - height;
				speed += tension * x - speed * dampening;
				height += speed;
			}
		}

		public Spring[] springs = null ~ delete _;
		public Vector2[] deltas = null ~ delete _;

		public float targetHeight;
		public float tension = 0.025f;
		public float damping = 0.001f;
		public float spread = 0.25f;

		public void Create(int count, float _targetHeight, float _tension = 0.025f, float _damping = 0.025f, float _spread = 0.25f)
		{
			springs = new Spring[count];
			deltas = new Vector2[count];
			targetHeight = _targetHeight;
			for (int i = 0; i < count; ++i)
			{
				springs[i] = .() { height = targetHeight };
			}
		}

		public void Splash(int index, float speed)
		{
			if (index < 0 || index >= springs.Count)
			{
				return;
			}
			springs[index].speed = speed;
		}

		public void Update(int iterationCount = 8)
		{
			for (int i = 0; i < springs.Count; i++)
			{
				springs[i].Update(damping, tension, targetHeight);
			}
			for (int i = 0; i < deltas.Count; ++i)
			{
				deltas[i] = .Zero;
			}
			for (int j = 0; j < iterationCount; j++)
			{
				for (int i = 0; i < springs.Count; i++)
				{
					if (i > 0)
					{
						deltas[i].x = spread * (springs[i].height - springs[i - 1].height);
						springs[i - 1].speed += deltas[i].x;
					}
					if (i < springs.Count - 1)
					{
						deltas[i].y = spread * (springs[i].height - springs[i + 1].height);
						springs[i + 1].speed += deltas[i].y;
					}
				}

				for (int i = 0; i < springs.Count; i++)
				{
					if (i > 0)
					{
						springs[i - 1].height += deltas[i].x;
					}
					if (i < springs.Count - 1)
					{
						springs[i + 1].height += deltas[i].y;
					}
				}
			}
		}

	}
}
