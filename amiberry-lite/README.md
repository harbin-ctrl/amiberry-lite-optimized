# Amiberry Lite — 1084S CRT Shader Port

This repo contains the changes needed to add the **Commodore 1084S CRT monitor shader** to [Amiberry Lite](https://github.com/BlitterStudio/amiberry-lite), along with stock Amiga machine configs for the Raspberry Pi 400.

The full Amiberry already has this shader. Amiberry Lite is faster for CPU emulation on the Pi 400 but lacked it — this port brings it across.

## What's included

### `src/osdep/crtemu.h`
Drop-in replacement for the same file in the Amiberry Lite source tree. Adds:
- `CRTEMU_TYPE_1084` enum value
- `crtemu_shaders_1084()` — mobile-optimised GLSL shader (works on Pi 400's VideoCore VI / Mesa V3D, OpenGL 3.1, GLSL 1.40):
  - Nearly-flat barrel distortion matching the 1084S's flat screen
  - Warm phosphor colour temperature
  - Aperture grille (Trinitron-style RGB stripe pattern)
  - Brightness-dependent scanlines
  - Mild halation from the blur buffer
  - Filmic tonemapping
- `crtemu_coordinates_window_to_bitmap` case for 1084 (inverse barrel for mouse coords)

### `src/osdep/amiberry_gfx.cpp`
Drop-in replacement for the same file. Adds:
- `get_crtemu_type()` recognises `"1084"` and `"1084S"` as shader names
- Wires in `set_opengl_attributes()` and `init_opengl_context()` (they existed but were never called)
- Handles negative-dimension probe calls to `SDL2_alloctexture` in the OpenGL path

### `configs/`
Six stock Amiga machine configs for Amiberry Lite (PAL and NTSC variants):

| Config | Kickstart | CPU | Chipset | RAM | Workbench |
|--------|-----------|-----|---------|-----|-----------|
| Amiga 2000 (PAL/NTSC) | 1.3 rev 34.5 | 68000 @ 7MHz | OCS | 1MB chip | 1.3.5 |
| Amiga 1200 (PAL/NTSC) | 3.1 rev 40.68 | 68EC020 @ 14MHz | AGA | 2MB chip | 3.1.1 |
| Amiga 3000 (PAL/NTSC) | 2.04 rev 37.175 | 68030 @ 25MHz + 68882 | ECS | 1MB chip + 2MB fast | 2.1 |

Hard drive images (`workbench-135.hdf`, `workbench-211.hdf`, `workbench-311.hdf`) are expected in `/home/pi/Amiberry-Lite/harddrives/`. ROMs are expected in `/home/pi/Amiberry/ROMs/`.

## Building

1. Clone [Amiberry Lite](https://github.com/BlitterStudio/amiberry-lite)
2. Replace `src/osdep/crtemu.h` and `src/osdep/amiberry_gfx.cpp` with the files from this repo
3. Build with OpenGL enabled:

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DWITH_OPTIMIZE=ON -DUSE_OPENGL=ON
cmake --build build --parallel $(nproc)
```

Tested on Raspberry Pi 400 (aarch64, Debian Bookworm, Mesa 25.0.7 / V3D 4.2, OpenGL 3.1).

## Enabling the shader

In `~/.config/amiberry-lite/amiberry.conf`:

```
shader=1084
```

Valid shader names: `tv`, `pc`, `lite`, `1084` / `1084S`
