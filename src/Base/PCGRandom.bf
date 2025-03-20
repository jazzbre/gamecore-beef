namespace System
{
	struct PCGRandom
	{
		private uint64 state;
		private uint64 inc;

		public this(uint64 initstate, uint64 initseq)
		{
			state = 0;
			inc = (initseq << 1) | 1;
			Next();
			state += initstate;
			Next();
		}

		public uint32 Next() mut
		{
			let oldstate = state;
			state = oldstate * 6364136223846793005 + inc;
			let xorshifted = (uint32)(((oldstate >> 18) ^ oldstate) >> 27);
			let rot = (uint32)(oldstate >> 59);
			return (xorshifted >> rot) | (xorshifted << (-((int32)rot) & 31));
		}

		public uint32 Next(uint32 bound) mut
		{
			if (bound == 0)
			{
				return 0;
			}
			let threshold = (uint32)(-((int)bound) % (int)bound);
			while (true)
			{
				let r = Next();
				if (r >= threshold)
				{
					return r % bound;
				}
			}
		}

		public int32 Next(int32 minValue, int32 maxValue) mut
		{
			let range = (uint32)(maxValue - minValue);
			if (range == 0)
			{
				return maxValue;
			}
			let r = Next(range);
			return minValue + (int32)r;
		}

		public double NextDouble() mut
		{
			let r = Next();
			return (double)r / 0xffffffff;
		}

		public double NextDoubleSigned() mut
		{
			return NextDouble() * 2.0 - 1.0;
		}

		public float NextFloat() mut
		{
			return (float)NextDouble();
		}

		public double NextFloatSigned() mut
		{
			return (float)NextDoubleSigned();
		}
	}
}
