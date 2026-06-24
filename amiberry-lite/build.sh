#!/usr/bin/env bash
# build.sh — Build Amiberry Lite with the 1084S CRT shader and set up the
# environment on a new Pi (Raspberry Pi, Orange Pi, or similar SBC).
#
# Usage:
#   ./build.sh              # build only
#   ./build.sh --install    # build and install to /usr/bin/amiberry-lite
#
# Does NOT assume /home/pi. Uses $HOME throughout.
# Tested on Raspberry Pi 400, Debian Bookworm (aarch64),
# Mesa 25.0.7 / V3D 4.2 / OpenGL 3.1 / GLSL 1.40.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

AMIBERRY_REPO="https://github.com/BlitterStudio/amiberry-lite.git"
AMIBERRY_TAG="v5.9.2"
AMIBERRY_SRC="amiberry-lite-${AMIBERRY_TAG}"   # cloned into $PWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Paths under $HOME — no /home/pi anywhere below this line
ROM_DIR="${HOME}/Amiberry/ROMs"
LITE_DIR="${HOME}/Amiberry-Lite"
CONF_DIR="${LITE_DIR}/conf"
HDF_DIR="${LITE_DIR}/harddrives"
FLOPPY_DIR="${LITE_DIR}/floppies"
CDROM_DIR="${LITE_DIR}/cdroms"
AMIBERRY_CONF="${HOME}/.config/amiberry-lite/amiberry.conf"

# Files the configs require (by exact filename)
REQUIRED_ROMS=(
    "amiga-os-130.rom"          # Kickstart 1.3  — Amiga 2000
    "amiga-os-310-a1200.rom"    # Kickstart 3.1  — Amiga 1200
    "amiga-os-204-a3000.rom"    # Kickstart 2.04 — Amiga 3000
)
REQUIRED_HDFS=(
    "workbench-135.hdf"         # Workbench 1.3.5 — Amiga 2000
    "workbench-211.hdf"         # Workbench 2.1   — Amiga 3000
    "workbench-311.hdf"         # Workbench 3.1.1 — Amiga 1200
)

INSTALL=false
for arg in "$@"; do [[ "$arg" == "--install" ]] && INSTALL=true; done

# ── Helpers ───────────────────────────────────────────────────────────────────

ok()   { echo "    [OK]     $*"; }
found(){ echo "    [FOUND]  $*"; }
miss() { echo "    [MISSING] $*"; }
info() { echo "==> $*"; }
warn() { echo "!!! $*"; }

# Search $HOME for a filename (skip .git/.cache to stay fast).
find_file() {
    local name="$1"
    find "$HOME" -maxdepth 7 \
        -not -path "*/.git/*" \
        -not -path "*/.cache/*" \
        -not -path "*/proc/*" \
        -name "$name" \
        2>/dev/null | head -1
}

# ── 1. Dependencies ───────────────────────────────────────────────────────────

info "Checking build dependencies..."

PKGS=(
    git cmake ninja-build
    libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev
    libflac-dev libmpg123-dev
    libserialport-dev libportmidi-dev libenet-dev
    libmpeg2-4-dev libzstd-dev libpcap-dev
    libglew-dev libgl-dev libegl-dev
)

MISSING_PKGS=()
for pkg in "${PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    info "Installing: ${MISSING_PKGS[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${MISSING_PKGS[@]}"
else
    info "All build packages present."
fi

# ── 2. Directory structure ────────────────────────────────────────────────────

info "Creating directory structure under ${HOME}..."

for dir in \
    "$ROM_DIR" \
    "$CONF_DIR" \
    "$HDF_DIR" \
    "$FLOPPY_DIR" \
    "$CDROM_DIR" \
    "${LITE_DIR}/savestates" \
    "${LITE_DIR}/screenshots" \
    "${LITE_DIR}/lha" \
    "${LITE_DIR}/plugins" \
    "${LITE_DIR}/roms"; do
    if [[ -d "$dir" ]]; then
        ok "$dir"
    else
        mkdir -p "$dir"
        echo "    [CREATED] $dir"
    fi
done

# ── 3. Clone ──────────────────────────────────────────────────────────────────

if [[ -d "$AMIBERRY_SRC" ]]; then
    info "Source directory '${AMIBERRY_SRC}' already exists — skipping clone."
else
    info "Cloning Amiberry Lite ${AMIBERRY_TAG}..."
    git clone --depth=1 --branch "${AMIBERRY_TAG}" "${AMIBERRY_REPO}" "${AMIBERRY_SRC}"
fi

# ── 4. Apply shader patch ─────────────────────────────────────────────────────

info "Applying 1084S shader modifications..."
cp "${SCRIPT_DIR}/src/osdep/crtemu.h"         "${AMIBERRY_SRC}/src/osdep/crtemu.h"
cp "${SCRIPT_DIR}/src/osdep/amiberry_gfx.cpp" "${AMIBERRY_SRC}/src/osdep/amiberry_gfx.cpp"
ok "crtemu.h + amiberry_gfx.cpp applied"

# ── 5. Build ──────────────────────────────────────────────────────────────────

BUILD_DIR="${AMIBERRY_SRC}/build"

info "Configuring cmake..."
cmake -B "${BUILD_DIR}" \
    -S "${AMIBERRY_SRC}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_OPTIMIZE=ON \
    -DUSE_OPENGL=ON

info "Building with $(nproc) parallel jobs..."
cmake --build "${BUILD_DIR}" --parallel "$(nproc)"

BINARY="${BUILD_DIR}/amiberry-lite"
info "Build complete: ${BINARY} ($(du -h "$BINARY" | cut -f1))"

# ── 6. Verify shader compiled in ─────────────────────────────────────────────

if grep -qa "1084" "${BINARY}" && grep -qa "blur_luma" "${BINARY}"; then
    info "1084S shader verified in binary."
else
    warn "1084 shader strings not found in binary — build may be misconfigured."
    exit 1
fi

# ── 7. ROMs ───────────────────────────────────────────────────────────────────

info "Checking ROMs in ${ROM_DIR}..."

MISSING_ROMS=()
for rom in "${REQUIRED_ROMS[@]}"; do
    if [[ -f "${ROM_DIR}/${rom}" ]]; then
        ok "${rom}"
    else
        echo "    [??]     ${rom} — searching \$HOME..."
        hit="$(find_file "$rom")"
        if [[ -n "$hit" ]]; then
            found "${hit} -> ${ROM_DIR}/"
            cp "$hit" "${ROM_DIR}/${rom}"
        else
            miss "${rom}"
            MISSING_ROMS+=("$rom")
        fi
    fi
done

# ── 8. Hard drive images ──────────────────────────────────────────────────────

info "Checking hard drive images in ${HDF_DIR}..."

MISSING_HDFS=()
for hdf in "${REQUIRED_HDFS[@]}"; do
    if [[ -f "${HDF_DIR}/${hdf}" ]]; then
        ok "${hdf}"
    else
        echo "    [??]     ${hdf} — searching \$HOME..."
        hit="$(find_file "$hdf")"
        if [[ -n "$hit" ]]; then
            found "${hit} -> ${HDF_DIR}/"
            cp "$hit" "${HDF_DIR}/${hdf}"
            chmod 664 "${HDF_DIR}/${hdf}"
        else
            miss "${hdf}"
            MISSING_HDFS+=("$hdf")
        fi
    fi
done

# ── 9. Configs ────────────────────────────────────────────────────────────────

info "Installing configs to ${CONF_DIR}..."

for src in "${SCRIPT_DIR}/configs/"*.uae; do
    name="$(basename "$src")"
    dest="${CONF_DIR}/${name}"
    # Substitute the original /home/pi prefix with $HOME so paths are correct
    # on any user account or SBC.
    sed "s|/home/pi|${HOME}|g" "$src" > "$dest"
    ok "${name}"
done

# ── 10. amiberry.conf — set shader=1084 and fix paths ────────────────────────

if [[ -f "$AMIBERRY_CONF" ]]; then
    info "Updating ${AMIBERRY_CONF}..."
    # Fix any stale /home/pi paths from a previous install
    sed -i "s|/home/pi|${HOME}|g" "$AMIBERRY_CONF"
    # Set the shader
    if grep -q "^shader=" "$AMIBERRY_CONF"; then
        sed -i "s|^shader=.*|shader=1084|" "$AMIBERRY_CONF"
        ok "shader=1084 (updated)"
    else
        echo "shader=1084" >> "$AMIBERRY_CONF"
        ok "shader=1084 (appended)"
    fi
else
    info "${AMIBERRY_CONF} not found — it will be created by amiberry-lite on first run."
    echo "    Remember to add:  shader=1084"
fi

# ── 11. Install binary (optional) ─────────────────────────────────────────────

if [[ "$INSTALL" == true ]]; then
    DEST="/usr/bin/amiberry-lite"
    if [[ -f "$DEST" ]]; then
        info "Backing up existing binary to ${DEST}.bak"
        sudo cp "$DEST" "${DEST}.bak"
    fi
    info "Installing to ${DEST}..."
    sudo cp "${BINARY}" "${DEST}"
    ok "Installed."
fi

# ── 12. Final report ──────────────────────────────────────────────────────────

ERRORS=()
if [[ ${#MISSING_ROMS[@]} -gt 0 ]]; then
    for f in "${MISSING_ROMS[@]}"; do ERRORS+=("ROM:          ${f}"); done
fi
if [[ ${#MISSING_HDFS[@]} -gt 0 ]]; then
    for f in "${MISSING_HDFS[@]}"; do ERRORS+=("Hard drive:   ${f}"); done
fi

echo ""
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    warn "Build succeeded but required files could not be found anywhere under \$HOME:"
    for e in "${ERRORS[@]}"; do echo "      - ${e}"; done
    echo ""
    echo "  Copy the missing files to:"
    echo "      ROMs:        ${ROM_DIR}/"
    echo "      Hard drives: ${HDF_DIR}/"
    echo "  Then re-run this script."
    exit 1
fi

echo "==> All done."
echo "    Binary:   ${BINARY}"
[[ "$INSTALL" == true ]] && echo "    Installed: /usr/bin/amiberry-lite"
echo "    Configs:  ${CONF_DIR}/"
echo "    ROMs:     ${ROM_DIR}/"
echo "    HDFs:     ${HDF_DIR}/"
echo "    Shader:   shader=1084 (set in amiberry.conf on next run if not yet)"
