using System;
using System.Collections;
using Bgfx;
#if USEPHYSX
using PhysX;
#endif

namespace GameCore
{
	class Physics3DDebugDraw
	{
		public void Initialize()
		{
		}

		#if USEPHYSX
		public void DebugDraw(PxScene* scene)
		{
			DebugDraw3D.Clear();
			var renderBuffer = PhysXAPI.Scene_getRenderBuffer_mut(scene);
			// Lines
			var lineCount = PhysXAPI.RenderBuffer_getNbLines(renderBuffer);
			var lines = PhysXAPI.RenderBuffer_getLines(renderBuffer);
			for (var i = 0; i < lineCount; ++i)
			{
				var line = lines[i];
				var p0 = Vector3(line.pos0.x, line.pos0.y, line.pos0.z);
				var p1 = Vector3(line.pos1.x, line.pos1.y, line.pos1.z);
				var color = Color(line.color0);
				DebugDraw3D.DrawSegment(p0, p1, color);
			}
			// Triangles
			var triangleCount = PhysXAPI.RenderBuffer_getNbTriangles(renderBuffer);
			var triangles = PhysXAPI.RenderBuffer_getTriangles(renderBuffer);
			for (var i = 0; i < triangleCount; ++i)
			{
				var triangle = triangles[i];
				var p0 = Vector3(triangle.pos0.x, triangle.pos0.y, triangle.pos0.z);
				var p1 = Vector3(triangle.pos1.x, triangle.pos1.y, triangle.pos1.z);
				var p2 = Vector3(triangle.pos2.x, triangle.pos2.y, triangle.pos2.z);
				var color = Color(triangle.color0);
				DebugDraw3D.DrawTriangle(p0, p1, p2, color);
			}
		}
		#endif
	}
}
