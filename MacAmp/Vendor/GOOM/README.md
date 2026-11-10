# GOOM for MacAmp

The original C renderer comes from Fred Howell's `wgoom-1.99-src.zip`, whose SHA-256 is `1e670baaf8b1c82a26e4ed205b7a4f035f47516773e3d1032b44386b0d6d8fc8`. The Winamp module in that archive identifies itself as 1.99.4. [Source release](https://sourceforge.net/projects/goom/files/win_goom/wgoom-1.99/)

The license and credits are in [GOOM-LICENSE.txt](GOOM-LICENSE.txt), [COPYING](COPYING) and [AUTHORS.txt](AUTHORS.txt).

`core/` contains the renderer, bitmap font and credits from the release. The port uses the original scalar renderer on both macOS architectures. It fixes 64-bit pointer alignment, bounded text copies, buffer cleanup, integer operations that depended on the Win32 compiler, and the uninitialized entry in the random-number table. `MacAmpGoom.c` converts stereo Float32 PCM into the 512 signed 8-bit waveform samples per channel that Winamp supplied, represented in GOOM's original 16-bit layout.

Run `scripts/build_goom.sh` to build the universal dynamic library and package the corresponding source and license under `build/goom/`.
