using System;
using System.Collections;
using SoLoud;

namespace Dedkeni
{
	enum AudioBus
	{
		Default,
	}

	static class AudioManager
	{
		protected static Soloud soloud = new Soloud() ~ delete _;

		public static var masterVolume = 1.0f;
		public static var musicMasterVolume = 1.0f;
		public static var musicFadeVolume = 1.0f;

		static int activeMusicIndex = 0;
		static float activeMusicFactor = 0.0f;
		static uint32[] activeMusicHandles = new .[2] ~ delete _;


		public static delegate float(Vector2 position) OnGetDistanceCallback = null ~ delete _;

		public static Soloud SoLoud => soloud;

		public static bool Initialize()
		{
			var result = soloud.init(Soloud.CLIP_ROUNDOFF);
			if (result != 0)
			{
				Log.Error("Failed to initialize SoLoud!");
				return false;
			}

			return true;
		}

		public static void Finalize()
		{
			// Finalize SoLoud
			soloud.deinit();
		}

		public static void OnUpdate(float deltaTime)
		{
			activeMusicFactor = Math.MoveTowards(activeMusicFactor, (float)activeMusicIndex, deltaTime * 0.5f);
			for (var i = 0; i < 2; ++i)
			{
				if (activeMusicHandles[i] == 0)
				{
					continue;
				}
				var volume = i == 0 ? 1.0f - activeMusicFactor : activeMusicFactor;
				SoLoud.setVolume(activeMusicHandles[i], volume * masterVolume * musicMasterVolume * musicFadeVolume);
				if (volume <= 0.0001f && i != activeMusicIndex)
				{
					SoLoud.stop(activeMusicHandles[i]);
					activeMusicHandles[i] = 0;
				}
			}
		}

		public static uint32 Play(StringView name, float volume = 1.0f, float pan = 0.0f, AudioBus bus = .Default)
		{
			let audioClip = ResourceManager.GetResource<AudioClip>(name);
			return Play(audioClip, volume, pan, bus);
		}

		public static uint32 Play(AudioClip audioClip, float volume = 1.0f, float pan = 0.0f, AudioBus bus = .Default)
		{
			if (audioClip == null)
			{
				return 0;
			}
			var handle = SoLoud.play(audioClip.Clip, volume * masterVolume, pan);
			return handle;
		}

		public static uint32 PlayAtPosition(StringView name, Vector2 position, float volume = 1.0f, float range = 300.0f, AudioBus bus = .Default)
		{
			let audioClip = ResourceManager.GetResource<AudioClip>(name);
			return PlayAtPosition(audioClip, position, volume, range, bus);
		}

		public static uint32 PlayAtPosition(AudioClip audioClip, Vector2 position, float volume = 1.0f, float range = 300.0f, AudioBus bus = .Default)
		{
			if (audioClip == null)
			{
				return 0;
			}

			var distance = OnGetDistanceCallback != null ? OnGetDistanceCallback(position) : 0.0f;
			if (distance > range)
			{
				return 0;
			}
			return Play(audioClip, (1.0f - distance / range) * volume, 0.0f, bus);
		}

		public static bool PlayMusicByName(StringView name)
		{
			let audioClip = ResourceManager.GetResource<AudioClip>(name);
			PlayMusic(audioClip);
			return true;
		}

		public static void PlayMusic(AudioClip audioClip)
		{
			activeMusicIndex = activeMusicIndex == 0 ? 1 : 0;
			if (activeMusicHandles[activeMusicIndex] != 0)
			{
				SoLoud.stop(activeMusicHandles[activeMusicIndex]);
				activeMusicHandles[activeMusicIndex] = 0;
			}
			if (audioClip != null)
			{
				activeMusicHandles[activeMusicIndex] = SoLoud.play(audioClip.Clip, 0.0f);
				SoLoud.setLooping(activeMusicHandles[activeMusicIndex], 1);
				SoLoud.setInaudibleBehavior(activeMusicHandles[activeMusicIndex], 1, 0);
			}
		}

		public static void OnLevelPlay()
		{
			PlayMusic(null);
		}

		public static void OnLevelStop()
		{
			PlayMusic(null);
			SoLoud.stopAll();
		}
	}
}