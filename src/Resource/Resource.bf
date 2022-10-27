using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
using Bgfx;

namespace GameCore
{
	public abstract class Resource
	{
		public String Name
		{
			get; private set;
		}

		public String Hash
		{
			get; private set;
		}

		public bool IsLoaded
		{
			get; private set;
		}

		public ~this()
		{
			delete Name;
			delete Hash;
		}

		public virtual void Initialize(String name, String hash)
		{
			Name = name;
			Hash = hash;
		}

		public void Load()
		{
			if (IsLoaded)
			{
				return;
			}
			OnLoad();
			IsLoaded = true;
		}

		public void Unload()
		{
			if (!IsLoaded)
			{
				return;
			}
			OnUnload();
			IsLoaded = false;
		}

		protected abstract void OnLoad();
		protected abstract void OnUnload();

	}
}
