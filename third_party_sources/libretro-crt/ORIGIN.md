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

## Additional single-pass CRT families

The following original sources were retrieved at libretro/glsl-shaders commit
`f277bd87e454a68c50e01e61e3588118d56b1365`. Their complete headers are retained:

- `crt-aperture.glsl`: CRT Shader by EasyMode, header states "License: GPL".
  Source: `crt/shaders/crt-aperture.glsl` at the commit above.
- `crt-geom.glsl`: Copyright (C) 2010-2012 cgwg, Themaister and DOLLS,
  GPL version 2 or later. Source: `crt/shaders/crt-geom.glsl`.
- `crt-hyllian.glsl`: Copyright (C) 2011-2020 Hyllian, MIT license. Its embedded
  mask collection is by hunterk and explicitly public domain.
  Source: `crt/shaders/hyllian/crt-hyllian.glsl`.

Immutable source directory:
https://github.com/libretro/glsl-shaders/tree/f277bd87e454a68c50e01e61e3588118d56b1365/crt/shaders

These are iPhone single-pass adaptations with fixed, deliberately different
defaults. Aperture combines dual Lanczos reconstruction with a 3x3 Gaussian
halation/diffusion glow; reconstruction samples are aligned to progressive
source-row centers instead of adding half-row bilinear softening, while the
Gaussian pass supplies the glow. Geom retains the analytic spherical tube projection,
Lanczos reconstruction, rounded corners and generalized scanline beams; its
tilt is fixed to zero and its input is progressive, so no interlace history is
needed. Hyllian uses eight-tap Catmull-Rom reconstruction, anti-ringing,
per-channel beam width and the original mask collection's 2x2 delta layout.
Source-file line endings are normalized to LF; algorithm and license text in
the retained GLSL files is otherwise unchanged. These adaptations do not claim
to reproduce every parameter or external RetroArch preset.
