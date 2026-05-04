using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

namespace GameCore
{
	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	public class Sprite
	{
		[JSON_Beef.Serialized]
		public String name = new String() ~ delete _;
		[JSON_Beef.Serialized]
		public uint32 x, y;
		[JSON_Beef.Serialized]
		public uint32 width, height;
		[JSON_Beef.Serialized]
		public var convexHull = new List<float>() ~ delete _;
		[JSON_Beef.Serialized]
		public double moment = 0.0;
		[JSON_Beef.Serialized]
		public Vector2 center = .Zero;
		[JSON_Beef.Serialized]
		public Color averageColor = .White;

		public Texture texture;
		public int index;
		public Vector3 size;
		public Vector4 uvBounds = .Zero;
		public Mesh mesh = null ~ delete _;

		public static Dictionary<String, Sprite> spriteMap = new Dictionary<String, Sprite>() ~ delete _;

		public delegate bool UpdateVertexDelegate(Vector2 v, out Vector2 offset);

		public static Vector2 PushToBounds(Vector2 v)
		{
			return .(v.x < 0.5f ? 0.0f : 1.0f, v.y < 0.5f ? 0.0f : 1.0f);
			// Center of the 0..1 square
			Vector2 center = .(0.5f, 0.5f);

			// Direction from center
			float dx = v.x - center.x;
			float dy = v.y - center.y;

			// If already at center, just pick an arbitrary edge
			if (dx == 0 && dy == 0)
				return .(0.5f, 1.0f);

			// Compute scale needed to hit each boundary
			float tX = float.PositiveInfinity;
			if (dx > 0) tX = (1.0f - center.x) / dx;
			else if (dx < 0) tX = (0.0f - center.x) / dx;

			float tY = float.PositiveInfinity;
			if (dy > 0) tY = (1.0f - center.y) / dy;
			else if (dy < 0) tY = (0.0f - center.y) / dy;

			// Choose smallest positive t (first edge hit)
			float t = Math.Min(tX, tY);

			// Return point on edge
			return .(center.x + dx * t, center.y + dy * t);
		}

		public static Vector2 ClosestPointOnBounds(Vector2 v)
		{
			// Clamp to square first
			float cx = Math.Min(Math.Max(v.x, 0.0f), 1.0f);
			float cy = Math.Min(Math.Max(v.y, 0.0f), 1.0f);

			// Distances to each edge
			float distLeft   = cx - 0.0f;
			float distRight  = 1.0f - cx;
			float distBottom = cy - 0.0f;
			float distTop    = 1.0f - cy;

			// Find the closest edge
			float minDist = distLeft;
			int edge = 0; // 0=left, 1=right, 2=bottom, 3=top

			if (distRight < minDist) { minDist = distRight; edge = 1; }
			if (distBottom < minDist) { minDist = distBottom; edge = 2; }
			if (distTop < minDist) { minDist = distTop; edge = 3; }

			// Snap coordinate to that edge
			switch (edge)
			{
			case 0: cx = 0.0f; break; // Left
			case 1: cx = 1.0f; break; // Right
			case 2: cy = 0.0f; break; // Bottom
			case 3: cy = 1.0f; break; // Top
			}
			return .(cx, cy);
		}

		public bool GenerateShapeVertices(Vector2[] verts, Vector2 offset = .Zero, SpriteFlags spriteFlags = .None, UpdateVertexDelegate updateVertexDelegate = null)
		{
			var scale = size.xy;
			let flipU = (spriteFlags & .FlipU) != 0;
			let flipV = (spriteFlags & .FlipV) != 0;
			var index = 0;
			var increment = 1;
			if (flipU != flipV && (flipU || flipV))
			{
				index = convexHull.Count / 2 - 1;
				increment = -1;
			}
			bool updated = false;
			for (int i = 0; i < convexHull.Count; i += 2)
			{
				var point = Vector2(convexHull[i + 0], convexHull[i + 1]);
				if (flipU)
				{
					point.x = 1.0f - point.x;
				}
				if (flipV)
				{
					point.y = 1.0f - point.y;
				}
				var vertex = offset + point * scale;
				if (updateVertexDelegate != null)
				{
					var testVertex = offset + Vector2.Round(point) * scale;
					Vector2 updateOffset = .Zero;
					if (updateVertexDelegate(testVertex, out updateOffset))
					{
						vertex += updateOffset;
						updated = true;
					}
				}
				verts[index] = vertex;
				index += increment;
			}
			return updated;
		}

		public Chipmunk2D.Shape CreateShape(Chipmunk2D.Body body, Vector2 offset = .Zero, double radius = 0.0, bool setMoment = true, SpriteFlags spriteFlags = .None)
		{
			var inputVerts = scope Vector2[convexHull.Count / 2];
			GenerateShapeVertices(inputVerts, offset, spriteFlags);
			var verts = scope Chipmunk2D.Vector2[convexHull.Count / 2];
			for (int i = 0; i < inputVerts.Count; ++i)
			{
				verts[i] = Chipmunk2D.Vector2.FromVector(inputVerts[i]);
			}
			if (setMoment)
			{
				body.Moment = Chipmunk2D.Shape.MomentForPoly(body.Mass, verts, .(offset.x, offset.y), radius);
			}
			return body.AddPolyShape(verts, radius);
		}

		public Mesh CreateMesh()
		{
			if (mesh != null)
			{
				return mesh;
			}
			mesh = new Mesh();
			mesh.Initialize(convexHull.Count / 2, (convexHull.Count / 2 - 2) * 3);
			var textureOffset = Vector2(x, y);
			var scale = size.xy;
			var index = 0;
			for (int i = 0; i < convexHull.Count; i += 2)
			{
				var uv = Vector2(convexHull[i + 0], convexHull[i + 1]);
				let point = uv * scale;
				uv.y = 1.0f - uv.y;
				let textureUv = (textureOffset + uv * scale) / texture.ooSize;
				mesh.Vertices[index++] = .(point, .(textureUv.x, textureUv.y, uv.x, uv.y), uint32.MaxValue);
			}
			index = 0;
			for (int i = 0; i < mesh.Vertices.Count - 2; ++i)
			{
				var vertexIndex = (uint16)i;
				mesh.Indices[index++] = 0;
				mesh.Indices[index++] = vertexIndex + 1;
				mesh.Indices[index++] = vertexIndex + 2;
			}
			mesh.Create();
			return mesh;
		}

		public static Sprite Find(String name)
		{
			Sprite sprite;
			if (spriteMap.TryGetValue(name, out sprite))
			{
				return sprite;
			}
			return null;
		}
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	public class SpriteAtlas
	{
		[JSON_Beef.Serialized]
		public List<Sprite> sprites = new List<Sprite>() ~ delete _;

		public ~this()
		{
			for (var sprite in sprites)
			{
				delete sprite;
			}
		}
	}

	[Reflect(.Methods), AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true)]
	public class Texture : Resource
	{
		public bgfx.TextureHandle Handle { get; private set; }
		public int Width { get; private set; };
		public int Height { get; private set; }
		public Vector2 Size { get; private set; }
		public Vector2 ooSize { get; private set; }
		public Vector4[] SpriteData { get; set; }
		public SpriteAtlas SpriteAtlas { get; private set; }

		private Dictionary<String, Sprite> textureSpriteMap = new Dictionary<String, Sprite>() ~ delete _;

		protected override void OnLoad()
		{
			// Load texture
			var binaryFile = scope DynMemStream();
			if (!ResourceManager.ReadFile(scope $"{Hash}.ktx", binaryFile))
			{
				return;
			}
			var memory = bgfx.copy(binaryFile.Ptr, (uint32)binaryFile.Length);
			var info = bgfx.TextureInfo();
			Handle = bgfx.create_texture(memory, 0, 0, &info);

			if (Handle.Valid)
			{
				Width = (int)info.width;
				Height = (int)info.height;
				Size = .((float)Width, (float)Height);
				ooSize = .One / Size;

				// Load sprite
				SpriteAtlas = new SpriteAtlas();
				var jsonBinaryFile = scope DynMemStream();
				if (ResourceManager.ReadFile(scope $"{Hash}.json", jsonBinaryFile))
				{
					var jsonText = StringView((char8*)jsonBinaryFile.Ptr, (int)jsonBinaryFile.Length);
					JSON_Beef.Serialization.JSONDeserializer.Deserialize<SpriteAtlas>(jsonText, SpriteAtlas);
				}
				// Add default sprite
				if (SpriteAtlas.sprites.Count == 0)
				{
					var sprite = new Sprite();
					sprite.x = 0;
					sprite.y = 0;
					sprite.width = (uint32)Width;
					sprite.height = (uint32)Height;
					Path.GetFileNameWithoutExtension(Name, sprite.name);
					SpriteAtlas.sprites.Add(sprite);
					textureSpriteMap.Add(sprite.name, sprite);
				}
				// Setup data
				SpriteData = new Vector4[SpriteAtlas.sprites.Count];
				var index = 0;
				let ooWidth = 1.0f / (float)Width;
				let ooHeight = 1.0f / (float)Height;
				for (var sprite in SpriteAtlas.sprites)
				{
					sprite.index = index;
					sprite.size = Vector3((float)sprite.width, (float)sprite.height, 0.0f);
					sprite.uvBounds = .((float)sprite.x * ooWidth, (float)sprite.y * ooHeight, (float)(sprite.x + sprite.width) * ooWidth, (float)(sprite.y + sprite.height) * ooHeight);
					SpriteData[index] = sprite.uvBounds;
					sprite.texture = this;
					Sprite.spriteMap.TryAdd(sprite.name, sprite);
					textureSpriteMap.TryAdd(sprite.name, sprite);
					++index;
				}
				Log.Info("Loaded {0} with {1} sprites!", Name, SpriteData.Count);
			}
		}

		protected override void OnUnload()
		{
			for (var sprite in SpriteAtlas.sprites)
			{
				Sprite.spriteMap.Remove(sprite.name);
			}
			delete SpriteAtlas;
			delete SpriteData;
			bgfx.destroy_texture(Handle);
		}

		public Sprite FindSprite(StringView name)
		{
			Sprite sprite = null;
			textureSpriteMap.TryGetValue(scope String(name), out sprite);
			return sprite;
		}

		public Sprite FindSpriteByPosition(uint32 x, uint32 y)
		{
			for (var pair in textureSpriteMap)
			{
				if (pair.value.x == x && pair.value.y == y)
				{
					return pair.value;
				}
			}
			return null;
		}
	}
}
