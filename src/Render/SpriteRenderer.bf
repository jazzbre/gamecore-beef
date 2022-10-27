using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	struct SpriteRenderer
	{
		public Matrix4 worldMatrix;
		public Color color;
		public int spriteIndex;
	}

	enum SpriteFlags
	{
		FlipX = 1 << 0,
		FlipY = 1 << 1,
	}

	class SpriteBatchRenderer
	{
		private static readonly int InstanceVectorCount = 4;

		public static readonly Vector2 DefaultPivot = Vector2(-0.5f, 0.0f);
		public static readonly Vector2 CenterPivot = Vector2(-0.5f, -0.5f);

		private List<SpriteRenderer> renderers = new List<SpriteRenderer>() ~ delete _;
		private Vector4[] instanceData = null ~ delete _;

		private bgfx.StateFlags stateFlags;
		private bgfx.SamplerFlags samplerFlags;
		private int programIndex;

		private Vector4 textureScale;

		public int MaxCount { get; private set; }

		public Shader Shader { get; private set; }
		public Texture Texture { get; private set; }
		public uint16 ViewId { get; private set; }
		public int BatchCount { get; private set; }
		public Vector4 Settings { get; private set; }

		public this(int maxCount = 64)
		{
			MaxCount = maxCount;
			instanceData = new Vector4[maxCount * 4];
		}

		public ~this()
		{
		}

		public void Begin(Shader shader, uint16 viewId, Vector4 settings, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int _programIndex = 0)
		{
			if (renderers.Count > 0)
			{
				renderers.Clear();
			}
			Shader = shader;
			ViewId = viewId;
			Settings = settings;
			Texture = null;
			samplerFlags = _samplerFlags;
			programIndex = _programIndex;
			if (_stateFlags != 0)
			{
				stateFlags = _stateFlags;
			} else
			{
				stateFlags = bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.DepthTestAlways | bgfx.blend_function(bgfx.StateFlags.BlendSrcAlpha, bgfx.StateFlags.BlendInvSrcAlpha);
			}
			if (_samplerFlags != 0)
			{
				samplerFlags = _samplerFlags;
			} else
			{
				samplerFlags = bgfx.SamplerFlags.MinPoint | bgfx.SamplerFlags.MagPoint | bgfx.SamplerFlags.MipPoint | bgfx.SamplerFlags.UClamp | bgfx.SamplerFlags.VClamp;
			}
			BatchCount = 0;
		}

		public void Begin(Shader shader, uint16 viewId, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int _programIndex = 0)
		{
			Begin(shader, viewId, Settings, _stateFlags, _samplerFlags, _programIndex);
		}

		public void Add(Sprite sprite, Matrix4 worldMatrix, Color color = .White, Vector2 pivot = Vector2.Zero, SpriteFlags flags = 0)
		{
			if (sprite == null)
			{
				return;
			}
			Add(sprite.texture, sprite.index, sprite.size, worldMatrix, color, pivot, flags);
		}

		public Matrix4 GetPivotMatrix(Vector3 spriteSize, Matrix4 worldMatrix, Vector2 pivot = Vector2.Zero, SpriteFlags flags = 0)
		{
			var pivotWorldMatrix = worldMatrix;
			var localPivot = pivot;
			if ((flags & .FlipX) != 0)
			{
				pivotWorldMatrix.Right = -pivotWorldMatrix.Right;
				localPivot.x = -localPivot.x;
			}
			if ((flags & .FlipY) != 0)
			{
				pivotWorldMatrix.Up = -pivotWorldMatrix.Up;
				localPivot.y = -localPivot.y;
			}
			var newPosition = Vector3.Transform(Vector3(localPivot.x, localPivot.y, 0.0f) * spriteSize, worldMatrix);
			newPosition = .Floor(newPosition);
			pivotWorldMatrix.Translation = newPosition;
			return pivotWorldMatrix;
		}

		public void Add(Texture texture, int _spriteIndex, Vector3 spriteSize, Matrix4 worldMatrix, Color color = Color.White, Vector2 pivot = Vector2.Zero, SpriteFlags flags = 0)
		{
			var pivotWorldMatrix = GetPivotMatrix(spriteSize, worldMatrix, pivot, flags);
			Add(texture, _spriteIndex, spriteSize, pivotWorldMatrix, color);
		}


		public void Add(Texture texture, int _spriteIndex, Vector3 spriteSize, Matrix4 pivotWorldMatrix, Color color = Color.White)
		{
			if (texture != Texture)
			{
				Render();
				Texture = texture;
				textureScale = Texture.Size.xy00;
			}
			renderers.Add(SpriteRenderer() { worldMatrix = Matrix4.Transpose(pivotWorldMatrix), color = color, spriteIndex = _spriteIndex });
			if (renderers.Count == MaxCount)
			{
				Render();
			}
		}

		public void End()
		{
			Render();
		}

		private void Render()
		{
			if (renderers.Count == 0)
			{
				return;
			}
			// Fill data
			int dataIndex = 0;
			for (int i = 0; i < renderers.Count; ++i,dataIndex += InstanceVectorCount)
			{
				var renderer = renderers[i];
				instanceData[dataIndex + 0] = renderer.worldMatrix.r.RowX;
				instanceData[dataIndex + 1] = renderer.worldMatrix.r.RowY;
				instanceData[dataIndex + 2] = renderer.color.xyzw;
				instanceData[dataIndex + 3] = Texture.SpriteData[renderer.spriteIndex];
			}
			// Render
			RenderManager.RenderQuads(ViewId, Matrix4.Identity, Shader, renderers.Count, &instanceData[0], dataIndex, Settings, textureScale, scope bgfx.TextureHandle[](Texture.Handle), stateFlags, samplerFlags, programIndex);
			renderers.Clear();
			++BatchCount;
		}
	}
}
