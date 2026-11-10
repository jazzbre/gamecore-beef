using System;
using System.IO;
using System.Diagnostics;
using System.Collections;
using System.Threading;
using SDL2;

namespace GameCore
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
			processStartInfo.CreateNoWindow = true;
			processStartInfo.RedirectStandardOutput = true;
			processStartInfo.RedirectStandardError = true;
			var outputStream = scope FileStream();
			var errorOutputStream = scope FileStream();
#endif
			switch (process.Start(processStartInfo)) {
			case .Ok:
#if BF_PLATFORM_WINDOWS
				process.AttachStandardOutput(outputStream);
				process.AttachStandardError(errorOutputStream);
#endif
				break;
			case .Err:
				return -1;
			}

#if BF_PLATFORM_WINDOWS
			var capturedStandardOutput = scope String();
			var capturedStandardError = scope String();
			var outputReader = scope Thread(new () => ReadProcessOutput(outputStream, capturedStandardOutput));
			var errorReader = scope Thread(new () => ReadProcessOutput(errorOutputStream, capturedStandardError));
			// Both pipes must drain before waiting, otherwise a verbose tool can block on a full pipe.
			outputReader.Start(false);
			errorReader.Start(false);
#endif
			process.WaitFor();
#if BF_PLATFORM_WINDOWS
			outputReader.Join();
			errorReader.Join();
			if (output != null)
			{
				output.Set(capturedStandardOutput);
			}
			else if (!capturedStandardOutput.IsEmpty)
			{
				Log.Info("{}", capturedStandardOutput);
			}
			if (errorOutput != null)
			{
				errorOutput.Set(capturedStandardError);
			}
			else if (!capturedStandardError.IsEmpty)
			{
				if (process.ExitCode == 0)
				{
					Log.Warning("{}", capturedStandardError);
				}
				else
				{
					Log.Error("{}", capturedStandardError);
				}
			}
#endif
			return process.ExitCode;
		}

#if BF_PLATFORM_WINDOWS
		private static void ReadProcessOutput(FileStream stream, String output)
		{
			var buffer = scope uint8[4096];
			while (true)
			{
				switch (stream.TryRead(Span<uint8>(buffer)))
				{
				case .Ok(let readCount):
					if (readCount == 0)
					{
						return;
					}
					output.Append(StringView((char8*)&buffer[0], readCount));
				case .Err:
					return;
				}
			}
		}
#endif

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
