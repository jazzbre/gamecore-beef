using System;
using System.IO;
using Bgfx;
using System.Collections;

namespace GameCore
{
	/// What a pass wants from a camera beyond its matrices.
	public enum CameraRenderFlags : uint32
	{
		None = 0,
		/// Only the depth of the geometry matters, so material, lighting and texture setup is
		/// skipped. A shadow cascade renders this way.
		DepthOnly = 1,
	}

	class Camera
	{
		private Vector4[6] frustumPlanes;
		private bool frustumValid;
		private int frustumPlaneCount;

		public CameraRenderFlags renderFlags = .None;
		public bool IsDepthOnly => (renderFlags & .DepthOnly) != .None;
		public bool UseReversedDepth = false;
		public bool IsReversedDepth => UseReversedDepth && !IsDepthOnly;
		public float DepthClearValue => IsReversedDepth ? 0.0f : 1.0f;
		public bgfx.StateFlags DepthTest => IsReversedDepth ? .DepthTestGequal : .DepthTestLequal;
		public static bool HomogeneousDepth => bgfx.get_caps() != null && bgfx.get_caps().homogeneousDepth != 0;

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
			projectionMatrix = IsReversedDepth
				? Matrix4.CreatePerspectiveReversedInfinite(fov * (float)Math.DegreeToRadian, aspectRatio, nearPlane, HomogeneousDepth)
				: Matrix4.CreatePerspectiveFOV(fov * (float)Math.DegreeToRadian, aspectRatio, nearPlane, farPlane, HomogeneousDepth);
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
			for (int32 i = 0; i < frustumPlaneCount; i++)
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
			let clipPosition = Vector4.Transform(position.xyz1, viewProjectionMatrix);
			if (Math.Abs(clipPosition.w) < 0.000001f)
			{
				return .Zero;
			}
			return clipPosition.xyz / clipPosition.w;
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
			frustumPlanes[4] = NormalizePlane(IsReversedDepth ? columnW - columnZ : (HomogeneousDepth ? columnW + columnZ : columnZ));
			frustumPlaneCount = IsReversedDepth ? 5 : 6;
			if (!IsReversedDepth)
			{
				frustumPlanes[5] = NormalizePlane(columnW - columnZ);
			}
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
