using System;
using System.Collections;
using GameCore;

namespace ImGui
{
	enum ImGuiListFlags
	{
		None,
		Add = 1 << 0,
		Remove = 1 << 1,
		Reorder = 1 << 2,
		DefaultMask = Add | Remove | Reorder,
	}

	extension ImGui
	{
		public static bool InputText(StringView name, String text)
		{
			var buffer = scope char8[512];
			Internal.MemCpy(&buffer[0], text.Ptr, text.Length);
			buffer[text.Length] = 0;
			if (ImGui.InputText(name.Ptr, &buffer[0], (uint)buffer.Count))
			{
				text.Clear();
				text.Append(StringView(&buffer[0]));
				return true;
			}
			return false;
		}

		public static bool InputFloat2(StringView name, ref Vector2 v)
		{
			var f = float[2](v.x, v.y);
			if (ImGui.InputFloat2(name.Ptr, f))
			{
				v = .(f[0], f[1]);
				return true;
			}
			return false;
		}

		public static bool InputFloat3(StringView name, ref Vector3 v)
		{
			var f = float[3](v.x, v.y, v.z);
			if (ImGui.InputFloat3(name.Ptr, f))
			{
				v = .(f[0], f[1], f[2]);
				return true;
			}
			return false;
		}

		public static bool InputFloat4(StringView name, ref Vector4 v)
		{
			var f = float[4](v.x, v.y, v.z, v.w);
			if (ImGui.InputFloat4(name.Ptr, f))
			{
				v = .(f[0], f[1], f[2], f[3]);
				return true;
			}
			return false;
		}

		public static bool InputColor(StringView name, ref GameCore.Color v)
		{
			var f = float[4](v.r, v.g, v.b, v.a);
			if (ImGui.ColorEdit4(name.Ptr, f, .HDR))
			{
				v = .(f[0], f[1], f[2], f[3]);
				return true;
			}
			return false;
		}

		public static bool InputEnum(StringView name, ref int64 t, Type type)
		{
			var enumInfo = ReflectionUtils.GetEnumInfo(type);
			if (enumInfo == null || enumInfo.names.Count == 0)
			{
				return false;
			}
			if (enumInfo.isFlags)
			{
				var preview = scope String();
				for (var i = 0; i < enumInfo.values.Count; ++i)
				{
					if ((t & enumInfo.values[i]) != 0)
					{
						if (preview.Length > 0)
						{
							preview.Append("|");
						}
						preview.Append(enumInfo.names[i]);
					}
				}
				if (preview.Length == 0)
				{
					preview.Append("None");
				}
				preview.Append("\0");
				if (ImGui.BeginCombo(name.Ptr, preview.Ptr))
				{
					for (var i = 0; i < enumInfo.values.Count; ++i)
					{
						var isSet = (t & enumInfo.values[i]) != 0;
						if (ImGui.Selectable(enumInfo.names[i].Ptr, isSet))
						{
							if (isSet)
							{
								t &= ~enumInfo.values[i];
							} else
							{
								t |= enumInfo.values[i];
							}
						}
					}
					ImGui.EndCombo();
				}
			} else
			{
				int32 index = 0;
				for (int i = 0; i < enumInfo.values.Count; ++i)
				{
					if (t == enumInfo.values[i])
					{
						index = (.)i;
						break;
					}
				}
				if (ImGui.Combo(name.Ptr, &index, &enumInfo.namePointers[0], (int32)enumInfo.namePointers.Count))
				{
					t = (int64)enumInfo.values[index];
				}
			}
			return true;
		}

		public static bool InputEnum<T>(StringView name, ref T t) where T : enum
		{
			var value = (int64)t;
			if (InputEnum(name, ref value, typeof(T)))
			{
				t = (T)value;
				return true;
			}
			return true;
		}

		public static bool InputProperty(StringView name, ref String v)
		{
			return InputText(name, v);
		}

		public static bool InputProperty(StringView name, ref bool v)
		{
			return Checkbox(name.Ptr, &v);
		}

		public static bool InputProperty(StringView name, ref int v)
		{
			var i = (int32)v;
			if (InputInt(name.Ptr, &i))
			{
				v = (int)i;
				return true;
			}
			return false;
		}

		public static bool InputProperty(StringView name, ref int32 v)
		{
			return InputInt(name.Ptr, &v);
		}

		public static bool InputProperty(StringView name, ref float v)
		{
			return InputFloat(name.Ptr, &v);
		}

		public static bool InputProperty(StringView name, ref double v)
		{
			return InputDouble(name.Ptr, &v);
		}

		public static bool InputProperty(StringView name, ref Vector2 v)
		{
			return InputFloat2(name, ref v);
		}

		public static bool InputProperty(StringView name, ref Vector3 v)
		{
			return InputFloat3(name, ref v);
		}

		public static bool InputProperty(StringView name, ref Vector4 v)
		{
			return InputFloat4(name, ref v);
		}

		public static bool InputProperty(StringView name, ref GameCore.Color v)
		{
			return InputColor(name, ref v);
		}

		public static bool InputProperty<T>(StringView name, ref T t) where T : enum
		{
			return InputEnum(name, ref t);
		}

		public static bool InputProperty(StringView name, System.Reflection.FieldInfo field, Type type, void* data)
		{
			if (type.IsValueType)
			{
				if (type.IsEnum)
				{
					switch (type.Size)
					{
					case 1:
						var v = ((int8*)data);
						var value = (int64) * v;
						if (InputEnum(name, ref value, type))
						{
							*v = (int8)value;
							return true;
						}
						break;
					case 2:
						var v = ((int16*)data);
						var value = (int64) * v;
						if (InputEnum(name, ref value, type))
						{
							*v = (int16)value;
							return true;
						}
						break;
					case 4:
						var v = ((int32*)data);
						var value = (int64) * v;
						if (InputEnum(name, ref value, type))
						{
							*v = (int32)value;
							return true;
						}
						break;
					case 8:
						var v = ((int64*)data);
						if (InputEnum(name, ref *v, type))
						{
							return true;
						}
						break;
					}
				}
				switch (type)
				{
				case typeof(bool):
					var v = ((bool*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(int32):
					var v = ((int32*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(int):
					var v = ((int*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(float):
					var v = ((float*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(Vector2):
					var v = ((Vector2*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(Vector3):
					var v = ((Vector3*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(Vector4):
					var v = ((Vector4*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(GameCore.Color):
					var v = ((GameCore.Color*)data);
					if (InputProperty(name, ref *v))
					{
						return true;
					}
					break;
				case typeof(String):
					var v = Internal.UnsafeCastToObject(data);
					if (InputProperty(name, v))
					{
						return true;
					}
					break;
				}
			}
			return false;
		}

		public static bool InputProperty<T>(StringView name, ref T t) where T : struct
		{
			bool changed = false;
			var type = t.GetType();
			var pointer = (uint8*)&t;
			for (var field in type.GetFields())
			{
				if (InputProperty(field.Name, field, field.FieldType, pointer + field.MemberOffset))
				{
					changed = true;
				}
			}
			return changed;
		}

		public static bool InputProperty<T>(StringView name, T t) where T : Object
		{
			bool changed = false;
			var type = t.GetType();
			var pointer = (uint8*)Internal.UnsafeCastToPtr(t);
			for (var field in type.GetFields())
			{
				if (InputProperty(field.Name, field, field.FieldType, pointer + field.MemberOffset))
				{
					changed = true;
				}
			}
			return changed;
		}

		typealias InputPropertyDelegate<T> = delegate void(ref T);
		typealias InputPropertyCheckDelegate<T> = delegate bool(ref T);

		public static bool InputList<T>(StringView name, List<T> list, InputPropertyDelegate<T> inputProperty, ImGuiListFlags flags = .DefaultMask, bool sameLine = false, InputPropertyCheckDelegate<T> inputCheckProperty = null) where T : ValueType
		{
			var deleted = false;
			ImGui.PushID(Internal.UnsafeCastToPtr(list));
			ImGui.Text(scope $"{name}:");
			ImGui.Indent();
			for (int i = 0; i < list.Count; ++i)
			{
				if (inputCheckProperty != null && !inputCheckProperty(ref list[i]))
				{
					continue;
				}
				ImGui.PushID((void*)i);
				ImGui.TextDisabled(scope $"{i:D4}");
				if ((flags & .Add) != 0)
				{
					ImGui.SameLine();
					if (ImGui.Button("+"))
					{
						list.Insert(i, default(T));
					}
				}
				if ((flags & .Remove) != 0)
				{
					ImGui.SameLine();
					if (ImGui.Button("-"))
					{
						list.RemoveAt(i--);
						ImGui.PopID();
						deleted = true;
						continue;
					}
				}
				if ((flags & .Reorder) != 0)
				{
					ImGui.SameLine();
					if (i > 0)
					{
						if (ImGui.Button("U"))
						{
							Swap!(list[i], list[i - 1]);
						}
					} else
					{
						ImGui.Button(" ###U");
					}
					ImGui.SameLine();
					if (i < list.Count - 1)
					{
						if (ImGui.Button("D"))
						{
							Swap!(list[i], list[i + 1]);
						}
					} else
					{
						ImGui.Button(" ###D");
					}
				}
				if (sameLine)
				{
					ImGui.SameLine();
				}
				inputProperty(ref list[i]);
				ImGui.PopID();
			}
			if ((flags & .Add) != 0 && ImGui.Button("+"))
			{
				list.Add(default(T));
			}
			ImGui.Unindent();
			ImGui.PopID();
			return deleted;
		}

		public static bool InputList<T>(StringView name, List<T> list, InputPropertyDelegate<T> inputProperty, ImGuiListFlags flags = .DefaultMask, bool sameLine = false, InputPropertyCheckDelegate<T> inputCheckProperty = null) where T : Object, new, delete
		{
			var deleted = false;
			ImGui.PushID(Internal.UnsafeCastToPtr(list));
			ImGui.Text(scope $"{name}:");
			ImGui.Indent();
			for (int i = 0; i < list.Count; ++i)
			{
				if (inputCheckProperty != null && !inputCheckProperty(ref list[i]))
				{
					continue;
				}
				ImGui.PushID((void*)i);
				ImGui.TextDisabled(scope $"{i:D4}");
				if ((flags & .Add) != 0)
				{
					ImGui.SameLine();
					if (ImGui.Button("+"))
					{
						switch (typeof(T).CreateObject())
						{
						case .Ok(let val):
							list.Insert(i, val as T);
						default:
						}
					}
				}
				if ((flags & .Remove) != 0)
				{
					ImGui.SameLine();
					if (ImGui.Button("-"))
					{
						delete list[i];
						list.RemoveAt(i--);
						ImGui.PopID();
						deleted = true;
						continue;
					}
				}
				if ((flags & .Reorder) != 0)
				{
					ImGui.SameLine();
					if (i > 0)
					{
						if (ImGui.Button("U"))
						{
							Swap!(list[i], list[i - 1]);
						}
					}
					else
					{
						ImGui.Button(" ###U");
					}
					ImGui.SameLine();
					if (i < list.Count - 1)
					{
						if (ImGui.Button("D"))
						{
							Swap!(list[i], list[i + 1]);
						}
					}
					else
					{
						ImGui.Button(" ###D");
					}
				}
				if (sameLine)
				{
					ImGui.SameLine();
				}
				inputProperty(ref list[i]);
				ImGui.PopID();
			}
			if ((flags & .Add) != 0 && ImGui.Button("+"))
			{
				switch (typeof(T).CreateObject())
				{
				case .Ok(let val):
					list.Add(val as T);
				default:
				}
			}
			ImGui.Unindent();
			ImGui.PopID();
			return deleted;
		}

		public static void InputList<T>(StringView name, List<T> list, ImGuiListFlags flags = .DefaultMask) where T : var
		{
			InputList(name, list, scope [&] (t) => InputProperty("", ref t), flags);
		}

		public static void InputList<T>(StringView name, List<T> list, ImGuiListFlags flags = .DefaultMask) where T : ValueType
		{
			InputList(name, list, scope [&] (t) => InputProperty("", ref t), flags);
		}

		public static void InputList<T>(StringView name, List<T> list, ImGuiListFlags flags = .DefaultMask) where T : Object, new, delete
		{
			InputList(name, list, scope [&] (t) => InputProperty("", t), flags);
		}

		public static bool InputSprite(StringView name, ref Sprite sprite)
		{
			var lastSprite = sprite;
			if (ImGui.Selectable(sprite != null ? sprite.name : "NONE", false))
			{
				sprite = null;
			}
			if (ImGui.BeginDragDropTarget())
			{
				var payload = ImGui.AcceptDragDropPayload("Sprite");
				if (payload != null)
				{
					var spritePointer = *((void**)ImGui.GetPayloadData(payload));
					Log.Info(scope $"Sprite Drop {spritePointer}");
					sprite = (Sprite)Internal.UnsafeCastToObject(spritePointer);
				}
				ImGui.EndDragDropTarget();
			}
			return lastSprite != sprite;
		}

		public static bool Foldout(StringView name, ref bool isOpened)
		{
			bool changed = false;
			if (ArrowButton(name.Ptr, isOpened ? .Left : .Right))
			{
				isOpened = !isOpened;
				changed = true;
			}
			SameLine();
			Selectable(name.Ptr);
			return changed;
		}
	}
}
