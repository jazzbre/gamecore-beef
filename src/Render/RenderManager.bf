using System;
using System.Collections;
using Bgfx;

namespace GameCore
{
	enum RenderShaderType
	{
		Default,
		Font,
		Field,
		Mesh3D,
		StaticMesh3D,
		Dialog,
		Particle,
		Last
	}

	abstract class PostProcess
	{
		public abstract void OnRender(RenderTexture sourceRenderTexture);
	}

	class BloomPostProcess : PostProcess
	{
		public override void OnRender(RenderTexture sourceRenderTexture)
		{
		}
	}

	static class RenderManager
	{
		public struct Statistics
		{
			public uint64 submitCount = 0;
			public uint64 blitCount = 0;

			public void Clear() mut
			{
				submitCount = 0;
				blitCount = 0;
			}
		}

		public static var statistics = Statistics();

		public static SpriteBatchRenderer batchRenderer;
		public static SpriteBatchRenderer entityBatchRenderer;

		public static List<RenderTexture> temporaryRenderTextures = new List<RenderTexture>();
		public static List<RenderTexture> temporaryHalfRenderTextures = new List<RenderTexture>();

		public static bgfx.TextureHandle readBackTextureHandle = .Null;

		public static RenderTexture temporaryRenderTextureWithDepth;

		public static int width = 1280; // 320 * 1 + 320 / 4;
		public static int height = 720; //180 * 1 + 180 / 4;
		public static float ooWidth, ooHeight;
		public static var viewBounds = Bounds2();
		public static float aspectRatio = 1.0f;

		public static bgfx.VertexBufferHandle batchVertexBufferHandle;
		public static bgfx.IndexBufferHandle batchIndexBufferHandle;
		public static int batchVertexCount;
		public static int batchIndexCount;
		public static bgfx.VertexBufferHandle batchTesselatedVertexBufferHandle;
		public static bgfx.IndexBufferHandle batchTesselatedIndexBufferHandle;
		public static int batchTesselatedVertexCount;
		public static int batchTesselatedIndexCount;
		public static bgfx.VertexLayout batchVertexLayout;

		public static var textureUniformHandles = new bgfx.UniformHandle[8] ~ delete _;
		public static bgfx.UniformHandle colorUniformHandle;
		public static bgfx.UniformHandle timeUniformHandle;
		public static bgfx.UniformHandle settingsUniformHandle;
		public static bgfx.UniformHandle textureScaleUniformHandle;
		public static bgfx.UniformHandle instanceDataUniformHandle;
		public static bgfx.UniformHandle instanceDataPSUniformHandle;
		public static bgfx.UniformHandle shUniformHandle;

		public static var shaders = new Shader[(int)RenderShaderType.Last] ~ DeleteAndNullify!(_);

		public static uint16 PreViewId { get; private set; }
		public static uint16 ViewId { get; private set; }
		public static uint16 PostViewId { get; private set; }

		public static Vector4 ShaderData { get; private set; }

		public static bool capture = true;

		public static bool IsRenderTextureYFlipped { get; private set; }

		public static bgfx.RendererType RendererType { get; private set; }
		public static bgfx.RendererType ShaderRendererType { get; private set; }

		public static SH9 sh9 = new .() ~ delete _;

		public static Shader GetShader(RenderShaderType type)
		{
			return shaders[(int)type];
		}

		public static void PreInitialize()
		{
			RendererType = bgfx.get_renderer_type();
			ShaderRendererType = RendererType == .Direct3D12 ? .Direct3D11 : RendererType;
			IsRenderTextureYFlipped = RendererType != .OpenGL && RendererType != .OpenGLES;
		}

		public static bool Initialize(int maxBatchCount = 128)
		{
			Log.Info(scope $"Render target {width}x{height}");
			SDL2.SDL.Log(scope $"Renderer:{RendererType}, {width}x{height}, IsRenderTextureYFlipped {IsRenderTextureYFlipped}");
			ooWidth = 1.0f / width;
			ooHeight = 1.0f / height;
			aspectRatio = width * ooHeight;
			viewBounds = .(.Zero, .(width, height));
			batchRenderer = new .();
			entityBatchRenderer = new .();
			for (int i = 0; i < 2; ++i)
			{
				temporaryRenderTextures.Add(new .(width, height));
				temporaryHalfRenderTextures.Add(new .(width, height, .RGBA16F));
			}
			temporaryRenderTextureWithDepth = new .(width, height, .RGBA16F, .D24S8);
			// Generate batch buffers
			// Setup buffers
			bgfx.vertex_layout_begin(&batchVertexLayout, bgfx.get_renderer_type());
			bgfx.vertex_layout_add(&batchVertexLayout, bgfx.Attrib.Position, 3, bgfx.AttribType.Float, false, false);
			bgfx.vertex_layout_end(&batchVertexLayout);
			// Default quad
			CreateQuad(1, 1, maxBatchCount, out batchVertexBufferHandle, out batchIndexBufferHandle, out batchVertexCount, out batchIndexCount);
			// Tesselated
			CreateQuad(2, 2, maxBatchCount, out batchTesselatedVertexBufferHandle, out batchTesselatedIndexBufferHandle, out batchTesselatedVertexCount, out batchTesselatedIndexCount);
			// Load shaders
			shaders[(int)RenderShaderType.Default] = ResourceManager.GetResource<Shader>("shaders/generic_sprite_texture");
			shaders[(int)RenderShaderType.Font] = ResourceManager.GetResource<Shader>("shaders/font_sprite_texture");
			shaders[(int)RenderShaderType.Field] = ResourceManager.GetResource<Shader>("shaders/field");
			shaders[(int)RenderShaderType.Mesh3D] = ResourceManager.GetResource<Shader>("shaders/mesh3d");
			shaders[(int)RenderShaderType.StaticMesh3D] = ResourceManager.GetResource<Shader>("shaders/staticmesh3d");
			shaders[(int)RenderShaderType.Dialog] = ResourceManager.GetResource<Shader>("shaders/dialog");
			shaders[(int)RenderShaderType.Particle] = ResourceManager.GetResource<Shader>("shaders/particle");
			textureUniformHandles[0] = bgfx.create_uniform("s_texture", bgfx.UniformType.Sampler, 1);
			for (int i = 1; i < textureUniformHandles.Count; ++i)
			{
				textureUniformHandles[i] = bgfx.create_uniform(scope $"s_texture{i + 1}" , bgfx.UniformType.Sampler, 1);
			}
			colorUniformHandle = bgfx.create_uniform("s_color", bgfx.UniformType.Vec4, 1);
			timeUniformHandle = bgfx.create_uniform("s_time", bgfx.UniformType.Vec4, 1);
			settingsUniformHandle = bgfx.create_uniform("s_settings", bgfx.UniformType.Vec4, 1);
			textureScaleUniformHandle = bgfx.create_uniform("s_textureScale", bgfx.UniformType.Vec4, 1);
			instanceDataUniformHandle = bgfx.create_uniform("s_instanceData", bgfx.UniformType.Vec4, (uint16)256);
			instanceDataPSUniformHandle = bgfx.create_uniform("s_instanceDataPS", bgfx.UniformType.Vec4, (uint16)8);
			shUniformHandle = bgfx.create_uniform("s_sh", bgfx.UniformType.Vec4, (uint16)9);
			if (capture)
			{
				readBackTextureHandle = bgfx.create_texture_2d((.)width, (.)height, false, 1, .RGBA8, (.)(bgfx.TextureFlags.ReadBack | bgfx.TextureFlags.BlitDst), null);
			}

			return true;
		}

		public static void Finalize()
		{
			for (var textureUniformHandle in textureUniformHandles)
			{
				bgfx.destroy_uniform(textureUniformHandle);
			}
			bgfx.destroy_uniform(colorUniformHandle);
			bgfx.destroy_uniform(timeUniformHandle);
			bgfx.destroy_uniform(settingsUniformHandle);
			bgfx.destroy_uniform(textureScaleUniformHandle);
			bgfx.destroy_uniform(instanceDataUniformHandle);
			bgfx.destroy_uniform(instanceDataPSUniformHandle);
			bgfx.destroy_uniform(shUniformHandle);
			delete batchRenderer;
			delete entityBatchRenderer;
			DeleteContainerAndItems!(temporaryRenderTextures);
			DeleteContainerAndItems!(temporaryHalfRenderTextures);
			bgfx.destroy_vertex_buffer(batchVertexBufferHandle);
			bgfx.destroy_index_buffer(batchIndexBufferHandle);
			delete temporaryRenderTextureWithDepth;

			if (readBackTextureHandle.Valid)
			{
				bgfx.destroy_texture(readBackTextureHandle);
			}
		}

		public static void OnPreRender(float timeStep)
		{
			PreViewId = 0;
			ViewId = 60;
			PostViewId = 100;
			ShaderData = .((float)Time.Time, (float)(Time.Time * 0.1), timeStep, 1.0f / timeStep);
			statistics.Clear();
		}

		public static void OnPostRender()
		{
		}

		public static uint16 NextPreViewId()
		{
			return ++PreViewId;
		}

		public static uint16 NextViewId()
		{
			return ++ViewId;
		}

		public static uint16 NextPostViewId()
		{
			return ++PostViewId;
		}

		public static void PostProcess(Vector2 cameraPosition, RenderTexture sourceRenderTexture, List<PostProcess> postProcess)
		{
			var shaders = scope Shader[](ResourceManager.GetResource<Shader>("shaders/bloom_mask"), ResourceManager.GetResource<Shader>("shaders/blur_horizontal"), ResourceManager.GetResource<Shader>("shaders/blur_vertical"));
			int targetIndex = 1;
			for (int i = 0; i < 4; ++i)
			{
				targetIndex = targetIndex ^ 1;
				var viewId = NextViewId();
				var targetRenderTexture = temporaryRenderTextures[targetIndex];
				if (i == 0)
				{
					BlitWithShader(viewId, shaders[0], targetRenderTexture, sourceRenderTexture.TextureHandle, .WriteRgb | .WriteA | .DepthTestAlways, .UClamp | .VClamp, false);
				} else
				{
					BlitWithShader(viewId, shaders[1 + (i - 1) % 2], targetRenderTexture, temporaryRenderTextures[targetIndex ^ 1].TextureHandle, .WriteRgb | .WriteA | .DepthTestAlways, .UClamp | .VClamp, false);
				}
			}
			bgfx.blit(NextViewId(), temporaryHalfRenderTextures[0].TextureHandle, 0, 0, 0, 0, sourceRenderTexture.TextureHandle, 0, 0, 0, 0, (uint16)sourceRenderTexture.Width, (uint16)sourceRenderTexture.Height, 0);
			++RenderManager.statistics.blitCount;
			{
				var bloomApplyShader = ResourceManager.GetResource<Shader>("shaders/bloom_apply");
				Vector4 settings = .(cameraPosition.x / viewBounds.Size.x, cameraPosition.y / viewBounds.Size.y, 0, 0);
				settings.x += (.)(Time.Time * 0.01);
				settings.y += (.)(Time.Time * -0.005);
				bgfx.set_uniform(settingsUniformHandle, &settings.x, 1);
				BlitWithShader(NextViewId(), bloomApplyShader, sourceRenderTexture, scope bgfx.TextureHandle[](temporaryHalfRenderTextures[0].TextureHandle, temporaryRenderTextures[targetIndex].TextureHandle), .WriteRgb | .WriteA | .DepthTestAlways, .UClamp | .VClamp | .Point, false);
			}
		}

		public static void BlitWithShader(uint16 viewId, Shader shader, RenderTexture targetRenderTexture, bgfx.TextureHandle sourceTextureHandle, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, bool clear = true, int shiftScale = 0, int programIndex = 0)
		{
			let width = targetRenderTexture.Width >> shiftScale;
			let height = targetRenderTexture.Height >> shiftScale;
			bgfx.set_view_clear(viewId, clear ? (uint16)(bgfx.ClearFlags.Color | bgfx.ClearFlags.Depth) : 0, 0, 1.0f, 0);
			bgfx.set_view_frame_buffer(viewId, targetRenderTexture.FrameBufferHandle);
			bgfx.set_view_rect(viewId, 0, 0, (uint16)width, (uint16)height);
			bgfx.set_view_mode(viewId, .Sequential);
			var view = Matrix4.Identity;
			var projection = RenderManager.CreatePerspectiveOrtho(0, (float)width, 0, (float)height, 0.0f, 1.0f, 0.0f);
			bgfx.set_view_transform(viewId, view.Ptr(), projection.Ptr());
			bgfx.set_view_name(viewId, "Blit", 4);
			bgfx.touch(viewId);
			RenderManager.RenderScreenQuad(viewId, shader, sourceTextureHandle, _stateFlags, _samplerFlags, programIndex);
		}


		public static void BlitWithShader(uint16 viewId, Shader shader, RenderTexture targetRenderTexture, bgfx.TextureHandle[] textureHandles, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, bool clear = true, int shiftScale = 0, int programIndex = 0)
		{
			let width = targetRenderTexture.Width >> shiftScale;
			let height = targetRenderTexture.Height >> shiftScale;
			bgfx.set_view_clear(viewId, clear ? (uint16)(bgfx.ClearFlags.Color | bgfx.ClearFlags.Depth) : 0, 0, 1.0f, 0);
			bgfx.set_view_frame_buffer(viewId, targetRenderTexture.FrameBufferHandle);
			bgfx.set_view_rect(viewId, 0, 0, (uint16)width, (uint16)height);
			bgfx.set_view_mode(viewId, .Sequential);
			var view = Matrix4.Identity;
			var projection = RenderManager.CreatePerspectiveOrtho(0, (float)width, 0, (float)height, 0.0f, 1.0f, 0.0f);
			bgfx.set_view_transform(viewId, view.Ptr(), projection.Ptr());
			bgfx.set_view_name(viewId, "Blit2", 5);
			bgfx.touch(viewId);
			RenderManager.RenderScreenQuad(viewId, shader, textureHandles, _stateFlags, _samplerFlags, programIndex);
		}


		public static void RenderScreenQuad(uint16 viewId, Shader shader, bgfx.TextureHandle textureHandle, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int programIndex = 0)
		{
			var stateFlags = _stateFlags != 0 ? _stateFlags : bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.DepthTestAlways | bgfx.blend_function(bgfx.StateFlags.BlendSrcAlpha, bgfx.StateFlags.BlendInvSrcAlpha);
			var samplerFlags = _samplerFlags != 0 ? (uint32)_samplerFlags : (uint32)(bgfx.SamplerFlags.UClamp | bgfx.SamplerFlags.VClamp);
			var identity = Matrix4.Identity;
			bgfx.set_transform(identity.Ptr(), 1);
			bgfx.set_state((uint64)stateFlags, 0);
			bgfx.set_vertex_buffer(0, batchVertexBufferHandle, 0, 4);
			bgfx.set_index_buffer(batchIndexBufferHandle, 0, 6);
			if (textureHandle.idx != uint16.MaxValue)
			{
				bgfx.set_texture(0, textureUniformHandles[0], textureHandle, samplerFlags);
			}
			bgfx.submit(viewId, shader.Programs[programIndex], 0, (uint8)bgfx.DiscardFlags.All);
			++RenderManager.statistics.submitCount;
		}

		public static void RenderScreenQuad(uint16 viewId, Shader shader, bgfx.TextureHandle[] textureHandles, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int programIndex = 0)
		{
			var stateFlags = _stateFlags != 0 ? _stateFlags : bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.DepthTestAlways | bgfx.blend_function(bgfx.StateFlags.BlendSrcAlpha, bgfx.StateFlags.BlendInvSrcAlpha);
			var identity = Matrix4.Identity;
			bgfx.set_transform(identity.Ptr(), 1);
			bgfx.set_state((uint64)stateFlags, 0);
			bgfx.set_vertex_buffer(0, batchVertexBufferHandle, 0, 4);
			bgfx.set_index_buffer(batchIndexBufferHandle, 0, 6);
			if (textureHandles != null)
			{
				for (int i = 0; i < textureHandles.Count; ++i)
				{
					bgfx.set_texture((uint8)i, textureUniformHandles[i], textureHandles[i], _samplerFlags != 0 ? (uint32)_samplerFlags : (uint32)(bgfx.SamplerFlags.UClamp | bgfx.SamplerFlags.VClamp));
				}
			}
			bgfx.set_uniform(timeUniformHandle, &ShaderData.x, 1);
			bgfx.submit(viewId, shader.Programs[programIndex], 0, (uint8)bgfx.DiscardFlags.All);
			++RenderManager.statistics.submitCount;
		}

		public static void RenderMeshes(uint16 viewId, Matrix4 _worldMatrix, Shader shader, int quadCount, Vector4* instanceData, int instanceDataCount, Vector4 settings, Vector4 textureScale, bgfx.TextureHandle[] textureHandles, bgfx.StateFlags _stateFlags = 0, bgfx.SamplerFlags _samplerFlags = 0, int programIndex = 0, bool tesselated = false)
		{
			var stateFlags = _stateFlags != 0 ? _stateFlags : bgfx.StateFlags.WriteRgb | bgfx.StateFlags.WriteA | bgfx.StateFlags.DepthTestAlways | bgfx.blend_function(bgfx.StateFlags.BlendSrcAlpha, bgfx.StateFlags.BlendInvSrcAlpha);
			var samplerFlags = _samplerFlags != 0 ? (uint32)_samplerFlags : (uint32)(bgfx.SamplerFlags.UClamp | bgfx.SamplerFlags.VClamp | bgfx.SamplerFlags.Point);
				// Render
			var worldMatrix = _worldMatrix;

			bgfx.VertexBufferHandle vertexBuffer;
			bgfx.IndexBufferHandle indexBuffer;
			int vertexCount;
			int indexCount;

			if (tesselated)
			{
				vertexBuffer = batchTesselatedVertexBufferHandle;
				indexBuffer = batchTesselatedIndexBufferHandle;
				vertexCount = batchTesselatedVertexCount;
				indexCount = batchTesselatedIndexCount;
			}
			else
			{
				vertexBuffer = batchVertexBufferHandle;
				indexBuffer = batchIndexBufferHandle;
				vertexCount = batchVertexCount;
				indexCount = batchIndexCount;
			}

			bgfx.set_transform(worldMatrix.Ptr(), 1);
			bgfx.set_state((uint64)stateFlags, 0);
			bgfx.set_uniform(instanceDataUniformHandle, instanceData, (uint16)instanceDataCount);
			bgfx.set_uniform(timeUniformHandle, &ShaderData.x, 1);
			bgfx.set_uniform(settingsUniformHandle, &settings.x, 1);
			bgfx.set_uniform(textureScaleUniformHandle, &textureScale.x, 1);
			bgfx.set_vertex_buffer(0, vertexBuffer, 0, (uint32)(quadCount * vertexCount));
			bgfx.set_index_buffer(indexBuffer, 0, (uint32)(quadCount * indexCount));
			if (textureHandles != null)
			{
				for (int i = 0; i < textureHandles.Count; ++i)
				{
					if (!textureHandles[i].Valid)
					{
						continue;
					}
					bgfx.set_texture((uint8)i, textureUniformHandles[i], textureHandles[i], samplerFlags);
				}
			}
			bgfx.submit(viewId, shader.Programs[programIndex], 0, (uint8)bgfx.DiscardFlags.All);
			++RenderManager.statistics.submitCount;
		}

		public static void FixProjectionMatrix(ref Matrix4 projection)
		{
			if (!IsRenderTextureYFlipped)
			{
				return;
			}
			projection.d[5] = -projection.d[5];
			projection.v.m31 = -projection.v.m31;
		}

		public static bgfx.StateFlags GetCullingState(bool ccw)
		{
			if (!IsRenderTextureYFlipped)
			{
				return ccw ? .CullCcw : .CullCw;
			}
			return ccw ? .CullCw : .CullCcw;
		}

		public static Matrix4 CreatePerspectiveOrtho(float _left, float _right, float _bottom, float _top, float _near, float _far, float _offset = 0.0f)
		{
			var projection = Matrix4.CreatePerspectiveOrtho(_left, _right, _bottom, _top, _near, _far, _offset, false);
			FixProjectionMatrix(ref projection);
			return projection;
		}

		public static void SetViewRectangle(uint16 _id, uint16 _x, uint16 _y, uint16 _width, uint16 _height)
		{
			if (IsRenderTextureYFlipped)
			{
				bgfx.set_view_rect(_id, _x, (.)(height - _height - _y), _width, _height);
			} else
			{
				bgfx.set_view_rect(_id, _x, _y, _width, _height);
			}
		}

		public static void CreateQuad(int tessX, int tessY, int batchCount, out bgfx.VertexBufferHandle outVertexBuffer, out bgfx.IndexBufferHandle outIndexBuffer, out int vertsPerBatch, out int indicesPerBatch)
		{
			vertsPerBatch = (tessX + 1) * (tessY + 1);
			indicesPerBatch = tessX * tessY * 6;

			int totalVertCount = vertsPerBatch * batchCount;
			int totalIndexCount = indicesPerBatch * batchCount;

			var vertices = scope Vector3[totalVertCount];
			var indices  = scope uint16[totalIndexCount];

			int v = 0;
			int i = 0;
			float instanceIndex = 0.0f;

			for (int batch = 0; batch < batchCount; batch++,instanceIndex += 4.0f)
			{
				int baseVertex = v;

				// Create vertices for this batch
				for (int y = 0; y <= tessY; y++)
				{
					float fy = (float)y / (float)tessY;
					for (int x = 0; x <= tessX; x++)
					{
						float fx = (float)x / (float)tessX;
						vertices[v++] = Vector3(fx, fy, instanceIndex);
					}
				}

				// Create indices for this batch
				for (int ty = 0; ty < tessY; ty++)
				{
					for (int tx = 0; tx < tessX; tx++)
					{
						uint16 v0 = (uint16)(baseVertex + ty * (tessX + 1) + tx);
						uint16 v1 = (uint16)(v0 + 1);
						uint16 v2 = (uint16)(v0 + (tessX + 1));
						uint16 v3 = (uint16)(v2 + 1);

						// First triangle
						indices[i++] = v0;
						indices[i++] = v1;
						indices[i++] = v3;

						// Second triangle
						indices[i++] = v0;
						indices[i++] = v3;
						indices[i++] = v2;
					}
				}
			}

			outVertexBuffer = bgfx.create_vertex_buffer(bgfx.copy(&vertices[0], (uint32)(vertices.Count * sizeof(Vector3))), &batchVertexLayout, 0);
			outIndexBuffer = bgfx.create_index_buffer(bgfx.copy(&indices[0], (uint32)(indices.Count * sizeof(uint16))), 0);
		}

		public static void SetSHRenderState()
		{
			bgfx.set_uniform(shUniformHandle, &sh9.sh[0].x, 9);
		}
	}
}