#!/usr/bin/env bash
# build.sh — Download Amiberry Lite v5.9.2, apply 1084S shader patch, and build.
#
# Usage:
#   ./build.sh              # build only
#   ./build.sh --install    # build and install to /usr/bin/amiberry-lite
#
# Tested on Raspberry Pi 400, Debian Bookworm (aarch64),
# Mesa 25.0.7 / V3D 4.2 / OpenGL 3.1 / GLSL 1.40.

set -euo pipefail

AMIBERRY_REPO="https://github.com/BlitterStudio/amiberry-lite.git"
AMIBERRY_TAG="v5.9.2"
AMIBERRY_DIR="amiberry-lite-${AMIBERRY_TAG}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTALL=false
for arg in "$@"; do
    [[ "$arg" == "--install" ]] && INSTALL=true
done

# ── 1. Dependencies ────────────────────────────────────────────────────────────

echo "==> Checking build dependencies..."

PKGS=(
    git cmake ninja-build
    libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev
    libflac-dev libmpg123-dev
    libserialport-dev libportmidi-dev libenet-dev
    libmpeg2-4-dev libzstd-dev libpcap-dev
    libglew-dev
    libgl-dev libegl-dev
)

MISSING=()
for pkg in "${PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "==> Installing missing packages: ${MISSING[*]}"
    sudo apt-get install -y "${MISSING[@]}"
else
    echo "==> All dependencies present."
fi

# ── 2. Clone ───────────────────────────────────────────────────────────────────

if [[ -d "$AMIBERRY_DIR" ]]; then
    echo "==> Source directory '$AMIBERRY_DIR' already exists, skipping clone."
else
    echo "==> Cloning Amiberry Lite ${AMIBERRY_TAG}..."
    git clone --depth=1 --branch "${AMIBERRY_TAG}" "${AMIBERRY_REPO}" "${AMIBERRY_DIR}"
fi

# ── 3. Apply shader patch ──────────────────────────────────────────────────────

echo "==> Applying 1084S shader modifications..."

cp "${SCRIPT_DIR}/src/osdep/crtemu.h"       "${AMIBERRY_DIR}/src/osdep/crtemu.h"
cp "${SCRIPT_DIR}/src/osdep/amiberry_gfx.cpp" "${AMIBERRY_DIR}/src/osdep/amiberry_gfx.cpp"

echo "    crtemu.h        -> ${AMIBERRY_DIR}/src/osdep/"
echo "    amiberry_gfx.cpp -> ${AMIBERRY_DIR}/src/osdep/"

# ── 4. Build ───────────────────────────────────────────────────────────────────

BUILD_DIR="${AMIBERRY_DIR}/build"

echo "==> Configuring cmake..."
cmake -B "${BUILD_DIR}" \
    -S "${AMIBERRY_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_OPTIMIZE=ON \
    -DUSE_OPENGL=ON

echo "==> Building ($(nproc) jobs)..."
cmake --build "${BUILD_DIR}" --parallel "$(nproc)"

BINARY="${BUILD_DIR}/amiberry-lite"

echo ""
echo "==> Build complete: ${BINARY}"
echo "    $(file "${BINARY}")"
echo "    $(du -h "${BINARY}" | cut -f1) on disk"

# ── 5. Verify shader is compiled in ───────────────────────────────────────────

if grep -qa "1084" "${BINARY}" && grep -qa "blur_luma" "${BINARY}"; then
    echo "==> 1084S shader verified in binary."
else
    echo "!!! WARNING: 1084 shader strings not found in binary — something may have gone wrong."
    exit 1
fi

# ── 6. Install (optional) ──────────────────────────────────────────────────────

if [[ "$INSTALL" == true ]]; then
    DEST="/usr/bin/amiberry-lite"
    if [[ -f "$DEST" ]]; then
        echo "==> Backing up existing binary to ${DEST}.bak"
        sudo cp "$DEST" "${DEST}.bak"
    fi
    echo "==> Installing to ${DEST}..."
    sudo cp "${BINARY}" "${DEST}"
    echo "==> Installed."
fi

echo ""
echo "Done. To enable the 1084S shader, set in ~/.config/amiberry-lite/amiberry.conf:"
echo "    shader=1084"
