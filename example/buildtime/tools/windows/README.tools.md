# Windows resource tools

GameCore runs `slangc.exe` and `slugconvert.exe` only from this directory.
Copy these files and their notices together into each game's
`buildtime/tools/windows/`.

- `slangc.exe`, `slang-compiler.dll`, and `slang-glsl-module.dll`: Slang 2026.17, copied from Vulkan SDK 1.4.357.0.
- `dxcompiler.dll`: DirectX Shader Compiler 1.9.0.5399 (`a107ba613`), required by Slang's DXIL target.
- `slugconvert.exe`: prebuilt converter from the sibling Slug converter project; see `README.slugconvert.md`.

The Slang bundle supports the DXIL target used by GameCore. Other Slang
targets may require additional compiler modules. Keep all tool files under
this directory when adding them. Tool files are used while building
resources and are not required in packaged runtime games.

License files and third-party notices accompany the corresponding tools.
