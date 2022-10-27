namespace Dedkeni
{
	static class JointAnimationManager
	{
		public static JointAnimationJob animationJob = new .() ~ delete _;

		public static void OnInitialize()
		{
		}

		public static void OnFinalize()
		{
		}

		public static void UpdateAnimation(JointAnimationController controller)
		{
			animationJob.Update(controller);
		}
	}
}
