# Amiberry Lite — 1084S CRT Shader Port

Adds the **Commodore 1084S CRT monitor shader** to [Amiberry Lite](https://github.com/BlitterStudio/amiberry-lite), plus a build script that sets up a complete Amiga environment on a fresh Pi.

Amiberry Lite is faster than full Amiberry for CPU emulation on the Pi 400 but lacked the 1084S shader. This port brings it across, along with fixes to the OpenGL initialisation path that were present in the source but never wired in.

---

## Quick start

```bash
git clone https://github.com/harbin-ctrl/amiberry-shaders.git
cd Amiberry-lite-shader
./build.sh --install
```

Copy your ROM files and Workbench hard drive images into place if the script can't find them (see [Required files](#required-files)), then launch:

```bash
amiberry-lite
```

---

## What `build.sh` does

The script is a complete environment setup tool, not just a build wrapper. It handles everything needed to go from a bare Pi to a running Amiga emulator.

| Step | Action |
|------|--------|
| 1 | Installs missing build packages via `apt-get` |
| 2 | Creates the full `~/Amiberry-Lite/` directory tree under `$HOME` |
| 3 | Clones Amiberry Lite **v5.9.2** from GitHub (skips if already present) |
| 4 | Applies the 1084S shader modifications to `crtemu.h` and `amiberry_gfx.cpp` |
| 5 | Builds with `USE_OPENGL=ON` and `WITH_OPTIMIZE=ON` |
| 6 | Verifies the shader is present in the compiled binary |
| 7 | Checks each required ROM by filename in `~/Amiberry/ROMs/`; searches all of `$HOME` and copies it in if found elsewhere |
| 8 | Same search-and-copy for Workbench hard drive images into `~/Amiberry-Lite/harddrives/` |
| 9 | Installs the six stock machine configs, rewriting `/home/pi` → `$HOME` in all paths |
| 10 | Sets `shader=1084` in `~/.config/amiberry-lite/amiberry.conf` |
| 11 | *(--install only)* Runs `cmake --install` — installs the binary **and** the data directory (fonts, themes, icons) to system paths. Skipping this causes *"No usable font found in theme"* on first launch |
| 12 | Exits with a clear error listing any ROMs or hard drive images not found anywhere under `$HOME` |

`$HOME` is used throughout — `/home/pi` is never assumed. Works on Raspberry Pi, Orange Pi, or any similar SBC.

### Usage

```bash
./build.sh              # build only — run binary from build dir
./build.sh --install    # build + install system-wide (recommended)
```

---

## Required files

The script searches all of `$HOME` (7 levels deep) for these files and copies them into place automatically. If they cannot be found, the script exits with an error telling you exactly what to supply and where.

### Kickstart ROMs → `~/Amiberry/ROMs/`

| Filename | Used for |
|----------|----------|
| `amiga-os-130.rom` | Amiga 2000 (Kickstart 1.3) |
| `amiga-os-310-a1200.rom` | Amiga 1200 (Kickstart 3.1) |
| `amiga-os-204-a3000.rom` | Amiga 3000 (Kickstart 2.04) |

### Workbench hard drive images → `~/Amiberry-Lite/harddrives/`

| Filename | Used for |
|----------|----------|
| `workbench-135.hdf` | Amiga 2000 (Workbench 1.3.5) |
| `workbench-211.hdf` | Amiga 3000 (Workbench 2.1) |
| `workbench-311.hdf` | Amiga 1200 (Workbench 3.1.1) |

These are RDB-formatted images; geometry does not need to be set manually.

---

## Stock machine configs

Six configs are installed to `~/Amiberry-Lite/conf/` — PAL and NTSC variants for each machine:

| Machine | Kickstart | CPU | Chipset | RAM |
|---------|-----------|-----|---------|-----|
| Amiga 2000 | 1.3 rev 34.5 | 68000 @ 7 MHz | OCS | 1 MB chip |
| Amiga 1200 | 3.1 rev 40.68 | 68EC020 @ 14 MHz | AGA | 2 MB chip |
| Amiga 3000 | 2.04 rev 37.175 | 68030 @ 25 MHz + 68882 | ECS | 1 MB chip + 2 MB fast |

---

## What's changed in the source

### `src/osdep/crtemu.h`
Drop-in replacement. Adds:
- `CRTEMU_TYPE_1084` enum value
- `crtemu_shaders_1084()` — mobile-optimised GLSL shader tuned for the Pi's VideoCore VI (OpenGL 3.1, GLSL 1.40):
  - Nearly-flat barrel distortion (matching the 1084S's flat screen geometry)
  - Warm phosphor colour temperature
  - Aperture grille (Trinitron-style RGB stripe pattern)
  - Brightness-dependent scanlines
  - Mild halation from the blur buffer
  - Filmic tonemapping
- `crtemu_coordinates_window_to_bitmap` case for 1084 (inverse barrel for accurate mouse coordinates)

### `src/osdep/amiberry_gfx.cpp`
Drop-in replacement. Fixes and additions:
- `get_crtemu_type()` recognises `"1084"` and `"1084S"` as shader names
- Wires in `set_opengl_attributes()` before window creation — sets OpenGL 2.1 compatibility profile so GLSL 1.20 shaders are accepted (this function existed in the source but was never called)
- Wires in `init_opengl_context()` to replace the bare `SDL_GL_CreateContext` + `glewInit()` sequence — adds proper error handling and context validation
- Handles negative-dimension probe calls to `SDL2_alloctexture()` correctly in the OpenGL path

---

## Enabling the shader manually

If you are not using the build script, set this in `~/.config/amiberry-lite/amiberry.conf`:

```
shader=1084
```

Valid shader names: `tv`, `pc`, `lite`, `1084`, `1084S`

---

## Platform notes

Tested on **Raspberry Pi 400**, Debian Bookworm (aarch64), Mesa 25.0.7, V3D 4.2, OpenGL 3.1, GLSL 1.40. Should work on any Pi 4-class board or Orange Pi with a Mesa-based GPU driver.
