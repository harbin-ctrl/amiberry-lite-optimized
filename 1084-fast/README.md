# 1084-fast (Raspberry Pi / Low-End GPU Optimized)

This is a heavily optimized, ultra-fast version of the classic 1084 CRT shader, specifically engineered for tiled mobile architectures and low-power hardware like the Raspberry Pi (VideoCore VI).

The original shader is incredibly accurate but relies on complex conditional branching, texture sampling hacks, and nested clamps that cause massive pipeline stalls on mobile GPUs, leading to frame drops. This version mathematically simplifies the pipeline to allow the GPU to run pure SIMD arithmetic across the entire screen without stalling.

## What is Better?
* **Performance:** Executes in roughly 4.7ms - 6.5ms per frame on a standard Raspberry Pi 400.
* **60 FPS Locked:** Easily sustains a rock-solid 60 FPS in emulators like AltirraSDL at 720p/1080p output resolutions.
* **Branchless:** Replaced divergent `if/else` statements with GPU-friendly step/abs mathematics.

## What Changed?
* **Vectorized Border Logic:** Replaced expensive conditional border checks with a single mathematical `step()` function.
* **Scanline Alignment:** Simplified the scanline and moire interference calculations by locking them purely to the `SourceSize.y` uniform. This is dynamically injected by your emulator, meaning it automatically adapts to whatever system you are running without any manual configuration required. (e.g., 224p for SNES, 240p for NES, or 480i for PS1).
* **Removed Clamp Saturation:** Removed redundant `clamp` boundaries, allowing the GPU stream processors to vectorize the fragment math without halting.

## What is Lost?
* **Sub-pixel Accuracy on Extreme Scales:** Because we removed the heavy `textureLod` lookups and edge-case clamps, the shader might exhibit minor artifacting if you attempt to scale it to non-integer or extremely bizarre aspect ratios. (Stick to standard 3x, 4x, 5x integer vertical scaling).
* **Anti-Moire Hacks:** The original shader used complex logic to dynamically fight moire patterns at the cost of performance. We simply lock the scanlines to the physical source resolution grid instead, which requires the host emulator to scale cleanly to avoid interference.

## Usage
Load `1084.slangp` into any librashader-compatible frontend. For maximum performance on Raspberry Pi, ensure your emulator caps the internal shader resolution to no more than 3x (approx 720p), as 3x is the minimum number of pixels required to cleanly render a 1-gap/2-lit CRT phosphor triad without wasting VRAM bandwidth.
