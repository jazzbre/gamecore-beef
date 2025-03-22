using System;
using System.IO;
using System.Collections;

namespace GameCore
{
	enum AutoTileRuleType
	{
		Tile,
		Prop
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	class AutoTileRuleSprite
	{
		[JSON_Beef.Serialized]
		public String spriteName = new String() ~ delete _;
		public Sprite sprite = null;

		public Sprite Sprite
		{
			get
			{
				return sprite;
			}
			set
			{
				sprite = value;
				spriteName.Clear();
				if (sprite != null)
				{
					spriteName.Append(sprite.name);
				}
			}
		}
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	class AutoTileRule
	{
		public const int Size = 5;

		[JSON_Beef.Serialized]
		public List<AutoTileRuleSprite> ruleSprites = new .() ~ DeleteContainerAndItems!(_);
		[JSON_Beef.Serialized]
		public List<int> pattern = new .() ~ delete _;
		[JSON_Beef.Serialized]
		public AutoTileRuleType type = .Tile;
		[JSON_Beef.Serialized]
		public bool collision = false;
		[JSON_Beef.Serialized]
		public bool enabled = true;
		[JSON_Beef.Serialized]
		public float probability = 1.0f;

		public void Initialize()
		{
			for (var sprite in ruleSprites)
			{
				sprite.sprite = Sprite.Find(sprite.spriteName);
			}
		}
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	class AutoTileLayer
	{
		[JSON_Beef.Serialized]
		public uint64 id = 0;
		[JSON_Beef.Serialized]
		public int32 gridX = 32;
		[JSON_Beef.Serialized]
		public int32 gridY = 32;
		[JSON_Beef.Serialized]
		public var name = new String("Empty") ~ delete _;
		[JSON_Beef.Serialized]
		public var color = Color.Black;
		[JSON_Beef.Serialized]
		public var rules = new List<AutoTileRule>() ~ DeleteContainerAndItems!(_);
		[JSON_Beef.Serialized]
		public bool enabled = true;

		public int index = -1;

		public Vector2 Size => .((float)gridX, (float)gridY);

		public void Initialize()
		{
			if (id == 0)
			{
				id = (uint64)DateTime.UtcNow.ToBinaryRaw();
			}
			for (var rule in rules)
			{
				rule.Initialize();
			}
		}

		public AutoTileRule Duplicate(AutoTileRule rule)
		{
			String jsonString = null;
			defer
			{
				delete jsonString;
			}
			switch (JSON_Beef.Serialization.JSONSerializer.Serialize<String>(rule)) {
			case .Ok(let val):
				jsonString = val;
				break;
			case .Err(let err):
				return null;
			}
			AutoTileRule newRule = new .();
			switch (JSON_Beef.Serialization.JSONDeserializer.Deserialize<AutoTileRule>(jsonString, newRule)) {
			case .Ok:
				break;
			case .Err(let err):
				delete newRule;
			}
			rules.Add(newRule);
			return newRule;
		}
	}

	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	class AutoTileList
	{
		[JSON_Beef.Serialized]
		public List<AutoTileLayer> layers = new List<AutoTileLayer>() ~ DeleteContainerAndItems!(_);

		public bool LoadFromJson(StringView jsonString)
		{
			switch (JSON_Beef.Serialization.JSONDeserializer.Deserialize<AutoTileList>(jsonString, this)) {
			case .Ok:
				break;
			case .Err(let err):
				return false;
			}
			return true;
		}

		public bool Load(StringView fileName)
		{
			var binaryFile = scope DynMemStream();
			if (!ResourceManager.ReadFile(fileName, binaryFile))
			{
				return false;
			}
			var jsonString = StringView((char8*)binaryFile.Ptr, (.)binaryFile.Length);
			return LoadFromJson(jsonString);
		}

		public String SaveToJson()
		{
			switch (JSON_Beef.Serialization.JSONSerializer.Serialize<String>(this)) {
			case .Ok(let val):
				return val;
			case .Err(let err):
				return null;
			}
		}

		public bool Save(StringView fileName)
		{
			// Convert to json and save
			var result = false;
			let jsonString = SaveToJson();
			if (jsonString == null)
			{
				return false;
			}
			switch (File.WriteAllText(fileName, jsonString)) {
			case .Ok(let val):
				result = true;
				break;
			case .Err(let val):
				result = false;
				break;
			}
			delete jsonString;
			return result;
		}

	}
}
