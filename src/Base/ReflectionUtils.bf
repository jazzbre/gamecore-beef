using System;
using System.Collections;

namespace System
{
	public static class ReflectionUtils
	{
		public class EnumInfo
		{
			public String[] names = null ~ DeleteContainerAndItems!(_);
			public char8*[] namePointers = null ~ DeleteAndNullify!(_);
			public int64[] values = null ~ DeleteAndNullify!(_);
			public bool isFlags = false;
		}

		private static var enums = new Dictionary<Type, EnumInfo>() ~ DeleteDictionaryAndValues!(_);

		public static EnumInfo GetEnumInfo<T>() where T : enum
		{
			return GetEnumInfo(typeof(T));
		}

		public static EnumInfo GetEnumInfo(Type type)
		{
			EnumInfo enumInfo;
			if (enums.TryGetValue(type, out enumInfo))
			{
				return enumInfo;
			}
			enumInfo = new EnumInfo();
			enumInfo.names = new String[type.FieldCount];
			enumInfo.namePointers = new char8*[type.FieldCount];
			enumInfo.values = new int64[type.FieldCount];
			switch (type.GetCustomAttribute<FlagsAttribute>()) {
			case .Ok(var val):
				enumInfo.isFlags = true;
				break;
			default:
			}
			var index = 0;
			for (var field in type.GetFields())
			{
				enumInfo.names[index] = new String(field.Name);
				enumInfo.namePointers[index] = enumInfo.names[index].CStr();
				enumInfo.values[index] = (int64)field.MemberOffset;
				++index;
			}
			enums.Add(type, enumInfo);
			return enumInfo;
		}
	}
}
