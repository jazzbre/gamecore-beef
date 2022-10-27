using System;
using System.IO;
using System.Diagnostics;
using System.Collections;
using SDL2;

namespace Dedkeni
{
	public static class SystemUtils
	{
		public static int32 ShowMessageBoxOK(String title, String message)
		{
			var messageBoxData = SDL.MessageBoxData();
			SDL.MessageBoxButtonData[1] buttons;
			buttons[0].buttonid = 0;
			buttons[0].text = "OK";
			messageBoxData.buttons = &buttons[0];
			messageBoxData.window = null;
			messageBoxData.numbuttons = 1;
			messageBoxData.message = message;
			messageBoxData.title = title;
			int32 buttonId = 0;
			SDL.ShowMessageBox(ref messageBoxData, out buttonId);
			return buttonId;
		}

		public static int32 ShowMessageBoxOKCancel(StringView title, StringView message)
		{
			var messageBoxData = SDL.MessageBoxData();
			SDL.MessageBoxButtonData[2] buttons;
			buttons[0].buttonid = 0;
			buttons[0].text = "OK";
			buttons[1].buttonid = 1;
			buttons[1].text = "Cancel";
			messageBoxData.buttons = &buttons[0];
			messageBoxData.window = null;
			messageBoxData.numbuttons = 1;
			messageBoxData.message = message.Ptr;
			messageBoxData.title = title.Ptr;
			int32 buttonId = 0;
			SDL.ShowMessageBox(ref messageBoxData, out buttonId);
			return buttonId;
		}

		public static int ExecuteProcess(StringView executable, StringView commandLine, String output = null, String errorOutput = null)
		{
			Log.Info("Executing: {0} {1}", executable, commandLine);
			var process = scope SpawnedProcess();
			var processStartInfo = scope ProcessStartInfo();
			processStartInfo.UseShellExecute = false;
			processStartInfo.SetFileName(executable);
			processStartInfo.SetArguments(commandLine);
#if BF_PLATFORM_WINDOWS
			var outputStream = scope FileStream();
			if (output != null)
			{
				processStartInfo.RedirectStandardError = true;
			}
			var errorOutputStream = scope FileStream();
			if (errorOutput != null)
			{
				processStartInfo.RedirectStandardOutput = true;
			}
#endif
			switch (process.Start(processStartInfo)) {
			case .Ok:
#if BF_PLATFORM_WINDOWS
				if (output != null)
				{
					process.AttachStandardOutput(outputStream);
				}
				if (errorOutput != null)
				{
					process.AttachStandardError(errorOutputStream);
				}
#endif
				break;
			case .Err:
				return -1;
			}
			process.WaitFor();
#if BF_PLATFORM_WINDOWS			
			if (output != null)
			{
				if (outputStream.Length > 0)
				{
					var outputData = scope char8[outputStream.Length];
					outputStream.Position = 0;
					outputStream.TryRead(Span<uint8>((uint8*)&outputData[0], outputData.Count));
					output.Set(StringView(outputData, 0, outputData.Count));
				} else
				{
					output.Clear();
				}
			}
			if (errorOutput != null)
			{
				if (errorOutputStream.Length > 0)
				{
					var outputData = scope char8[errorOutputStream.Length];
					errorOutputStream.Position = 0;
					errorOutputStream.TryRead(Span<uint8>((uint8*)&outputData[0], outputData.Count));
					errorOutput.Set(StringView(outputData, 0, outputData.Count));
				} else
				{
					errorOutput.Clear();
				}
			}
#endif
			return process.ExitCode;
		}

		public static bool ReadBinaryFile(StringView filename, out uint8[] data)
		{
			data = null;
			var file = scope FileStream();
			switch (file.Open(filename, .Read)) {
			case .Ok:
				break;
			case .Err:
				return false;
			}
			data = new uint8[(.)file.Length];
			file.TryRead(Span<uint8>(data));
			file.Close();
			return true;
		}

		public static bool WriteBinaryFile(StringView filename, uint8* data, int size)
		{
			var file = scope FileStream();
			switch (file.Create(filename, .Write)) {
			case .Ok:
				break;
			case .Err:
				return false;
			}
			file.TryWrite(Span<uint8>(data, size));
			file.Close();
			return true;
		}

		public static bool ReadStrSized32(Stream stream, String outString)
		{
			var size = (int)stream.Read<int32>().Value;
			outString.Clear();
			if (size == 0)
			{
				return true;
			}
			var data = scope char8[size];
			switch (stream.TryRead(Span<uint8>((uint8*)&data[0], size))) {
			case .Ok(let val):
				outString.Append(data, 0, size);
				return true;
			default:
				return false;
			}
		}

		public static bool ReadStrSized16(Stream stream, String outString)
		{
			var size = (int)stream.Read<int16>().Value;
			outString.Clear();
			if (size == 0)
			{
				return true;
			}
			var data = scope char8[size];
			switch (stream.TryRead(Span<uint8>((uint8*)&data[0], size))) {
			case .Ok(let val):
				outString.Append(data, 0, size);
				return true;
			default:
				return false;
			}
		}

		public static DateTime GetLatestTimestamp(params StringView[] args)
		{
			var bestDateTime = DateTime();
			var failed = false;
			for (var arg in args)
			{
				if (File.Exists(arg))
				{
					switch (File.GetLastWriteTimeUtc(arg)) {
					case .Ok(let dt):
						if (dt > bestDateTime)
						{
							bestDateTime = dt;
						}
						break;
					default:
					}
				} else
				{
					failed = true;
				}
			}
			return failed ? DateTime() : bestDateTime;
		}

		public static void NormalizePath(String path)
		{
			path.Replace("\\", "/");
			path.Replace("//", "/");
		}


		public static void NormalizeSystemPath(String path)
		{
#if BF_PLATFORM_WINDOWS
			path.Replace("/", "\\");
#else
			path.Replace("\\", "/");
#endif
		}

		public static void FindFiles(StringView path, StringView what, ref List<String> foundFiles)
		{
			var searchPath = scope String();
			var fileName = scope String();
			searchPath.AppendF("{}/{}", path, what);
			var files = Directory.Enumerate(searchPath, .Directories | .Files);
			for (var file in files)
			{
				fileName.Clear();
				file.GetFilePath(fileName);
				// if (file.IsDirectory) doesn't work on macOS so the hack bellow is used
				if (!fileName.Contains("."))
				{
					FindFiles(fileName, what, ref foundFiles);
				} else
				{
					var foundFileName = new String(fileName);
					SystemUtils.NormalizePath(foundFileName);
					foundFiles.Add(foundFileName);
				}
			}
		}

		public static void SHA256ToString(SHA256Hash hash, String s)
		{
			for (var h in hash.mHash)
			{
				s.AppendF("{0:X}", h);
			}
		}

		public static bool FileCopy(StringView fromFileName, StringView toFileName, bool overwrite = true)
		{
			switch (File.Copy(fromFileName, toFileName, overwrite)) {
			case .Ok(let val):
				return true;
			default:
				return false;
			}
		}
	}
}
