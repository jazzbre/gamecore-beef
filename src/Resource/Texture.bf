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

		public Chipmunk2D.Shape CreateShape(Chipmunk2D.Body body, Vector2 offset = .Zero, double radius = 0.0, bool setMoment = true)
		{
			var verts = scope Chipmunk2D.Vector2[convexHull.Count / 2];
			var scale = size.xy;
			var index = 0;
			for (int i = 0; i < convexHull.Count; i += 2)
			{
				let point = offset + Vector2(convexHull[i + 0], convexHull[i + 1]) * scale;
				verts[index++] = Chipmunk2D.Vector2.FromVector(point);
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
