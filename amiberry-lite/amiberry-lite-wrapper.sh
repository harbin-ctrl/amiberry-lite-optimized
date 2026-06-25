#!/bin/sh
# Wrapper for amiberry-lite.
#
# A crash inside amiberry-lite can corrupt the Mesa shader cache, causing
# "Vertex Shader Error:" on every subsequent launch.  This wrapper gives
# amiberry its own isolated cache directory and clears it on each launch so
# a prior crash never blocks the next session — and other programs' caches
# are never touched.
AMIBERRY_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/amiberry-lite-shaders"
rm -rf "$AMIBERRY_CACHE"
mkdir -p "$AMIBERRY_CACHE"
export MESA_SHADER_CACHE_DIR="$AMIBERRY_CACHE"
exec /usr/local/bin/amiberry-lite.bin "$@"
