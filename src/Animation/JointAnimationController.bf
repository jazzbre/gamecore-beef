using System;
using System.Collections;

namespace Dedkeni
{
	class JointAnimationController
	{
		public Ozz.Skeleton Skeleton
		{
			set
			{
				skeleton = value;
				if (skeleton != null)
				{
					modelMatrices.Count = skeleton.JointCount;
				} else
				{
					modelMatrices.Clear();
				}
			}
			get
			{
				return skeleton;
			}
		}
		public List<Layer> layers = new .() ~ delete _;
		public List<Layer> additiveLayers = new .() ~ delete _;

		public List<Matrix4> modelMatrices = new .() ~ delete _;
		private Ozz.Skeleton skeleton;

		public struct Layer
		{
			public Ozz.Animation animation;
			public float time;
			public float weight;
		}

	}
}
