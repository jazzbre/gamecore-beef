using System;
using System.Collections;

namespace GameCore
{
	class JointAnimationJob
	{
		private const int maxJointCount = 128;

		private Ozz.SamplingJob samplingJob = new Ozz.SamplingJob(maxJointCount, 32) ~ delete _;
		private Ozz.BlendingJob blendingJob = new .(maxJointCount, 16, 4) ~ delete _;
		private Ozz.LocalToModelJob localToModelJob = new .(maxJointCount) ~ delete _;
		private List<Ozz.OzzSoaTransform*> layerTransforms = new .() ~ delete _;

		public bool Update(JointAnimationController controller)
		{
			// Sample
			blendingJob.ClearLayers();
			blendingJob.SetSkeleton(controller.Skeleton);
			for (var layer in controller.layers)
			{
				if (layer.weight > 0)
				{
					var transforms = samplingJob.Run(layer.animation, layer.time, layerTransforms.Count);
					if (transforms == null)
					{
						return false;
					}
					blendingJob.AddLayer(transforms, layer.weight);
				}
			}
			for (var layer in controller.additiveLayers)
			{
				if (layer.weight > 0)
				{
					var transforms = samplingJob.Run(layer.animation, layer.time, layerTransforms.Count);
					if (transforms == null)
					{
						return false;
					}
					blendingJob.AddAdditiveLayer(transforms, layer.weight);
				}
			}
			// Blend
			var blendedTransforms = blendingJob.Run();
			if (blendedTransforms == null)
			{
				return false;
			}
			localToModelJob.SetInput(controller.Skeleton, blendedTransforms);
			var modelMatrices = (Matrix4*)localToModelJob.Run();
			if (modelMatrices == null)
			{
				return false;
			}
			for (int i = 0; i < controller.modelMatrices.Count; ++i)
			{
				controller.modelMatrices[i] = modelMatrices[i];
			}
			return true;
		}
	}
}
