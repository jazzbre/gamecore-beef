using System;

namespace GameCore
{
	static class SDF
	{
		public const float EPSILON = 0.00001f;

		// ------------------------------------------------------------
		// Basic helpers
		// ------------------------------------------------------------

		[Inline]
		public static float Clamp(float v, float minValue, float maxValue)
		{
			return Math.Min(Math.Max(v, minValue), maxValue);
		}

		[Inline]
		public static float Saturate(float v)
		{
			return Clamp(v, 0.0f, 1.0f);
		}

		[Inline]
		public static float Lerp(float a, float b, float t)
		{
			return a + (b - a) * t;
		}

		[Inline]
		public static float SmoothStep(float edge0, float edge1, float x)
		{
			float t = Saturate((x - edge0) / (edge1 - edge0));
			return t * t * (3.0f - 2.0f * t);
		}

		[Inline]
		public static Vector2 Abs(Vector2 v)
		{
			return Vector2(Math.Abs(v.x), Math.Abs(v.y));
		}

		[Inline]
		public static Vector3 Abs(Vector3 v)
		{
			return Vector3(Math.Abs(v.x), Math.Abs(v.y), Math.Abs(v.z));
		}

		[Inline]
		public static Vector2 Max(Vector2 a, Vector2 b)
		{
			return Vector2(Math.Max(a.x, b.x), Math.Max(a.y, b.y));
		}

		[Inline]
		public static Vector3 Max(Vector3 a, Vector3 b)
		{
			return Vector3(Math.Max(a.x, b.x), Math.Max(a.y, b.y), Math.Max(a.z, b.z));
		}

		[Inline]
		public static Vector2 Min(Vector2 a, Vector2 b)
		{
			return Vector2(Math.Min(a.x, b.x), Math.Min(a.y, b.y));
		}

		[Inline]
		public static Vector3 Min(Vector3 a, Vector3 b)
		{
			return Vector3(Math.Min(a.x, b.x), Math.Min(a.y, b.y), Math.Min(a.z, b.z));
		}

		[Inline]
		public static Vector2 Max(Vector2 a, float b)
		{
			return Vector2(Math.Max(a.x, b), Math.Max(a.y, b));
		}

		[Inline]
		public static Vector3 Max(Vector3 a, float b)
		{
			return Vector3(Math.Max(a.x, b), Math.Max(a.y, b), Math.Max(a.z, b));
		}

		[Inline]
		public static Vector2 Min(Vector2 a, float b)
		{
			return Vector2(Math.Min(a.x, b), Math.Min(a.y, b));
		}

		[Inline]
		public static Vector3 Min(Vector3 a, float b)
		{
			return Vector3(Math.Min(a.x, b), Math.Min(a.y, b), Math.Min(a.z, b));
		}

		// ------------------------------------------------------------
		// Boolean / blend operations
		// ------------------------------------------------------------

		[Inline]
		public static float Union(float a, float b)
		{
			return Math.Min(a, b);
		}

		[Inline]
		public static float Intersection(float a, float b)
		{
			return Math.Max(a, b);
		}

		[Inline]
		public static float Difference(float a, float b)
		{
			return Math.Max(a, -b);
		}

		[Inline]
		public static float Invert(float d)
		{
			return -d;
		}

		[Inline]
		public static float Onion(float d, float thickness)
		{
			return Math.Abs(d) - thickness;
		}

		[Inline]
		public static float Round(float d, float radius)
		{
			return d - radius;
		}

		[Inline]
		public static float Annular(float d, float radius)
		{
			return Math.Abs(d) - radius;
		}

		// Polynomial smooth min.
		// k is blend radius.
		[Inline]
		public static float SmoothUnion(float a, float b, float k)
		{
			float h = Saturate(0.5f + 0.5f * (b - a) / k);
			return Lerp(b, a, h) - k * h * (1.0f - h);
		}

		[Inline]
		public static float SmoothIntersection(float a, float b, float k)
		{
			float h = Saturate(0.5f - 0.5f * (b - a) / k);
			return Lerp(b, a, h) + k * h * (1.0f - h);
		}

		[Inline]
		public static float SmoothDifference(float a, float b, float k)
		{
			float h = Saturate(0.5f - 0.5f * (b + a) / k);
			return Lerp(a, -b, h) + k * h * (1.0f - h);
		}

		// ------------------------------------------------------------
		// 2D primitives
		// ------------------------------------------------------------

		[Inline]
		public static float Circle(Vector2 p, float radius)
		{
			return p.Length - radius;
		}

		// size = half extents.
		[Inline]
		public static float Box2D(Vector2 p, Vector2 size)
		{
			Vector2 q = Abs(p) - size;
			return Max(q, 0.0f).Length + Math.Min(Math.Max(q.x, q.y), 0.0f);
		}

		// size = half extents, radius = corner radius.
		[Inline]
		public static float RoundedBox2D(Vector2 p, Vector2 size, float radius)
		{
			Vector2 q = Abs(p) - size + Vector2(radius, radius);
			return Max(q, 0.0f).Length + Math.Min(Math.Max(q.x, q.y), 0.0f) - radius;
		}

		[Inline]
		public static float Segment2D(Vector2 p, Vector2 a, Vector2 b)
		{
			Vector2 pa = p - a;
			Vector2 ba = b - a;
			float h = Saturate(Vector2.Dot(pa, ba) / Vector2.Dot(ba, ba));
			return (pa - ba * h).Length;
		}

		[Inline]
		public static float Capsule2D(Vector2 p, Vector2 a, Vector2 b, float radius)
		{
			return Segment2D(p, a, b) - radius;
		}

		// Infinite line through a/b.
		[Inline]
		public static float Line2D(Vector2 p, Vector2 a, Vector2 b)
		{
			Vector2 ba = b - a;
			Vector2 pa = p - a;

			float len = ba.Length;
			if (len <= EPSILON)
				return pa.Length;

			// 2D cross product magnitude / line length.
			float cross = pa.x * ba.y - pa.y * ba.x;
			return Math.Abs(cross) / len;
		}

		// Plane-like 2D half-space.
		// n should be normalized.
		[Inline]
		public static float HalfPlane2D(Vector2 p, Vector2 n, float offset)
		{
			return Vector2.Dot(p, n) + offset;
		}

		// ------------------------------------------------------------
		// 3D primitives
		// ------------------------------------------------------------

		[Inline]
		public static float Sphere(Vector3 p, float radius)
		{
			return p.Length - radius;
		}

		// size = half extents.
		[Inline]
		public static float Box3D(Vector3 p, Vector3 size)
		{
			Vector3 q = Abs(p) - size;
			return Max(q, 0.0f).Length + Math.Min(Math.Max(q.x, Math.Max(q.y, q.z)), 0.0f);
		}

		// size = half extents, radius = corner radius.
		[Inline]
		public static float RoundedBox3D(Vector3 p, Vector3 size, float radius)
		{
			Vector3 q = Abs(p) - size + Vector3(radius, radius, radius);
			return Max(q, 0.0f).Length + Math.Min(Math.Max(q.x, Math.Max(q.y, q.z)), 0.0f) - radius;
		}

		// Infinite plane.
		// n should be normalized.
		[Inline]
		public static float Plane(Vector3 p, Vector3 n, float offset)
		{
			return Vector3.Dot(p, n) + offset;
		}

		[Inline]
		public static float Segment3D(Vector3 p, Vector3 a, Vector3 b)
		{
			Vector3 pa = p - a;
			Vector3 ba = b - a;
			float h = Saturate(Vector3.Dot(pa, ba) / Vector3.Dot(ba, ba));
			return (pa - ba * h).Length;
		}

		[Inline]
		public static float Capsule3D(Vector3 p, Vector3 a, Vector3 b, float radius)
		{
			return Segment3D(p, a, b) - radius;
		}

		// Cylinder along Y axis, centered at origin.
		// radius = xz radius, halfHeight = half height on Y.
		[Inline]
		public static float CylinderY(Vector3 p, float radius, float halfHeight)
		{
			Vector2 d = Vector2(Vector2(p.x, p.z).Length - radius, Math.Abs(p.y) - halfHeight);
			return Math.Min(Math.Max(d.x, d.y), 0.0f) + Max(d, 0.0f).Length;
		}

		// Cylinder along X axis.
		[Inline]
		public static float CylinderX(Vector3 p, float radius, float halfHeight)
		{
			Vector2 d = Vector2(Vector2(p.y, p.z).Length - radius, Math.Abs(p.x) - halfHeight);
			return Math.Min(Math.Max(d.x, d.y), 0.0f) + Max(d, 0.0f).Length;
		}

		// Cylinder along Z axis.
		[Inline]
		public static float CylinderZ(Vector3 p, float radius, float halfHeight)
		{
			Vector2 d = Vector2(Vector2(p.x, p.y).Length - radius, Math.Abs(p.z) - halfHeight);
			return Math.Min(Math.Max(d.x, d.y), 0.0f) + Max(d, 0.0f).Length;
		}

		// Infinite cylinder along Y axis.
		[Inline]
		public static float InfiniteCylinderY(Vector3 p, float radius)
		{
			return Vector2(p.x, p.z).Length - radius;
		}

		// Torus around Y axis.
		// majorRadius = distance from center to tube center.
		// minorRadius = tube radius.
		[Inline]
		public static float TorusY(Vector3 p, float majorRadius, float minorRadius)
		{
			Vector2 q = Vector2(Vector2(p.x, p.z).Length - majorRadius, p.y);
			return q.Length - minorRadius;
		}

		// Cone along Y axis, centered approximately at origin.
		// c should be normalized Vector2(sin(angle), cos(angle)).
		[Inline]
		public static float InfiniteConeY(Vector3 p, Vector2 c)
		{
			Vector2 q = Vector2(Vector2(p.x, p.z).Length, p.y);
			return Vector2.Dot(c, q);
		}

		// ------------------------------------------------------------
		// Domain operations
		// ------------------------------------------------------------

		[Inline]
		public static Vector2 Translate(Vector2 p, Vector2 offset)
		{
			return p - offset;
		}

		[Inline]
		public static Vector3 Translate(Vector3 p, Vector3 offset)
		{
			return p - offset;
		}

		[Inline]
		public static Vector2 Repeat(Vector2 p, Vector2 cellSize)
		{
			return Vector2(
				p.x - cellSize.x * Math.Floor(p.x / cellSize.x + 0.5f),
				p.y - cellSize.y * Math.Floor(p.y / cellSize.y + 0.5f));
		}

		[Inline]
		public static Vector3 Repeat(Vector3 p, Vector3 cellSize)
		{
			return Vector3(
				p.x - cellSize.x * Math.Floor(p.x / cellSize.x + 0.5f),
				p.y - cellSize.y * Math.Floor(p.y / cellSize.y + 0.5f),
				p.z - cellSize.z * Math.Floor(p.z / cellSize.z + 0.5f));
		}

		[Inline]
		public static Vector2 Mirror(Vector2 p)
		{
			return Abs(p);
		}

		[Inline]
		public static Vector3 Mirror(Vector3 p)
		{
			return Abs(p);
		}

		[Inline]
		public static Vector3 BendXZ(Vector3 p, float amount)
		{
			// Simple bend around Z-ish direction.
			// Useful for approximate deformations, not exact SDF-preserving.
			float c = Math.Cos(amount * p.x);
			float s = Math.Sin(amount * p.x);

			float x = c * p.x - s * p.y;
			float y = s * p.x + c * p.y;

			return Vector3(x, y, p.z);
		}

		// ------------------------------------------------------------
		// Normal estimation
		// ------------------------------------------------------------

		public function float SDF3DFunction(Vector3 p);

		public static Vector3 EstimateNormal(Vector3 p, SDF3DFunction sdf, float epsilon = 0.001f)
		{
			float dx = sdf(Vector3(p.x + epsilon, p.y, p.z)) - sdf(Vector3(p.x - epsilon, p.y, p.z));
			float dy = sdf(Vector3(p.x, p.y + epsilon, p.z)) - sdf(Vector3(p.x, p.y - epsilon, p.z));
			float dz = sdf(Vector3(p.x, p.y, p.z + epsilon)) - sdf(Vector3(p.x, p.y, p.z - epsilon));

			Vector3 n = Vector3(dx, dy, dz);
			float len = n.Length;

			if (len <= EPSILON)
				return Vector3(0.0f, 1.0f, 0.0f);

			return n / len;
		}

		// ------------------------------------------------------------
		// Ray marching helper
		// ------------------------------------------------------------

		public struct RayMarchResult
		{
			public bool hit;
			public float distance;
			public int steps;
			public Vector3 position;
		}

		public static RayMarchResult RayMarch(
			Vector3 rayOrigin,
			Vector3 rayDirection,
			SDF3DFunction sdf,
			float maxDistance = 1000.0f,
			float hitDistance = 0.001f,
			int maxSteps = 128)
		{
			RayMarchResult result = .();
			result.hit = false;
			result.distance = 0.0f;
			result.steps = 0;
			result.position = rayOrigin;

			float t = 0.0f;

			for (int i = 0; i < maxSteps; i++)
			{
				Vector3 p = rayOrigin + rayDirection * t;
				float d = sdf(p);

				if (d < hitDistance)
				{
					result.hit = true;
					result.distance = t;
					result.steps = i + 1;
					result.position = p;
					return result;
				}

				t += d;

				if (t > maxDistance)
					break;
			}

			result.hit = false;
			result.distance = t;
			result.steps = maxSteps;
			result.position = rayOrigin + rayDirection * t;
			return result;
		}
	}
}