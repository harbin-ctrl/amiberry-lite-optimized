# amiberry-shaders

Making Amiga emulators on a Raspberry Pi look like a **Commodore 1084S** — and run at 60 fps
while doing it.

Three related pieces, each with its own history and its own README:

| | what it is |
|---|---|
| **[`amiberry-lite/`](amiberry-lite/)** | The 1084S CRT shader ported into [Amiberry Lite](https://github.com/BlitterStudio/amiberry-lite), plus OpenGL init fixes that were in the source but never wired in, a shader panel for the GUI, tuned `.uae` machine configs, and a build script that stands up a complete Amiga environment on a fresh Pi. |
| **[`1084-fast/`](1084-fast/)** | A branchless, heavily optimised rewrite of the classic 1084 CRT shader in slang format — ~4.7–6.5 ms/frame on a Pi 400, where the original stalls the pipeline on tiled mobile GPUs. |
| **[`fsuae-1084s/`](fsuae-1084s/)** | The same 1084S look ported to [FS-UAE](https://fs-uae.net/)'s shader format, calibrated against the Amiberry output. |

## Which one do I want?

- Running **Amiberry Lite** → `amiberry-lite/`
- Running **FS-UAE** → `fsuae-1084s/`
- Running anything that eats **slang/slangp** shaders (RetroArch, librashader, AltirraSDL) and
  want the fast path → `1084-fast/`

## Why they live together

They are one effort with three targets. The FS-UAE shader is a direct port of the Amiberry
one, and `1084-fast` is what the shader became after being taken apart for performance on
VideoCore VI. Keeping them in one place means a calibration fix in one can actually be
carried across to the others, rather than drifting in three repositories.

Reference hardware throughout is a **Raspberry Pi 400**, but nothing here is Pi-specific
beyond the tuning targets.

## Licensing

Each subdirectory keeps the licence of the upstream project it derives from — see the
`LICENSE` file in each.
