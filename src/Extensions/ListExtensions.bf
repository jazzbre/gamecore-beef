namespace System.Collections
{
	extension List<T>
	{
		public void Shuffle(ref PCGRandom random)
		{
			var count = Count - 1;
			for (int i = 0; i < count; ++i)
			{
				int j = i + 1 + (int)random.Next() % (count - i);
				Swap!(this[i], this[j]);
			}
		}
	}
}
