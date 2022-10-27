using System;
using System.IO;
using System.Collections;

namespace Dedkeni
{
	[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	class ResourceList
	{
		[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
		public class ResourceEntry
		{
			[JSON_Beef.Serialized]
			public String name = new String() ~ delete _;
			[JSON_Beef.Serialized]
			public String hash = new String() ~ delete _;
		}

		[AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
		public class TypeEntry
		{
			[JSON_Beef.Serialized]
			public String name = new String() ~ delete _;
			[JSON_Beef.Serialized]
			public var resources = new List<ResourceEntry>() ~ DeleteContainerAndItems!(_);
		}

		[JSON_Beef.Serialized]
		public var types = new List<TypeEntry>() ~ DeleteContainerAndItems!(_);

		public bool LoadFromJson(StringView jsonString)
		{
			switch (JSON_Beef.Serialization.JSONDeserializer.Deserialize<ResourceList>(jsonString, this)) {
			case .Ok:
				break;
			case .Err(let err):
				return false;
			}
			for (var typeEntry in types)
			{
				var type = JSON_Beef.Util.JSONUtil.GetObjectType(typeEntry.name);
				for (var resourceEntry in typeEntry.resources)
				{
					ResourceManager.AddResource(type, resourceEntry.name, resourceEntry.hash);
				}
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
			types.Clear();

			for (var pair in ResourceManager.ResourcesByType)
			{
				var typeEntry = new TypeEntry();
				pair.key.GetFullName(typeEntry.name);
				types.Add(typeEntry);
				for (var resource in pair.value)
				{
					var resourceEntry = new ResourceEntry();
					resourceEntry.name.Append(resource.Name);
					resourceEntry.hash.Append(resource.Hash);
					typeEntry.resources.Add(resourceEntry);
				}
			}

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
