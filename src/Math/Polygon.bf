using System.Collections;

namespace GameCore
{
	enum PolygonSide
	{
		Left,
		Right,
		None
	}

	class Polygon
	{
		public static PolygonSide GetSide(Vector2 a, Vector2 b)
		{
			let x = Vector2.ScalarCross(a, b);
			if (x < 0)
			{
				return .Left;
			} else if (x > 0)
			{
				return .Right;
			} else
			{
				return .None;
			}
		}

		public static bool PointInPolygon(Vector2 point, Vector2[] vertices)
		{
			PolygonSide previousSide = .None;
			let count = vertices.Count;
			for (int n = 0; n < vertices.Count; ++n)
			{
				let pointA = vertices[n];
				let pointB = vertices[(n + 1) % count];
				let affineSegment = pointB - pointA;
				let affinePoint = point - pointA;
				let currentSide = GetSide(affineSegment, affinePoint);
				if (currentSide == .None)
				{
					return false;
				}
				else if (previousSide == .None)
				{
					previousSide = currentSide;
				}
				else if (previousSide != currentSide)
				{
					return false;
				}
			}
			return true;
		}

		public static float Cross(Vector2 a, Vector2 b, Vector2 c)
		{
			return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
		}

		public static bool IsConvex(Vector2 prev, Vector2 curr, Vector2 next)
		{
			return Cross(prev, curr, next) > 0.0f;
		}

		public static bool PointInTriangle(Vector2 p, Vector2 a, Vector2 b, Vector2 c)
		{
			float c1 = Cross(p, a, b);
			float c2 = Cross(p, b, c);
			float c3 = Cross(p, c, a);
			bool hasNeg = (c1 < 0) || (c2 < 0) || (c3 < 0);
			bool hasPos = (c1 > 0) || (c2 > 0) || (c3 > 0);
			return !(hasNeg && hasPos);
		}

		public delegate void NewTriangleDelegate(Vector2 a, Vector2, Vector2 c);

		public static void SplitIntoConvexPolygons(Vector2[] points, NewTriangleDelegate newTriangleDelegate)
		{
			// Make a working copy
			List<Vector2> verts = scope .(points);

			while (verts.Count > 3)
			{
				bool earFound = false;
				for (int i = 0; i < verts.Count; i++)
				{
					Vector2 prev = verts[(i - 1 + verts.Count) % verts.Count];
					Vector2 curr = verts[i];
					Vector2 next = verts[(i + 1) % verts.Count];

					if (!IsConvex(prev, curr, next))
						continue;

					bool hasPointInside = false;
					for (int j = 0; j < verts.Count; j++)
					{
						if (j == i || j == (i - 1 + verts.Count) % verts.Count || j == (i + 1) % verts.Count)
							continue;
						if (PointInTriangle(verts[j], prev, curr, next))
						{
							hasPointInside = true;
							break;
						}
					}

					if (!hasPointInside)
					{
						newTriangleDelegate(prev, curr, next);
						verts.RemoveAt(i);
						earFound = true;
						break;
					}
				}

				if (!earFound)
				{
					// Fallback: can't find ear -> probably invalid polygon
					break;
				}
			}

			// Last triangle
			if (verts.Count == 3)
			{
				newTriangleDelegate(verts[0], verts[1], verts[2]);
			}
		}
	}
}
