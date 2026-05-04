using System;
using System.IO;
using System.Collections;

namespace GameCore
{
	class Camera
	{
		public Vector3 position = .Zero;
		public Quaternion rotation = .Identity;
		public float fov = 60.0f;

		public float nearPlane = 0.01f;
		public float farPlane = 1000.0f;

		public Matrix4 viewMatrix = .Identity;
		public Matrix4 projectionMatrix = .Identity;

		public void UpdateMatrices(float aspectRatio)
		{
			viewMatrix = Matrix4.Inverse(Matrix4.CreateTransform(position, .One, rotation));
			projectionMatrix = Matrix4.CreatePerspectiveFOV(fov * (float)Math.DegreeToRadian, aspectRatio, nearPlane, farPlane);
		}
	}
}