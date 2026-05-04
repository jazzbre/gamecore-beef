using System;

namespace GameCore
{
	static class HalfUtils
	{
		public static uint16 FloatToHalf(float f)
		{
			uint bits = *(uint*)&f; // reinterpret float as uint
			uint sign = (bits >> 16) & 0x8000; // sign bit
			uint exponent = (bits >> 23) & 0xFF;
			uint mantissa = bits & 0x7FFFFF;

			if (exponent == 255) // Inf or NaN
			{
				if (mantissa != 0)
				{
					// NaN
					return (uint16)(sign | 0x7E00);
				}
				else
				{
					// Inf
					return (uint16)(sign | 0x7C00);
				}
			}

			// normalised float
			int newExp = (int)exponent - 127 + 15;
			if (newExp >= 0x1F)
			{
				// Overflow -> Inf
				return (uint16)(sign | 0x7C00);
			}
			else if (newExp <= 0)
			{
				if (newExp < -10)
				{
					// Too small -> zero
					return (uint16)sign;
				}
				// Subnormal
				mantissa |= 0x800000;
				int shift = 14 - newExp;
				uint halfMantissa = mantissa >> shift;
				if ((mantissa >> (shift - 1)) & 1 != 0) // round
					halfMantissa++;

				return (uint16)(sign | (halfMantissa & 0x3FF));
			}
			else
			{
				uint halfExp = (uint)(newExp << 10);
				uint halfMantissa = mantissa >> 13;
				if ((mantissa & 0x1000) != 0) // round
					halfMantissa++;

				return (uint16)(sign | halfExp | (halfMantissa & 0x3FF));
			}
		}

		public static float HalfToFloat(uint16 h)
		{
			uint sign = (uint)(h & 0x8000) << 16;
			uint exponent = (uint)(h >> 10) & 0x1F;
			uint mantissa = (uint)(h & 0x3FF);

			if (exponent == 0)
			{
				if (mantissa == 0)
				{
					// zero
					uint bits = sign;
					return *(float*)&bits;
				}
				else
				{
					// subnormal
					exponent = 1;
					while ((mantissa & 0x400) == 0)
					{
						mantissa <<= 1;
						exponent--;
					}
					mantissa &= 0x3FF;
					uint bits = sign | ((exponent + (127 - 15)) << 23) | (mantissa << 13);
					return *(float*)&bits;
				}
			}
			else if (exponent == 0x1F)
			{
				// Inf or NaN
				uint bits = sign | 0x7F800000 | (mantissa << 13);
				return *(float*)&bits;
			}
			else
			{
				// normal
				uint bits = sign | ((exponent + (127 - 15)) << 23) | (mantissa << 13);
				return *(float*)&bits;
			}
		}
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	struct HalfFloat
	{
		[JSON_Beef.Serialized]
		public uint16 h = 0;

		public this()
		{
		}

		public this(float f)
		{
			this = FromFloat(f);
		}

		public float ToFloat()
		{
			return HalfUtils.HalfToFloat(h);
		}

		public static HalfFloat FromFloat(float f)
		{
			return .() { h = HalfUtils.FloatToHalf(f) };
		}
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	struct HalfFloatVector2
	{
		[JSON_Beef.Serialized]
		public HalfFloat x = .();
		[JSON_Beef.Serialized]
		public HalfFloat y = .();

		public this()
		{
		}

		public this(Vector2 v)
		{
			xy = v;
		}

		public Vector2 xy
		{
			get
			{
				return .(x.ToFloat(), y.ToFloat());
			}
			set mut
			{
				x = .(value.x);
				y = .(value.y);
			}
		}
	}
}
