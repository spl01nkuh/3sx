# CRT algorithm sources

These unmodified shader sources were retrieved from the primary libretro GLSL
shader collection at commit `1aaabbebdd88a8a89a82edfdc94e10580c99ffdd`.

- `crt-lottes.glsl`: Timothy Lottes; explicitly public domain.
- `zfast_crt.glsl`: Copyright (C) 2017 Greg Hogan (SoltanGris42), GPL version 2 or later.
- `crt-caligari.glsl`: Copyright (C) 2011 caligari; ported by Hyllian, GPL version 2 or later.

Immutable source directory:
https://github.com/libretro/glsl-shaders/tree/1aaabbebdd88a8a89a82edfdc94e10580c99ffdd/crt/shaders

The single-pass Metal adaptations are in
`src/platform/video/sdl_gpu/shaders/compiled/msl/ios_crt.frag`. They use Lottes'
Gaussian beams, screen warp and RGB mask; zfast's cubic sampling and
brightness-dependent scanlines; and Caligari's gamma-corrected phosphor spots.
They are adaptations for 3SX's canvas and iPhone output, rather than drop-in
libretro presets. Their defaults are deliberately different from each other.

The upstream authors' license and copyright notices are retained in every
source file. This project distributes the GPL-2.0-or-later adaptations under
GPL-3.0-or-later; the complete GPL version 3 text is in `COPYING.GPL3`.

Carlos' complete existing shader/preset collection remains in
`../carlos-crt/`. The EasyMode slot-mask adaptation retains its attribution.
The Sharp Bilinear scaler and lightweight YIQ Composite TV effect are 3SX
implementations; the latter does not emulate a complete NTSC signal chain.
