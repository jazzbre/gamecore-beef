using System;

namespace GameCore
{
	static class HalfUtils
	{
		public static uint16 FloatToHalf(float f)
		{
			var value = f;
			uint32 bits = *(uint32*)&value;
			uint32 sign = (bits >> 16) & 0x8000;
			uint32 exponent = (bits >> 23) & 0xFF;
			uint32 mantissa = bits & 0x7FFFFF;

			if (exponent == 255)
			{
				return (uint16)(sign | (mantissa == 0 ? 0x7C00 : 0x7E00));
			}

			int halfExponent = (int)exponent - 112;
			if (halfExponent >= 31)
			{
				return (uint16)(sign | 0x7C00);
			}
			if (halfExponent < -10)
			{
				return (uint16)sign;
			}

			int shift = 13;
			uint32 halfBits;
			if (halfExponent <= 0)
			{
				mantissa |= 0x800000;
				shift = 14 - halfExponent;
				halfBits = mantissa >> shift;
			}
			else
			{
				halfBits = (uint32)(halfExponent << 10) | (mantissa >> shift);
			}

			uint32 discardedBits = mantissa & ((1U << shift) - 1);
			uint32 halfway = 1U << (shift - 1);
			// Round to nearest, ties to even; carry may enter the exponent.
			if (discardedBits > halfway || (discardedBits == halfway && (halfBits & 1) != 0))
			{
				++halfBits;
			}
			return (uint16)(sign | halfBits);
		}


		public static float HalfToFloat(uint16 h)
		{
			uint sign = (uint)(h & 0x8000) << 16;
			int exponent = (h >> 10) & 0x1F;
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
					uint bits = sign | ((uint)(exponent + (127 - 15)) << 23) | (mantissa << 13);
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
				uint bits = sign | ((uint)(exponent + (127 - 15)) << 23) | (mantissa << 13);
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
