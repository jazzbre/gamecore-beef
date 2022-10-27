namespace GameCore
{
	struct ConstantFrameRate
	{
		float constantDeltaTime = 1.0f / 6.0f;
		float time = 0.0f;
		bool firstUpdate = true;

		public float DeltaTime => constantDeltaTime;

		public this(float deltaTime)
		{
			constantDeltaTime = deltaTime;
		}

		public void Reset() mut
		{
			firstUpdate = true;
			time = 0.0f;
		}

		public int Update(float deltaTime) mut
		{
			if (firstUpdate)
			{
				firstUpdate = false;
				return 1;
			}
			time += deltaTime;
			int count = 0;
			while (time > constantDeltaTime)
			{
				time -= constantDeltaTime;
				++count;
			}
			return count;
		}
	}
}
