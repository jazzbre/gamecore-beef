using System;

namespace GameCore
{
	static class Line
	{
		public static double DistanceToPoint(Vector2 point, Vector2 l1, Vector2 l2)
		{
			return Math.Abs((l2.x - l1.x) * (l1.y - point.y) - (l1.x - point.x) * (l2.y - l1.y)) / Math.Sqrt(Math.Pow(l2.x - l1.x, 2) + Math.Pow(l2.y - l1.y, 2));
		}

		public static float GetPositionSegmentDelta(Vector2 position, Vector2 a, Vector2 b, float* segmentLength = null)
		{
			Vector2 ba = b - a;
			float d = Vector2.Dot(ba, ba);
			if (segmentLength != null)
			{
				*segmentLength = d;
			}
			if (Math.Abs(d) < 0.0000001f)
			{
				return 0.0f;
			}
			return Vector2.Dot(position - a, ba) / d;
		}

		public static Vector2 ConstrainToSegment(Vector2 position, Vector2 a, Vector2 b)
		{
			return Vector2.Lerp(a, b, Math.Clamp(GetPositionSegmentDelta(position, a, b), 0.0f, 1.0f));
		}
	}
}
