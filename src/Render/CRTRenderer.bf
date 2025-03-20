using System;
using Bgfx;

namespace GameCore
{
	class CRTRenderer
	{
		Mesh vertexbuffer = null ~ delete _;
		Mesh screenvertexbuffer = null ~ delete _;
		RenderTexture accumulatetexture_a = null ~ delete _;
		RenderTexture accumulatetexture_b = null ~ delete _;

		RenderTexture blurtexture_a = null ~ delete _;
		RenderTexture blurtexture_b = null ~ delete _;

		Shader crt_shader = null;
		Shader blur_shader = null;
		Shader accumulate_shader = null;
		Shader blend_shader = null;
		Shader copy_shader = null;

		bgfx.UniformHandle blur_uniform;
		bgfx.UniformHandle modulate_uniform;
		bgfx.UniformHandle modulateAndTime_uniform;
		bgfx.UniformHandle resolutionAndUseFrame_uniform;
		bgfx.UniformHandle cfg_a_uniform;
		bgfx.UniformHandle cfg_b_uniform;
		bgfx.UniformHandle cfg_c_uniform;
		bgfx.UniformHandle cfg_d_uniform;
		bgfx.UniformHandle cfg_e_uniform;

		float curvature, scanlines, shadow_mask, separation, ghosting, noise, flicker, vignette, distortion, aspect_lock,
			hpos, vpos, hsize, vsize, contrast, brightness, saturation, blur, degauss; // range -1.0f to 1.0f, default=0.0f

		public this()
		{
			let width = RenderManager.width;
			let height = RenderManager.height;
			scanlines = 0.75f;

			vertexbuffer = new Mesh();
			vertexbuffer.Initialize(0, 0);
			Vector2 v = RenderManager.IsRenderTextureYFlipped ? .(1, 0) : .(0, 1);
			vertexbuffer.Vertices.Add(.(.(-1, -1), .(0, v.x, 0, 0), 0xffff));
			vertexbuffer.Vertices.Add(.(.(1, -1), .(1, v.x, 0, 0), 0xffff));
			vertexbuffer.Vertices.Add(.(.(1, 1), .(1, v.y, 0, 0), 0xffff));
			vertexbuffer.Vertices.Add(.(.(-1, 1), .(0, v.y, 0, 0), 0xffff));
			vertexbuffer.Indices.Add(0);
			vertexbuffer.Indices.Add(1);
			vertexbuffer.Indices.Add(2);
			vertexbuffer.Indices.Add(0);
			vertexbuffer.Indices.Add(2);
			vertexbuffer.Indices.Add(3);
			vertexbuffer.Create();

			screenvertexbuffer = new Mesh();
			screenvertexbuffer.Initialize(0, 0);
			screenvertexbuffer.Vertices.Add(.(.(-1, -1), .(0, v.x, 0, 0), 0xffff));
			screenvertexbuffer.Vertices.Add(.(.(1, -1), .(1, v.x, 0, 0), 0xffff));
			screenvertexbuffer.Vertices.Add(.(.(1, 1), .(1, v.y, 0, 0), 0xffff));
			screenvertexbuffer.Vertices.Add(.(.(-1, 1), .(0, v.y, 0, 0), 0xffff));
			screenvertexbuffer.Indices.Add(0);
			screenvertexbuffer.Indices.Add(1);
			screenvertexbuffer.Indices.Add(2);
			screenvertexbuffer.Indices.Add(0);
			screenvertexbuffer.Indices.Add(2);
			screenvertexbuffer.Indices.Add(3);
			screenvertexbuffer.Create();

			accumulatetexture_a = new RenderTexture(width, height);
			accumulatetexture_b = new RenderTexture(width, height);
			blurtexture_a = new RenderTexture(width, height);
			blurtexture_b = new RenderTexture(width, height);

			blur_uniform = bgfx.create_uniform("blur", .Vec4, 1);
			modulate_uniform = bgfx.create_uniform("modulate", .Vec4, 1);
			modulateAndTime_uniform = bgfx.create_uniform("modulateAndTime", .Vec4, 1);
			resolutionAndUseFrame_uniform = bgfx.create_uniform("resolutionAndUseFrame", .Vec4, 1);
			cfg_a_uniform = bgfx.create_uniform("cfg_a", .Vec4, 1);
			cfg_b_uniform = bgfx.create_uniform("cfg_b", .Vec4, 1);
			cfg_c_uniform = bgfx.create_uniform("cfg_c", .Vec4, 1);
			cfg_d_uniform = bgfx.create_uniform("cfg_d", .Vec4, 1);
			cfg_e_uniform = bgfx.create_uniform("cfg_e", .Vec4, 1);

			crt_shader = ResourceManager.GetResource<Shader>("shaders/crt/crt");
			blur_shader = ResourceManager.GetResource<Shader>("shaders/crt/crt_blur");
			blend_shader = ResourceManager.GetResource<Shader>("shaders/crt/crt_blend");
			copy_shader = ResourceManager.GetResource<Shader>("shaders/crt/crt_copy");
			accumulate_shader = ResourceManager.GetResource<Shader>("shaders/crt/crt_acc");
		}

		public ~this()
		{
			bgfx.destroy_uniform(blur_uniform);
			bgfx.destroy_uniform(modulate_uniform);
			bgfx.destroy_uniform(modulateAndTime_uniform);
			bgfx.destroy_uniform(resolutionAndUseFrame_uniform);
			bgfx.destroy_uniform(cfg_a_uniform);
			bgfx.destroy_uniform(cfg_b_uniform);
			bgfx.destroy_uniform(cfg_c_uniform);
			bgfx.destroy_uniform(cfg_d_uniform);
			bgfx.destroy_uniform(cfg_e_uniform);
		}

		void RenderBlurCRT(RenderTexture source, RenderTexture target_a, RenderTexture target_b, float r, int width, int height)
		{
			bgfx.StateFlags state = .WriteRgb | .WriteA | .DepthTestAlways;
			bgfx.SamplerFlags sampler = .UClamp | .VClamp;
			Vector4 blur_vector = .(r / (float)width);
			{
				var viewId = RenderManager.NextViewId();
				bgfx.set_view_frame_buffer(viewId, target_b.FrameBufferHandle);
				bgfx.set_view_mode(viewId, .Sequential);
				bgfx.set_view_clear(viewId, 0, 0, 0.0f, 0);
				bgfx.set_view_rect(viewId, 0, 0, (uint16)width, (uint16)height);
				bgfx.set_view_name(viewId, "BlurCRT_A", 8);
				bgfx.touch(viewId);
				bgfx.set_uniform(blur_uniform, &blur_vector, 1);
				vertexbuffer.Render(viewId, .Identity, blur_shader, scope bgfx.TextureHandle[](source.TextureHandle), .White, state, sampler);
			}
			{
				var viewId = RenderManager.NextViewId();
				bgfx.set_view_frame_buffer(viewId, target_a.FrameBufferHandle);
				bgfx.set_view_mode(viewId, .Sequential);
				bgfx.set_view_clear(viewId, 0, 0, 0.0f, 0);
				bgfx.set_view_rect(viewId, 0, 0, (uint16)width, (uint16)height);
				bgfx.set_view_name(viewId, "BlurCRT_B", 8);
				bgfx.touch(viewId);
				bgfx.set_uniform(blur_uniform, &blur_vector, 1);
				vertexbuffer.Render(viewId, .Identity, blur_shader, scope bgfx.TextureHandle[](target_b.TextureHandle), .White, state, sampler);
			}
		}

		void RenderAccumulateCRT(RenderTexture texture0, RenderTexture texture1, RenderTexture target, int width, int height, float modulate)
		{
			bgfx.StateFlags state = .WriteRgb | .WriteA | .DepthTestAlways;
			bgfx.SamplerFlags sampler = .UClamp | .VClamp | .Point;
			Vector4 modulate_vector = .(modulate);
			var viewId = RenderManager.NextViewId();
			bgfx.set_view_frame_buffer(viewId, target.FrameBufferHandle);
			bgfx.set_view_mode(viewId, .Sequential);
			bgfx.set_view_clear(viewId, 0, 0, 0.0f, 0);
			bgfx.set_view_rect(viewId, 0, 0, (uint16)width, (uint16)height);
			bgfx.set_view_name(viewId, "AccumulateCRT", 10);
			bgfx.touch(viewId);
			bgfx.set_uniform(modulate_uniform, &modulate_vector, 1);
			vertexbuffer.Render(viewId, .Identity, accumulate_shader, scope bgfx.TextureHandle[](texture0.TextureHandle, texture1.TextureHandle), .White, state, sampler);
		}

		void RenderCopyCRT(RenderTexture source, RenderTexture destination, int width, int height)
		{
			bgfx.StateFlags state = .WriteRgb | .WriteA | .DepthTestAlways;
			bgfx.SamplerFlags sampler = .UClamp | .VClamp | .Point;
			var viewId = RenderManager.NextViewId();
			bgfx.set_view_frame_buffer(viewId, destination.FrameBufferHandle);
			bgfx.set_view_mode(viewId, .Sequential);
			bgfx.set_view_clear(viewId, 0, 0, 0.0f, 0);
			bgfx.set_view_rect(viewId, 0, 0, (uint16)width, (uint16)height);
			bgfx.set_view_name(viewId, "CopyCRT", 5);
			bgfx.touch(viewId);
			vertexbuffer.Render(viewId, .Identity, copy_shader, scope bgfx.TextureHandle[](source.TextureHandle), .White, state, sampler);
		}

		void RenderBlendCRT(RenderTexture texture0, RenderTexture texture1, RenderTexture target, int width, int height, float modulate)
		{
			bgfx.StateFlags state = .WriteRgb | .WriteA | .DepthTestAlways;
			bgfx.SamplerFlags sampler = .UClamp | .VClamp | .Point;
			Vector4 modulate_vector = .(modulate);
			var viewId = RenderManager.NextViewId();
			bgfx.set_view_frame_buffer(viewId, target.FrameBufferHandle);
			bgfx.set_view_mode(viewId, .Sequential);
			bgfx.set_view_clear(viewId, 0, 0, 0.0f, 0);
			bgfx.set_view_rect(viewId, 0, 0, (uint16)width, (uint16)height);
			bgfx.set_view_name(viewId, "BlendCRT", 8);
			bgfx.touch(viewId);
			bgfx.set_uniform(modulate_uniform, &modulate_vector, 1);
			vertexbuffer.Render(viewId, .Identity, blend_shader, scope bgfx.TextureHandle[](texture0.TextureHandle, texture1.TextureHandle), .White, state, sampler);
		}

		public void Render(RenderTexture sourceTexture, int windowWidth, int windowHeight)
		{
			let width = RenderManager.width;
			let height = RenderManager.height;

			RenderBlurCRT(accumulatetexture_b, blurtexture_a, blurtexture_b, 1.0f, width, height);
			RenderAccumulateCRT(sourceTexture, blurtexture_a, accumulatetexture_a, width, height, 0.5f);
			RenderCopyCRT(accumulatetexture_a, accumulatetexture_b, width, height);
			RenderBlendCRT(sourceTexture, accumulatetexture_b, accumulatetexture_a, width, height, 1.0f);
			RenderBlurCRT(accumulatetexture_a, accumulatetexture_a, blurtexture_b, 0.05f, width, height);
			RenderBlurCRT(accumulatetexture_a, blurtexture_a, blurtexture_b, 1.0f, width, height);

			bgfx.StateFlags state = .WriteRgb | .WriteA | .DepthTestAlways;
			bgfx.SamplerFlags sampler = .UClamp | .VClamp | .Point;

			var renderOffsetAndSize = GetRenderOffsetAndSize(windowWidth, windowHeight);
			{
				uint16 viewId = RenderManager.NextViewId();
				bgfx.set_view_clear(viewId, (uint)(bgfx.ClearFlags.Color | bgfx.ClearFlags.Depth), 0, 1.0f, 0);
				bgfx.set_view_rect(viewId, 0, 0, (uint16)windowWidth, (uint16)windowHeight);
				bgfx.touch(viewId);
			}

			uint16 viewId = RenderManager.NextViewId();
			{
				bgfx.set_view_clear(viewId, 0, 0, 1.0f, 0);
				bgfx.set_view_rect(viewId, (uint16)renderOffsetAndSize.x, (uint16)renderOffsetAndSize.y, (uint16)renderOffsetAndSize.z, (uint16)renderOffsetAndSize.w);
				bgfx.touch(viewId);
			}
			bgfx.set_view_name(viewId, "Present", 7);
			Vector4 modulateAndTime_vector = .(1.0f, 1.0f, 1.0f, (float)Time.Time);
			Vector4 resolutionAndUseFrame_vector = .((float)renderOffsetAndSize.z, (float)renderOffsetAndSize.w, 0.0f, 0.0f);
			// 4k = (0.75, 6), 1080p = (1.5, 3)
			float crtScale = 0.33f;
			scanlines = 1.5f * crtScale;
			shadow_mask = 3.0f / crtScale;
			Vector4 cfg_a_vector = .(curvature, scanlines, shadow_mask, separation);
			Vector4 cfg_b_vector = .();
			Vector4 cfg_c_vector = .();
			Vector4 cfg_d_vector = .();
			Vector4 cfg_e_vector = .();
			bgfx.set_uniform(modulateAndTime_uniform, &modulateAndTime_vector, 1);
			bgfx.set_uniform(resolutionAndUseFrame_uniform, &resolutionAndUseFrame_vector, 1);
			bgfx.set_uniform(cfg_a_uniform, &cfg_a_vector, 1);
			bgfx.set_uniform(cfg_b_uniform, &cfg_b_vector, 1);
			bgfx.set_uniform(cfg_c_uniform, &cfg_c_vector, 1);
			bgfx.set_uniform(cfg_d_uniform, &cfg_d_vector, 1);
			bgfx.set_uniform(cfg_e_uniform, &cfg_e_vector, 1);
			screenvertexbuffer.Render(viewId, .Identity, crt_shader, scope bgfx.TextureHandle[](accumulatetexture_a.TextureHandle, blurtexture_a.TextureHandle), .White, state, sampler);
		}

		public static Vector2 Curve(Vector2 _uv)
		{
			var uv = (_uv - Vector2.Half) * 2.0f;
			uv *= Vector2(1.049f, 1.042f);
			uv -= Vector2(-0.008f, 0.008f);
			uv.x *= 1.0f + Math.Pow((Math.Abs(uv.y) / 5.0f), 2.0f);
			uv.y *= 1.0f + Math.Pow((Math.Abs(uv.x) / 4.0f), 2.0f);
			uv  = (uv * 0.5f) + Vector2.Half;
			return uv;
		}

		public static Vector2 InverseCurve(Vector2 _uv)
		{
			var uv = (_uv - Vector2.Half) * 2.0f;
			// Approximate inverse of the nonlinear transformation
			uv.y /= 1.0f + Math.Pow(Math.Abs(uv.x) / 4.0f, 2.0f);
			uv.x /= 1.0f + Math.Pow(Math.Abs(uv.y) / 5.0f, 2.0f);
			uv += Vector2(-0.008f, 0.008f);
			uv /= Vector2(1.049f, 1.042f);
			uv = (uv * 0.5f) + Vector2.Half;
			return uv;
		}

		public static Vector4 GetRenderOffsetAndSize(int windowWidth, int windowHeight)
		{
			var scale = Math.Min((float)windowWidth / (float)RenderManager.width, (float)windowHeight / (float)RenderManager.height);
			var snappedScale = Math.Floor(scale);
			if (Math.Abs(scale - snappedScale) <= 0.20001f)
			{
				scale = snappedScale;
			}
			Vector2 renderSize = .(Math.Floor(RenderManager.width * scale), Math.Floor(RenderManager.height * scale));
			Vector2 renderOffset = .((windowWidth / 2 - renderSize.x / 2), (windowHeight / 2 - renderSize.y / 2));
			return Vector4(renderOffset, renderSize);
		}

	}
}
