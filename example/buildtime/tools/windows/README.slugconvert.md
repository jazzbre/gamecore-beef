# slugconvert

Standalone offline TTF/static OTF to `.slugfont` compiler. FreeType 2.14.3 source is included in `third_party/freetype-2.14.3` and built as a static library. Conversion and inspection run without a graphics device, bgfx, or game libraries. `SlugFont.h` / `SlugFont.cc` provide a checked reader and glyph/kerning lookup that can also be used without FreeType.

## Build and use

From this directory on Windows with Visual Studio 2022 C++ tools and CMake 3.21 or newer:

```bat
build.bat
build\bin\Release\slugconvert.exe font.ttf title.slugfont --charset latin --stats title-stats.txt
build\bin\Release\slugconvert.exe --inspect title.slugfont
```

`build.bat Debug` builds Debug. The script finds CMake on `PATH`, in its standard installation directory, or in Visual Studio's C++ CMake tools. It generates `build/slugconvert.sln` for Visual Studio 2022, x64. You can also configure and build directly:

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target slugconvert --parallel
```

Builds use only the included FreeType source and need no downloads or package manager. FreeType's optional external libraries are disabled; its bundled zlib code remains available. Both FreeType and the Visual C++ runtime are linked statically, so the executable needs no FreeType DLL or Visual C++ redistributable. The build copies `LICENSE.freetype.txt`, `LICENSE.bgfx`, and this README beside the executable; keep those notices with the tool. Windows with the Visual Studio C++ tools is the supported target.

```bat
slugconvert font.ttf font.slugfont --chars-file requiredchars.txt
slugconvert font.otf font.slugfont --charset ascii --range U+0100-U+017F
slugconvert font.ttf font.slugfont --charset none --range U+1F600 --fallback U+003F
```

The default `latin` preset selects U+0020–U+024F and U+1E00–U+1EFF, including č/š/ž and uppercase variants. `ascii` selects U+0020–U+007E. Explicit selections replace the default; repeated presets, ranges, and character files form a union. `none` adds no preset. Character files contain literal strict UTF-8 text, optionally with a BOM; tabs, CR and LF are skipped. Numeric codepoint lists are passed using `--range` instead.

Glyph zero, space, and the fallback are always included. The default fallback is U+FFFD when available, otherwise source glyph zero. An explicitly requested fallback must exist. Unavailable selected codepoints map to the fallback; aliases share a single glyph record. Codepoint zero always maps to source glyph zero. Output is deterministic for the same source, options, and FreeType version; no timestamps or input paths are embedded.

Both textures have width 4096 and format RGBA32F, with point filtering, clamp addressing and no mipmaps. `--max-texture-height` defaults to 16384 and accepts 1–65535. Runtime hardware must support width 4096 and both declared heights. The compiler rejects a glyph whose band lists cannot fit in one row, excessive texture heights, and files larger than 512 MiB. Band data uses one row per unique selected glyph, so even a small character subset can produce a multi-megabyte file. V1 stores uncompressed textures.

## Kerning and text layout

All positions, advances, bearings, rectangles, kerning, ascent, descent and line gap are normalized to em-space. Multiply by the requested font size. Coordinates are Cartesian: X right, Y up, origin at the baseline. Vertical metrics come from `hhea`, matching the reference's metric choice. Source units-per-em is retained. Bearings follow the outline control box: bearing X is rectangle minimum X, bearing Y is rectangle maximum Y, matching the reference. A CFF control-box bearing can differ from the source `hmtx` left side bearing. Zero-outline glyphs such as spaces retain advances and have empty band headers; skip drawing their quads.

Kerning uses `kern` features of the selected script's default GPOS language system (`--script latn` by default, falling back to `DFLT`). Pair positioning formats 1/2 and extension-to-pair lookups are supported, with the first matching subtable per lookup and additive lookup adjustments. If no such GPOS lookups apply, legacy FreeType unscaled kerning is used. GPOS and legacy kerning are not added together. Both negative and positive X-advance adjustments are retained, sorted by runtime glyph IDs.

V1 represents adjacent pairs for simple horizontal text. Contextual lookups, nonzero placement/second-glyph/device adjustments, and shaping-dependent lookup flags are rejected rather than silently discarded. The IgnoreMarks lookup flag is accepted for adjacent pairs only; skipping intervening marks requires a shaping implementation. `--no-kerning` explicitly omits kerning. Kerning enumeration is limited to 4096 selected glyphs; larger subsets require `--no-kerning`. General substitutions, ligatures, combining-mark placement, script shaping, vertical layout, variable fonts, font collections, and bitmap/color/SVG-only glyphs are outside v1.

Runtime text layout handles tabs and line breaks rather than drawing glyphs: CR is ignored, LF resets X and subtracts `(ascent - descent + lineGap) * size` from the baseline, and tabs advance to a chosen space-based tab stop. Reset the previous kerning glyph on line breaks/tabs. Decode UTF-8 before `FindGlyph`; use `GetKerning(leftID, rightID)` between adjacent glyphs and then add the current glyph advance.

## GPU compatibility

Curve conversion, band ordering and packing follow [bgfx example 51](https://github.com/bkaradzic/bgfx/blob/01dbbbc08c093f7ccf8adf7bd685739b344e9102/examples/51-gpufont/gpufont.cpp), pinned at `01dbbbc08c093f7ccf8adf7bd685739b344e9102`. Cubics use the reference's two-quadratic approximation. FreeType supplies unhinted, unscaled outlines. For TrueType, source `glyf` bounds are retained and FreeType's side-bearing origin translation is undone so outline coordinates match the reference convention. This tool does not promise bit-identical outline coordinates to stb_truetype for every font. Glyph order is sorted source glyph order, with deterministic curve-index tie breaking. Band counts are clamped before narrowing, avoiding the reference's truncation for complex outlines.

Each quadratic occupies two consecutive curve texels: `(p1.x, p1.y, p2.x, p2.y)` then `(p3.x, p3.y, 0, 0)`. Even indexing keeps both on the same row. Each glyph's band row contains horizontal headers, vertical headers, then curve locations. Headers are `(curveCount, relativeTexelOffset, 0, 0)`; locations are `(curveTexelX, curveTexelY, 0, 0)`. Band lists are sorted descending by maximum X for horizontal bands and maximum Y for vertical bands. Empty glyphs have two all-zero headers.

For the reference [vertex shader](https://github.com/bkaradzic/bgfx/blob/01dbbbc08c093f7ccf8adf7bd685739b344e9102/examples/51-gpufont/vs_slug.sc), bit-cast `(glyphLocationY << 16) | glyphLocationX` to `tex.z`, and `(bandMaximumY << 16) | bandMaximumX` to `tex.w`. Do not numerically convert those packed integers to floats. Banding is `(bandScaleX, bandScaleY, bandOffsetX, bandOffsetY)`. Use glyph rectangles as em-space sample coordinates and scale object-space positions by font size. The [fragment shader](https://github.com/bkaradzic/bgfx/blob/01dbbbc08c093f7ccf8adf7bd685739b344e9102/examples/51-gpufont/fs_slug.sc) consumes these texture bytes directly.

Game renderer integration and GPU image comparison are separate from this offline tool. The reusable reader validates and decodes the file before a renderer uploads the two texture buffers. It needs no original TTF/OTF, outline processing, or runtime FreeType/stb_truetype calls. A big-endian host must upload the reader's decoded float buffers rather than the original little-endian bytes.

## SLGF v1 binary format

All integers are unsigned little-endian unless otherwise stated. Floats are IEEE-754 binary32. Never read disk records by casting a native struct. File size is at most 512 MiB. The fixed header is 288 bytes, including five 32-byte section records. Section starts are aligned to 16 bytes; alignment bytes are zero. Sections appear in type order. CRC32 is the standard reflected IEEE polynomial `0xEDB88320`, initial/final XOR `0xFFFFFFFF`, over the complete file with bytes 24–27 treated as zero.

| Header offset | Type | Meaning |
|---:|---|---|
| 0 | 4 bytes | ASCII `SLGF` |
| 4 | u16 | Version: 1 |
| 6 | u16 | Header bytes: 288 |
| 8 | u32 | Endianness marker: 0x01020304 |
| 12 | u32 | Flags: 0 (uncompressed) |
| 16 | u64 | Exact file size |
| 24 | u32 | Whole-file CRC32 |
| 28 | u32 | Section count: 5 |
| 32 / 36 / 40 | u32 each | Glyph / cmap / kerning counts |
| 44 | u32 | Fallback runtime glyph ID |
| 48 / 52 / 56 | u32 each | Texture width / curve height / band height |
| 60 | u32 | Texture format: 1 = RGBA32F, both textures |
| 64 | u32 | Sampling flags: 1=point, 2=clamp, 4=no mipmaps; required value 7 |
| 68 | u32 | Source units per em |
| 72 / 76 / 80 | f32 each | Ascent / descent / line gap in em-space |
| 84 | u32 | Total quadratic curve count |
| 88 / 92 / 96 | u32 each | Glyph / cmap / kerning record sizes: 80 / 8 / 12 |
| 100 | u32 | Maximum bands per axis: 8 |
| 104–127 | 24 bytes | Reserved zero |
| 128–287 | 5 records | Section directory |

A section record is `type:u32, stride:u32, offset:u64, size:u64, count:u64`. `size == stride * count`. Types are 1=glyphs (stride 80), 2=cmap (8), 3=kerning (12), 4=curve texels (16), 5=band texels (16). For textures, count means texels, with RGBA component order, tightly packed rows, no row padding. An empty kerning section has size/count zero and still has an aligned offset.

Glyph records use runtime IDs 0…N−1, sorted by strictly increasing source glyph index. Source glyph zero is runtime ID zero. Curve ranges partition the curve array in that order. Band texture height equals glyph count; each glyph has location X=0, Y=runtime ID.

| Glyph offset | Type | Meaning |
|---:|---|---|
| 0 / 4 | u32 each | Runtime glyph ID / source glyph index |
| 8 / 12 / 16 | f32 each | Advance X / bearing X / bearing Y |
| 20 / 24 / 28 / 32 | f32 each | Rectangle minimum X/Y, maximum X/Y |
| 36 / 38 | u16 each | Band texture glyph location X/Y |
| 40 / 42 | u16 each | Maximum vertical/horizontal band indices |
| 44 / 48 / 52 / 56 | f32 each | Band scale X/Y, offset X/Y |
| 60 / 64 | u32 each | First curve index / curve count |
| 68 | u32 | Flags: 1=empty outline; otherwise 0 |
| 72–79 | 8 bytes | Reserved zero |

Cmap records are `codepoint:u32, runtimeGlyphID:u32`, strictly increasing by Unicode scalar. Multiple entries can share a glyph. Kerning records are `leftGlyphID:u32, rightGlyphID:u32, adjustment:f32`, strictly ordered by `(left, right)` with only nonzero adjustments. No shaping tables, source-font data, timestamps or pointers are included.

`LoadFont` rejects incompatible versions/flags, bad CRCs, malformed counts, section overlap/truncation, texture limits, non-finite values, invalid glyph/cmap/pair order, invalid curve ownership, unsorted bands and references that cross rows. `--inspect` exercises that same reader. Conversion validates its serialized result before replacing an output file; writes use a sibling temporary file so failed conversion does not overwrite existing output.

## Licenses

Reference-derived preprocessing retains the bgfx BSD-2-Clause notice in `LICENSE.bgfx`. The reference shaders have a separate MIT license in the [original Slug repository](https://github.com/EricLengyel/Slug). FreeType is used under the FreeType License in `third_party/freetype-2.14.3/docs/FTL.TXT`; its license overview and alternative GPL license are retained in the included source. Download provenance and the source archive's SHA-256 are recorded in `third_party/README.md`. Source font embedding/distribution permissions still apply to generated vector-outline assets.

This software is based in part on the work of the FreeType Team.
