using System;
using System.Collections;

namespace GameCore
{
	static class AutoTileManager
	{
		private const StringView defaultFileName = "data/autotile";

		private static AutoTileList autoTileList = new AutoTileList() ~ delete _;
		private static HashSet<Sprite> usedSprites = new .() ~ delete _;

		public static bool debugMode = false;

		public static List<AutoTileLayer> AutoTileLayers => autoTileList.layers;
		public static var AutoTileLayersById = new Dictionary<uint64, AutoTileLayer>() ~ delete _;

		public static bool IsSpriteUsed(Sprite sprite)
		{
			return usedSprites.Contains(sprite);
		}

		public static AutoTileLayer Duplicate(AutoTileLayer layer)
		{
			AutoTileList list = scope .();
			list.layers.Add(layer);
			var json = list.SaveToJson();
			list.LoadFromJson(json);
			delete json;
			var newLayer = list.layers[list.layers.Count - 1];
			AutoTileLayers.Add(newLayer);
			UpdateDictionary();
			list.layers.Clear();
			return newLayer;
		}

		public static void UpdateDictionary()
		{
			usedSprites.Clear();
			AutoTileLayersById.Clear();
			int index = 0;
			for (var layer in autoTileList.layers)
			{
				layer.Initialize();
				layer.index = index++;
				AutoTileLayersById.TryAdd(layer.id, layer);
				for (var rule in layer.rules)
				{
					for (var sprite in rule.ruleSprites)
					{
						usedSprites.Add(sprite.sprite);
					}
				}
			}
		}

		public static void SaveEditor()
		{
			UpdateDictionary();
			autoTileList.Save(scope $"{ResourceManager.buildtimeResourcesPath}/{defaultFileName}.json");
		}

		public static void OnInitialize()
		{
			var resource = ResourceManager.GetResource<JsonResource>(defaultFileName);
			if (resource != null)
			{
				autoTileList.Load(resource.JsonName);
			}
			UpdateDictionary();
		}

		public static void OnFinalize()
		{
		}

	}
}
