using System;
using System.IO;
using System.Collections;

namespace GameCore
{
	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	class SpriteAnimationList
	{
		[JSON_Beef.Serialized]
		public List<SpriteAnimation> spriteAnimations = new List<SpriteAnimation>() ~ DeleteContainerAndItems!(_);

		public bool LoadFromJson(StringView jsonString)
		{
			switch (JSON_Beef.Serialization.JSONDeserializer.Deserialize<SpriteAnimationList>(jsonString, this)) {
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
