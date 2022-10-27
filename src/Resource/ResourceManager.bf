using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using System.Threading;
using Bgfx;
using jazzutils;

namespace GameCore
{
	public static class ResourceManager
	{
		private static SHA256 sha256 = .();
		private static SHA256 sha256Init = .();

		public static String runtimeResourcesPath ~ delete _;
		public static String buildtimePath ~ delete _;
		public static String buildtimeResourcesPath ~ delete _;
		public static String buildtimeToolsPath ~ delete _;
		public static String buildtimeBgfxToolsPath ~ delete _;
		public static String buildtimeShaderIncludePath ~ delete _;
		public static String buildtimeTemporaryPath ~ delete _;
		private static bool canBuild = true;

		private static FileSystemWatcher buildResourcesWatched = null ~ delete _;
		private static Dictionary<String, Resource> resourceMap = new Dictionary<String, Resource>();
		private static Dictionary<Type, List<Resource>> resourceByTypeMap = new Dictionary<Type, List<Resource>>() ~ DestroyResourcesByType();
		private static List<ResourceBuilder> resourceBuilders = new List<ResourceBuilder>() ~ DestroyResourceBuilders();
		private static HashSet<String> queueResourceFiles = new HashSet<String>() ~ delete _;
		private static bool resourceBuilt = false;

		private static ZipArchive zipArchive = null ~ delete _;

		public static Dictionary<Type, List<Resource>> ResourcesByType => resourceByTypeMap;

		private static Monitor buildResourceLock = null ~ delete _;

		#if BF_PLATFORM_WINDOWS
		const String ToolsPath = "/../bgfx-beef/submodules/bgfx/.build/win64_vs2019/bin/";
		const String ToolsPath2 = "/../bgfx-beef/submodules/bgfx/.build/win64_vs2017/bin/";
		public static ResourceBuilderPlatform ActiveResourceBuilderPlatform = .Windows;
			#elif BF_PLATFORM_MACOS
		const String ToolsPath = "/../bgfx-beef/submodules/bgfx/.build/osx-x64/bin/";
		const String ToolsPath2 = "/../bgfx-beef/submodules/bgfx/.build/osx-x64/bin/";
		public static ResourceBuilderPlatform ActiveResourceBuilderPlatform = .macOS;
			#elif BF_PLATFORM_LINUX
		const String ToolsPath = "/../bgfx-beef/submodules/bgfx/.build/linux64_gcc/bin/";
		const String ToolsPath2 = "/../bgfx-beef/submodules/bgfx/.build/osx64_clang/bin/";
		public static ResourceBuilderPlatform ActiveResourceBuilderPlatform = .Linux;
		#else
		public static ResourceBuilderPlatform ActiveResourceBuilderPlatform = .Last;
		#endif

		public static bool AddResource(Type type, StringView _name, StringView _hash)
		{
			switch (type.CreateObject()) {
			case .Ok(let val):
				var resource = val as Resource;
				var hash = new String(_hash);
				resource.Initialize(new String(_name), hash);
				resourceMap.Add(hash, resource);
				List<Resource> resources;
				if (!resourceByTypeMap.TryGetValue(type, out resources))
				{
					resources = new List<Resource>();
					resourceByTypeMap.Add(type, resources);
				}
				resources.Add(resource);
				return true;
			default:
			}
			return false;
		}

		private static void DestroyResourcesByType()
		{
			for (var pair in resourceByTypeMap)
			{
				delete pair.value;
			}
			delete resourceByTypeMap;
		}

		private static void DestroyResources()
		{
			for (var pair in resourceMap)
			{
				pair.value.Unload();
				delete pair.value;
			}
			delete resourceMap;
		}

		private static void DestroyResourceBuilders()
		{
			for (var builder in resourceBuilders)
			{
				delete builder;
			}
			delete resourceBuilders;
		}

		public static void Finalize()
		{
			DestroyResources();
		}

		private static void OnFileChange(StringView _fileName)
		{
			buildResourceLock.Enter();
			var fileName = scope String(buildtimeResourcesPath);
			fileName.Append(_fileName);
			var newFileName = new String(fileName);
			if (!queueResourceFiles.Contains(newFileName))
			{
				queueResourceFiles.Add(newFileName);
			} else
			{
				delete newFileName;
			}
			buildResourceLock.Exit();
		}

		private static void AddResourceBuild(ResourceBuilder builder)
		{
			resourceBuilders.Add(builder);
		}

		private static void GetPathHash(StringView path, String hashString)
		{
			sha256 = sha256Init;
			sha256.Update(Span<uint8>((uint8*)path.Ptr, path.Length));
			var hash = sha256.Finish();
			SystemUtils.SHA256ToString(hash, hashString);
		}

		private static void GetRelativePathHash(String relativePath, String hashString)
		{
			var path = scope String();
			Path.GetDirectoryPath(relativePath, path);
			var fileName = scope String();
			Path.GetFileNameWithoutExtension(relativePath, fileName);
			path.AppendF("/{}", fileName);
			GetPathHash(path, hashString);
			relativePath.Set(path);
		}

		private static void BuildResourceList()
		{
			if (!resourceBuilt)
			{
				return;
			}
			resourceBuilt = false;
			var resourceList = scope ResourceList();
			resourceList.Save(scope $"{ResourceManager.runtimeResourcesPath}/resources.json");
		}

		private static bool BuildResource(StringView filename, bool force = false, bool update = true)
		{
			var wasBuilt = false;
			var relativePath = scope String(filename);
			relativePath.Remove(0, buildtimeResourcesPath.Length);
			relativePath.ToLower();
			SystemUtils.NormalizePath(relativePath);
			for (var builder in resourceBuilders)
			{
				var found = false;
				for (var ext in builder.Extensions)
				{
					if (relativePath.EndsWith(ext))
					{
						found = true;
						break;
					}
				}
				if (!found)
				{
					continue;
				}
				var hashString = scope String();
				GetRelativePathHash(relativePath, hashString);
				Resource resource = null;
				var wasLoaded = false;
				if (resourceMap.TryGetValue(hashString, out resource))
				{
					if (update)
					{
						wasLoaded = resource.IsLoaded;
						resource.Unload();
					}
				} else
				{
					if (AddResource(builder.ResourceType, relativePath, hashString))
					{
						Log.Info("Resource {} added!", relativePath);
					} else
					{
						Log.Info("Resource {} failed!", relativePath);
						continue;
					}
				}
				if (!force && !builder.CheckBuild(filename, hashString))
				{
					continue;
				}
				Log.Info("Building {}...", filename);
				builder.Build(filename, hashString);
				wasBuilt = true;
				resourceBuilt = true;
				if (wasLoaded)
				{
					resource.Load();
				}
			}
			return wasBuilt;
		}

		public static void BuildResourcesForPlatform(ResourceBuilderPlatform platform, StringView destinationPath, bool force = false)
		{
			// Set destination path
			var updateResouce = true;
			var runtimeResourcesPathCopy = scope String();
			var activeResourceBuilderPlatformCopy = ActiveResourceBuilderPlatform;
			if (platform != .Last)
			{
				updateResouce = false;
				runtimeResourcesPathCopy.Set(runtimeResourcesPath);
				runtimeResourcesPath.Set(destinationPath);
				ActiveResourceBuilderPlatform = platform;
				if (!Directory.Exists(destinationPath))
				{
					Directory.CreateDirectory(destinationPath);
				}
			}
			// Update buildtime folder
			var files = scope List<String>();
			SystemUtils.FindFiles(buildtimeResourcesPath, "*.*", ref files);
			// Update resource
			for (var fileName in files)
			{
				BuildResource(fileName, force, updateResouce);
				delete fileName;
			}
			BuildResourceList();
			// Revert destination path
			if (platform != .Last)
			{
				runtimeResourcesPath.Set(runtimeResourcesPathCopy);
				ActiveResourceBuilderPlatform = activeResourceBuilderPlatformCopy;
			}
		}

		private static void InitializeRuntimeBuild(String path)
		{
#if RESOURCEBUILD
			canBuild = System.IO.Directory.Exists(buildtimeResourcesPath);
			// Find tools (either VS2019 or VS2017)
			if (canBuild)
			{
				buildtimeBgfxToolsPath.Append(ToolsPath);
				if (!System.IO.Directory.Exists(buildtimeBgfxToolsPath))
				{
					canBuild = false;
				}
				if (!canBuild)
				{
					buildtimeBgfxToolsPath.Clear();
					buildtimeBgfxToolsPath.Append(ToolsPath2);
					if (!System.IO.Directory.Exists(buildtimeBgfxToolsPath))
					{
						canBuild = false;
					}
				}
				if (canBuild)
				{
					String.NewOrSet!(buildtimeShaderIncludePath, path);
					buildtimeShaderIncludePath.Append("/../bgfx-beef/submodules/bgfx/src/");
					if (!System.IO.Directory.Exists(buildtimeShaderIncludePath))
					{
						canBuild = false;
					}
				}
			}
			if (canBuild)
			{
				Log.Info("NOTE: Running in build mode!");
				Log.Info("NOTE: You can change existing assets (textures, shaders, etc) and they will get rebuilt and reloaded!");
				Directory.CreateDirectory(runtimeResourcesPath);
				// Create resource builders
				for (let type in Type.Types)
				{
					if (!type.IsSubtypeOf(typeof(ResourceBuilder)))
					{
						continue;
					}
					switch (type.CreateObject()) {
					case .Ok(let val):
						AddResourceBuild(val as ResourceBuilder);
						break;
					case .Err(let err):
						continue;
					}
				}
				BuildResourcesForPlatform(.Last, "");
				buildResourceLock = new Monitor();
		#if BF_PLATFORM_WINDOWS				
				// Watch buildtime folder
				buildResourcesWatched = new FileSystemWatcher(buildtimeResourcesPath);
				buildResourcesWatched.IncludeSubdirectories = true;
				buildResourcesWatched.StartRaisingEvents();
				buildResourcesWatched.OnCreated.Add(new (fileName) => OnFileChange(fileName));
				buildResourcesWatched.OnChanged.Add(new (fileName) => OnFileChange(fileName));
		#endif
			}
#endif
		}

		public static void Initialize(String path, String resourcesFileName, int resourcesFilePosition, int resourcesFileSize, bool isEditor)
		{
			if (!isEditor)
			{
				// Try open zip
				zipArchive = new ZipArchive();
				if (resourcesFilePosition != 0)
				{
					if (!zipArchive.Open(resourcesFileName, (uint64)resourcesFilePosition, (uint64)resourcesFileSize))
					{
						Log.Error(scope $"Resource '{resourcesFileName}'/{resourcesFilePosition}/{resourcesFileSize} open failed!");
						DeleteAndNullify!(zipArchive);
					}
				} else
				{
					if (!zipArchive.Open(resourcesFileName))
					{
						Log.Error(scope $"Resource '{resourcesFileName}' open failed!");
						DeleteAndNullify!(zipArchive);
					}
				}
				var resourceList = scope ResourceList();
				if (!resourceList.Load("resources.json"))
				{
					SystemUtils.ShowMessageBoxOK("ERROR", "Runtime missing!");
					System.Environment.Exit(1);
				}
				return;
			}
			String.NewOrSet!(runtimeResourcesPath, path);
			runtimeResourcesPath.Append("/runtime/resources/");
			String.NewOrSet!(buildtimeResourcesPath, path);
			buildtimeResourcesPath.Append("/buildtime/resources/");
			String.NewOrSet!(buildtimePath, path);
			buildtimePath.Append("/buildtime/");
			String.NewOrSet!(buildtimeToolsPath, path);
			buildtimeToolsPath.Append("/buildtime/tools/");
			String.NewOrSet!(buildtimeTemporaryPath, path);
			buildtimeTemporaryPath.Append("/buildtemp/");
			System.IO.Directory.CreateDirectory(buildtimeTemporaryPath);
#if BF_PLATFORM_WINDOWS
			buildtimeToolsPath.Append("windows/");
#else
			buildtimeToolsPath.Append("macos/");
#endif
			String.NewOrSet!(buildtimeBgfxToolsPath, path);
			InitializeRuntimeBuild(path);
			if (!System.IO.Directory.Exists(runtimeResourcesPath))
			{
				SystemUtils.ShowMessageBoxOK("ERROR", "Runtime folder missing!");
				System.Environment.Exit(1);
			}
		}

		public static void Update(bool isPaused)
		{
			if (isPaused)
			{
				return;
			}
			if (queueResourceFiles.Count == 0)
			{
				return;
			}
			if (buildResourceLock.TryEnter())
			{
				for (var fileName in queueResourceFiles)
				{
					defer delete fileName;
					if (!File.Exists(fileName))
					{
						continue;
					}
					BuildResource(fileName, true);
				}
				BuildResourceList();
				queueResourceFiles.Clear();
				buildResourceLock.Exit();
			}
		}

		public static T GetResource<T>(StringView path, bool load = true) where T : Resource
		{
			var hashString = scope String();
			GetPathHash(path, hashString);
			if (resourceMap.TryGetValue(hashString, var resource))
			{
				if (!(resource is T))
				{
					return null;
				}
				resource.Load();
				return resource as T;
			}
			return null;
		}

		public static List<Resource> FindResourcesByType<T>() where T : Resource
		{
			List<Resource> resources;
			resourceByTypeMap.TryGetValue(typeof(T), out resources);
			return resources;
		}

		private static uint WriteFunction(void* userData, uint64 offset, void* buffer, uint count)
		{
			var stream = Internal.UnsafeCastToObject(userData) as DynMemStream;
			stream.TryWrite(Span<uint8>((uint8*)buffer, (int)count));
			return count;
		}

		public static bool ReadFile(StringView fileName, DynMemStream stream)
		{
			var result = false;
			if (zipArchive != null)
			{
				var index = zipArchive.FindFile(scope $"{fileName}\0");
				if (index != -1)
				{
					stream.Position = 0;
					result = zipArchive.ReadFile(index, => WriteFunction, Internal.UnsafeCastToPtr(stream));
					stream.Position = 0;
				}
			} else
			{
				uint8[] binaryData;
				result = SystemUtils.ReadBinaryFile(scope $"{ResourceManager.runtimeResourcesPath}/{fileName}", out binaryData);
				if (result)
				{
					stream.Position = 0;
					stream.TryWrite(binaryData);
					stream.Position = 0;
					delete binaryData;
				}
			}
			if (!result)
			{
				Log.Error(scope $"Loading '{fileName}' failed!");
			}
			return result;
		}


	}
}
