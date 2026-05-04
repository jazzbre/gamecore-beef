namespace Bgfx
{
	public extension bgfx
	{
		public extension VertexBufferHandle
		{
			public static VertexBufferHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension DynamicIndexBufferHandle
		{
			public static DynamicIndexBufferHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension DynamicVertexBufferHandle
		{
			public static DynamicVertexBufferHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension FrameBufferHandle
		{
			public static FrameBufferHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension IndexBufferHandle
		{
			public static IndexBufferHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension IndirectBufferHandle
		{
			public static IndirectBufferHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension OcclusionQueryHandle
		{
			public static OcclusionQueryHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension ProgramHandle
		{
			public static ProgramHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension ShaderHandle
		{
			public static ShaderHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension TextureHandle
		{
			public static TextureHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension UniformHandle
		{
			public static UniformHandle Null => .() { idx = uint16.MaxValue };
		}

		public extension VertexLayoutHandle
		{
			public static VertexLayoutHandle Null => .() { idx = uint16.MaxValue };
		}
	}
}