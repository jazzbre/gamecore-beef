using System;
namespace GameCore;

static class Noise3D
{
	public static float MouseX = 0.0f; // replaces iMouse.x

	static float Floor(float x)
	{
		return Math.Floor(x);
	}

	static float Fract(float x)
	{
		return x - Floor(x);
	}

	static float Mod289(float x)
	{
		return x - Floor(x * (1.0f / 289.0f)) * 289.0f;
	}

	static Vector4 Mod289(Vector4 x)
	{
		return x - Floor(x * (1.0f / 289.0f)) * 289.0f;
	}

	static Vector4 Floor(Vector4 x)
	{
		return Vector4(
			Floor(x.x),
			Floor(x.y),
			Floor(x.z),
			Floor(x.w)
			);
	}

	static Vector3 Floor(Vector3 x)
	{
		return Vector3(
			Floor(x.x),
			Floor(x.y),
			Floor(x.z)
			);
	}

	static Vector4 Fract(Vector4 x)
	{
		return Vector4(
			Fract(x.x),
			Fract(x.y),
			Fract(x.z),
			Fract(x.w)
			);
	}

	static Vector4 Perm(Vector4 x)
	{
		return Mod289(((x * 34.0f)) * x);
	}

	public static float Noise(Vector3 p)
	{
		Vector3 a = Floor(p);
		Vector3 d = p - a;

		d = d * d * (Vector3(3.0f) - 2.0f * d);

		// GLSL:
		// vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
		Vector4 b = Vector4(a.x, a.x, a.y, a.y) + Vector4(0.0f, 1.0f, 0.0f, 1.0f);

		// vec4 k1 = perm(b.xyxy);
		Vector4 k1 = Perm(Vector4(b.x, b.y, b.x, b.y));

		// vec4 k2 = perm(k1.xyxy + b.zzww);
		Vector4 k2 = Perm(Vector4(k1.x, k1.y, k1.x, k1.y) + Vector4(b.z, b.z, b.w, b.w));

		// vec4 c = k2 + a.zzzz;
		Vector4 c = k2 + Vector4(a.z);

		Vector4 k3 = Perm(c);
		Vector4 k4 = Perm(c + Vector4.One);

		Vector4 o1 = Fract(k3 * (1.0f / 41.0f));
		Vector4 o2 = Fract(k4 * (1.0f / 41.0f));

		Vector4 o3 = o2 * d.z + o1 * (1.0f - d.z);

		// vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);
		Vector2 o4 = Vector2(o3.y, o3.w) * d.x + Vector2(o3.x, o3.z) * (1.0f - d.x);

		return o4.y * d.y + o4.x * (1.0f - d.y);
	}

	public static float FBM(Vector3 _x)
	{
		Vector3 x = _x;
		float v = 0.0f;
		float a = 0.5f;
		Vector3 shift = Vector3(100.0f);

		for (int i = 0; i < 5; ++i)
		{
			v += a * Noise(x);
			x = x * 2.0f + shift;
			a *= 0.5f;
		}

		return v;
	}
}