using System;
using System.Collections;

namespace GameCore;

class ShaderStageCompilation
{
    public String VariantName = new .() ~ delete _;
    public String EntryPoint = new .() ~ delete _;
    public ShaderStage Stage;
    // The manifest owns these strings until every compilation has finished.
    public List<String> Defines = new .() ~ delete _;
    public List<uint8> Bytecode = new .() ~ delete _;
    public String Error = new .() ~ delete _;
    public bool Succeeded;
}
