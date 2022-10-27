using Dedkeni;

namespace System
{
	extension Math
	{
		public static float MoveTowards(float value, float target, float speed)
		{
			if (value < target)
			{
				return Math.Min(value + speed, target);
			}
			else
			{
				return Math.Max(value - speed, target);
			}
		}

		public static float PixelLerp(float value, float target, float speed, float limit = 1)
		{
			var result = Math.Lerp(value, target, Math.Min(1.0f, speed));
			if (Math.Abs(target - result) <= limit)
			{
				result = target;
			}
			return result;
		}

		public static Vector2 GetNearestPointOnSegment(Vector2 segmenta, Vector2 segmentb, Vector2 point, out float delta)
		{
			let direction = segmentb - segmenta;
			let projection = Vector2.Dot(point, direction) - Vector2.Dot(segmenta, direction);
			let lengthSquared = Vector2.Dot(direction, direction);
			if (lengthSquared <= 0.00001)
			{
				delta = 0.0f;
				return segmenta;
			}

			if (projection > lengthSquared)
			{
				delta = 1.0f;
				return segmentb;
			}
			if (projection < 0.0f)
			{
				delta = 0.0f;
				return segmenta;
			}
			delta = projection / lengthSquared;
			return segmenta + delta * direction;
		}

		public static bool SegmentSegmentIntersection(Vector2 p1, Vector2 p2, Vector2 p3, Vector2 p4, out Vector2 intersection, float epsilon = 0.0f)
		{
			// Get the segments' parameters.
			let dx12 = p2.x - p1.x;
			let dy12 = p2.y - p1.y;
			let dx34 = p4.x - p3.x;
			let dy34 = p4.y - p3.y;

			// Solve for t1 and t2
			let denominator = (dy12 * dx34 - dx12 * dy34);
			if (denominator < 0.0001f)
			{
				// The lines are parallel (or close enough to it).
				intersection = .Zero;
				return false;
			}

			let t1 = ((p1.x - p3.x) * dy34 + (p3.y - p1.y) * dx34) / denominator;

			let t2 = ((p3.x - p1.x) * dy12 + (p1.y - p3.y) * dx12) / -denominator;

			// Find the point of intersection.
			intersection = .(p1.x + dx12 * t1, p1.y + dy12 * t1);

			let minLimit = epsilon;
			let maxLimit = 1.0f - epsilon;
			// The segments intersect if t1 and t2 are between 0 and 1.
			return ((t1 >= minLimit) && (t1 <= maxLimit) && (t2 >= minLimit) && (t2 <= maxLimit));
		}

		public static float SDFSegment(Vector2 p, Vector2 a, Vector2 b)
		{
			let pa = p - a;
			let ba = b - a;
			let h = Math.Clamp(Vector2.Dot(pa, ba) / Vector2.Dot(ba, ba), 0.0f, 1.0f);
			return (pa - ba * h).Length;
		}

	}
}
