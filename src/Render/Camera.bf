using System;
using System.IO;
using System.Collections;

namespace GameCore
{
	class Camera
	{
		private Vector4[6] frustumPlanes;
		private bool frustumValid;

		public Vector3 position = .Zero;
		public Quaternion rotation = .Identity;
		public float fov = 60.0f;

		public float nearPlane = 0.01f;
		public float farPlane = 1000.0f;

		public Matrix4 worldMatrix = .Identity;
		public Matrix4 viewMatrix = .Identity;
		public Matrix4 projectionMatrix = .Identity;
		public Matrix4 viewProjectionMatrix = .Identity;

		public void UpdateMatrices(float aspectRatio)
		{
			worldMatrix = Matrix4.CreateTransform(position, .One, rotation);
			viewMatrix = Matrix4.Inverse(worldMatrix);
			projectionMatrix = Matrix4.CreatePerspectiveFOV(fov * (float)Math.DegreeToRadian, aspectRatio, nearPlane, farPlane);
			viewProjectionMatrix = viewMatrix * projectionMatrix;
			UpdateFrustumPlanes();
		}

		public void SetMatrices(Matrix4 world, Matrix4 view, Matrix4 projection)
		{
			worldMatrix = world;
			viewMatrix = view;
			projectionMatrix = projection;
			viewProjectionMatrix = viewMatrix * projectionMatrix;
			position = world.Translation;
			rotation = Quaternion.Normalize(Quaternion.CreateFromRotationMatrix(world));
			UpdateFrustumPlanes();
		}

		public bool IsBoundsVisible(Matrix4 worldMatrix, Bounds3 bounds)
		{
			if (!frustumValid)
			{
				return true;
			}

			let worldBounds = Bounds3.Transform(bounds, worldMatrix);
			for (int32 i = 0; i < frustumPlanes.Count; i++)
			{
				let plane = frustumPlanes[i];
				let positiveVertex = Vector3(plane.x >= 0.0f ? worldBounds.max.x : worldBounds.min.x, plane.y >= 0.0f ? worldBounds.max.y : worldBounds.min.y, plane.z >= 0.0f ? worldBounds.max.z : worldBounds.min.z);
				if (plane.x * positiveVertex.x + plane.y * positiveVertex.y + plane.z * positiveVertex.z + plane.w < 0.0f)
				{
					return false;
				}
			}
			return true;
		}

		public Vector3 GetHomoPosition(Vector3 position)
		{
			var homoPosition = Vector3.Transform(position, viewProjectionMatrix);
			homoPosition.xy /= homoPosition.z;
			return homoPosition;
		}

		public Vector3 GetNormalizedPosition(Vector3 position)
		{
			let homoPosition = GetHomoPosition(position);
			return .(0.5f + homoPosition.x * 0.5f, 0.5f + homoPosition.y * 0.5f, homoPosition.z);
		}

		public Vector3 GetScreenPosition(Vector3 position, Vector2 viewportSize)
		{
			let normalizedPosition = GetNormalizedPosition(position);
			return .(normalizedPosition.xy * viewportSize, normalizedPosition.z);
		}

		private void UpdateFrustumPlanes()
		{
			let columnX = viewProjectionMatrix.GetColumn4(0);
			let columnY = viewProjectionMatrix.GetColumn4(1);
			let columnZ = viewProjectionMatrix.GetColumn4(2);
			let columnW = viewProjectionMatrix.GetColumn4(3);

			frustumPlanes[0] = NormalizePlane(columnW + columnX);
			frustumPlanes[1] = NormalizePlane(columnW - columnX);
			frustumPlanes[2] = NormalizePlane(columnW + columnY);
			frustumPlanes[3] = NormalizePlane(columnW - columnY);
			frustumPlanes[4] = NormalizePlane(columnZ);
			frustumPlanes[5] = NormalizePlane(columnW - columnZ);
			frustumValid = true;
		}

		private static Vector4 NormalizePlane(Vector4 plane)
		{
			float normalLength = Math.Sqrt(plane.x * plane.x + plane.y * plane.y + plane.z * plane.z);
			if (normalLength <= 0.000001f)
			{
				return plane;
			}
			return plane / normalLength;
		}
	}
}
