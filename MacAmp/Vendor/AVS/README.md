# libavs for MacAmp

Advanced Visualization Studio 2.81d (Nullsoft, 2005, BSD-3, `AVS-LICENSE.txt`) as split into the portable `libavs`
by the grandchild/vis_avs fork: https://github.com/grandchild/vis_avs at commit
`1cee1f3d4f783b830538c3e4d2082a2c59521dee` (2025-08-02). Built by `scripts/build_avs.sh` into a universal
`build/avs/libavs.dylib` (arm64 + x86_64); EEL2 expressions run interpreted (`EEL_TARGET_PORTABLE`), no JIT.

Taken: `avs/vis_avs` without the Win32 front end, `avs/3rdparty` (WDL-EEL2 unchanged, md_fft, json.h, pevents,
stb_image) and the platform layer. `compat/arm64`: sse2neon v1.8.0 (MIT) maps the SSE intrinsics to NEON.

MacAmp changes (marked `MacAmp:` in the code):
- macOS: `platform_macos.c` (the Linux POSIX layer), `__APPLE__` next to `__linux__`, `audio_in_macamp.cpp` (no recording)
- 64-bit: pointer casts in `e_effectlist.cpp`, `e_multidelay.cpp`, `e_videodelay.cpp`
- `avs_audio_set_legacy()`: the player passes Winamp's 576-sample vis data; the fork's float path overran its buffers
- fixes: `getosc()` pointer, SuperScope reading one sample past the end, Movement 50/50 blend source, uninitialised
  `global_ram` / compile hooks, Dynamic Movement table zeroed, blend LUTs clamped, `NO_MMX` bilinear blitter,
  leaked log strings, no debug output (`print_tree`, `printf`, `normalize_table.txt`)
- 2.81d's old APE names (`Winamp Mosaic v1` ...) map to the built-in effects again (`effect_library.cpp`)
- not built: Convolution (no licence text) and Texer II (x86 inline asm); Render / Text is not in libavs yet
