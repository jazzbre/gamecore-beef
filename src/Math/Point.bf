using System;
using System.Collections;
using System.Text;

namespace GameCore
{
	[CRepr, AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	public struct Point
	{
		[JSON_Beef.Serialized]
		public float x;
		[JSON_Beef.Serialized]
		public float y;

		public this(float _x, float _y)
		{
			x = _x;
			y = _y;
		}
	}

	[CRepr, AlwaysInclude(AssumeInstantiated = true, IncludeAllMethods = true), Reflect]
	public struct PointInt32
	{
		[JSON_Beef.Serialized]
		public int32 x;
		[JSON_Beef.Serialized]
		public int32 y;

		public this(int32 _x, int32 _y)
		{
			x = _x;
			y = _y;
		}
	}
}
