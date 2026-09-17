using System;

namespace GameCore
{
	static class Line
	{
		public static double DistanceToPoint(Vector2 point, Vector2 l1, Vector2 l2)
		{
			double directionX = (double)l2.x - l1.x;
			double directionY = (double)l2.y - l1.y;
			double offsetX = (double)point.x - l1.x;
			double offsetY = (double)point.y - l1.y;
			let lengthSquared = directionX * directionX + directionY * directionY;
			if (lengthSquared == 0.0)
			{
				return Math.Sqrt(offsetX * offsetX + offsetY * offsetY);
			}
			return Math.Abs(directionX * offsetY - directionY * offsetX) / Math.Sqrt(lengthSquared);
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
