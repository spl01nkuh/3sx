# Retained CRT shader collection

Source: https://github.com/carlosefr/retroarch-shaders

All 28 presets and all eight GLSL shader files from the collection are retained,
with their original notices. README.md is the upstream documentation.
Screenshots are not required by the shaders and are not included.

The iOS renderer contains Metal adaptations of CRT EasyMode Fast, sharp mask,
noise, adaptive blend, color controls, and composite scaling. The runtime menu
provides 15 effects plus Off. The source presets requiring external libretro
shaders, multiple render passes, or previous-frame feedback remain available
here; they are not falsely exposed as supported iOS effects.

The adapted CRT Scanlines color-control pass is folded into the four texture
samples. CRT TV, slot-mask, monitor, EGA and VGA parameter sets follow the
upstream presets. The standalone Color Controls option uses the scanlines
preset's black-level correction. The originals are preserved for future ports.

Shader licensing: retain each file's header. CRT EasyMode states "License: GPL";
Carlos' remaining shader files state GPL version 2 or later.
