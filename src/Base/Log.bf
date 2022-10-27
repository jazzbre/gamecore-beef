using System;
using SDL2;

namespace GameCore
{
	public enum LogType
	{
		Debug,
		Info,
		Warning,
		Error,
		Last,
	}

	public static class Log
	{
		private const SDL.LogPriority[(int)LogType.Last] logPriorities = .(SDL.LogPriority.SDL_LOG_PRIORITY_DEBUG, SDL.LogPriority.SDL_LOG_PRIORITY_INFO, SDL.LogPriority.SDL_LOG_PRIORITY_WARN, SDL.LogPriority.SDL_LOG_PRIORITY_ERROR);
		private static void Log(LogType logType, StringView fmt, params Object[] args)
		{
			var log = scope String();
			var type = scope String();
			logType.ToString(type);
#if BF_PLATFORM_WINDOWS			
			var now = DateTime.Now;
			log.AppendF("{}-{}-{} {}:{}:{}.{} - {} - ", now.Year, now.Month, now.Day, now.Hour, now.Minute, now.Second, now.Millisecond, Time.FrameCounter);
#endif
			log.AppendF(fmt, params args);
			SDL.LogMessage(SDL.LOG_CATEGORY_APPLICATION, logPriorities[(int)logType], log.CStr(), null);
		}

		public static void Debug(StringView fmt, params Object[] args)
		{
			Log(LogType.Debug, fmt, params args);
		}

		public static void Info(StringView fmt, params Object[] args)
		{
			Log(LogType.Info, fmt, params args);
		}

		public static void Warning(StringView fmt, params Object[] args)
		{
			Log(LogType.Warning, fmt, params args);
		}

		public static void Error(StringView fmt, params Object[] args)
		{
			Log(LogType.Error, fmt, params args);
		}

	}
}
