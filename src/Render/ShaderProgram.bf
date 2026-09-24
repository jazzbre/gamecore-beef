using System;
using System.Collections;
using System.Threading;

namespace GameCore;

public class ShaderProgram
{
    private static int64 nextProgramId;
    public readonly uint64 Id = (.)Interlocked.Increment(ref nextProgramId);
    public List<uint32> VertexCode = new .() ~ delete _;
    public List<uint32> FragmentCode = new .() ~ delete _;
}
