using System;

namespace GameCore;
[CRepr]
public struct CrtParameters
{
    public Vector4 Blur;
    public Vector4 Modulate;
    public Vector4 ModulateAndTime;
    public Vector4 ResolutionAndUseFrame;
    public Vector4 ConfigA;
    public Vector4 ConfigB;
    public Vector4 ConfigC;
    public Vector4 ConfigD;
    public Vector4 ConfigE;
}
