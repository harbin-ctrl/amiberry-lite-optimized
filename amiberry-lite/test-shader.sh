#!/usr/bin/env bash
# Exactly replicates the test Claude runs in the bash tool.
# Key difference from your method: uses -G (skip GUI, start emulation directly).
# This bypasses the GUI→emulation OpenGL context transition that you trigger
# by launching amiberry-lite and selecting a config from the menu.

set -euo pipefail

BINARY="$(which amiberry-lite)"
CONF="$HOME/.config/amiberry-lite/amiberry.conf"
CONFIG="$HOME/Amiberry-Lite/conf/Amiga 2000 NTSC.uae"

echo "=== Environment ==="
echo "Binary:   $BINARY"
echo "Shader:   $(grep '^shader=' "$CONF" || echo '(not set)')"
echo "Config:   $CONFIG"
echo "DISPLAY:  ${DISPLAY:-<unset>}"
echo "WAYLAND:  ${WAYLAND_DISPLAY:-<unset>}"
echo ""
echo "=== Running: timeout 6 amiberry-lite -f <config> -G --log ==="
echo "(This skips the GUI and starts emulation directly.)"
echo ""

timeout 6 amiberry-lite \
    -f "$HOME/Amiberry-Lite/conf/Amiga 2000 NTSC.uae" \
    -G \
    --log \
    2>&1 || true

echo ""
echo "=== Done ==="
