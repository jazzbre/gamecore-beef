using System;
using System.Collections;
using SoLoud;

namespace GameCore
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
		public static var effectsMasterVolume = 1.0f;
		private static Bus effectsBus = new .() ~ delete _;
		private static uint32 effectsBusHandle;
		private static bool initialized;

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

			initialized = true;
			EnsureEffectsBus();
			SetVolumes(masterVolume, musicMasterVolume, effectsMasterVolume);
			return true;
		}

		public static void Finalize()
		{
			initialized = false;
			effectsBusHandle = 0;
			// Finalize SoLoud
			soloud.deinit();
		}

		public static void OnUpdate(float deltaTime)
		{
			if (!initialized)
			{
				return;
			}
			SoLoud.setGlobalVolume(masterVolume);
			activeMusicFactor = Math.MoveTowards(activeMusicFactor, (float)activeMusicIndex, deltaTime * 0.5f);
			for (var i = 0; i < 2; ++i)
			{
				if (activeMusicHandles[i] == 0)
				{
					continue;
				}
				var volume = i == 0 ? 1.0f - activeMusicFactor : activeMusicFactor;
				SoLoud.setVolume(activeMusicHandles[i], volume * musicMasterVolume * musicFadeVolume);
				if (volume <= 0.0001f && i != activeMusicIndex)
				{
					SoLoud.stop(activeMusicHandles[i]);
					activeMusicHandles[i] = 0;
				}
			}
		}

		private static void EnsureEffectsBus()
		{
			if (SoLoud.isValidVoiceHandle(effectsBusHandle) != 0)
			{
				return;
			}
			effectsBusHandle = SoLoud.play(effectsBus, effectsMasterVolume);
			SoLoud.setProtectVoice(effectsBusHandle, 1);
			SoLoud.setInaudibleBehavior(effectsBusHandle, 1, 0);
		}

		public static void SetVolumes(float master, float music, float effects)
		{
			masterVolume = master.IsFinite ? Math.Clamp(master, 0.0f, 1.0f) : 1.0f;
			musicMasterVolume = music.IsFinite ? Math.Clamp(music, 0.0f, 1.0f) : 1.0f;
			effectsMasterVolume = effects.IsFinite ? Math.Clamp(effects, 0.0f, 1.0f) : 1.0f;
			if (!initialized)
			{
				return;
			}
			EnsureEffectsBus();
			SoLoud.setGlobalVolume(masterVolume);
			SoLoud.setVolume(effectsBusHandle, effectsMasterVolume);
			OnUpdate(0.0f);
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
			SoLoud.setGlobalVolume(masterVolume);
			EnsureEffectsBus();
			var handle = effectsBus.play(audioClip.Clip, volume, pan);
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
			effectsBusHandle = 0;
		}
	}
}
