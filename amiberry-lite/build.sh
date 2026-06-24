#!/usr/bin/env bash
# build.sh — Full environment setup and build for Amiberry Lite with the
# Commodore 1084S CRT shader, on Raspberry Pi, Orange Pi, or any similar SBC.
#
# What this script does, in order:
#   1. Removes any conflicting full-Amiberry (dpkg) installation, its apt
#      source, and keyring, so only our build-from-source version remains
#   2. (reserved — old step 1 absorbed into 3)
#   3. Installs missing build packages via apt-get
#   4. Creates the expected Amiberry-Lite directory tree under $HOME
#   5. Clones Amiberry Lite v5.9.2 from GitHub (skips if already present)
#   6. Applies the 1084S shader modifications (crtemu.h + amiberry_gfx.cpp)
#   7. Builds with OpenGL enabled (USE_OPENGL=ON)
#   8. Verifies the shader is compiled into the binary
#   9. Checks required ROM files; searches all of $HOME if not in place,
#      copies them into ~/Amiberry-Lite/roms/ when found
#  10. Checks required hard drive images; searches all of $HOME if absent,
#      copies them into ~/Amiberry-Lite/harddrives/ when found
#  11. Installs the six stock machine configs (A2000/A1200/A3000, PAL+NTSC),
#      rewriting /home/pi -> $HOME in all paths
#  12. Sets shader=1084 in ~/.config/amiberry-lite/amiberry.conf
#  13. (--install only) Runs cmake --install so the binary AND data directory
#      (fonts, themes, icons) land in the right system locations — skipping
#      this step causes "No usable font found in theme" on first launch
#  14. Exits with a clear error listing any ROMs or hard drive images that
#      could not be found anywhere under $HOME
#
# Usage:
#   ./build.sh              # build only; run binary from build dir
#   ./build.sh --install    # build + install system-wide
#
# Does NOT assume /home/pi — uses $HOME throughout.
# Tested on Raspberry Pi 400, Debian Bookworm (aarch64),
# Mesa 25.0.7 / V3D 4.2 / OpenGL 3.1 / GLSL 1.40.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

AMIBERRY_REPO="https://github.com/BlitterStudio/amiberry-lite.git"
AMIBERRY_TAG="v5.9.2"
AMIBERRY_SRC="amiberry-lite-${AMIBERRY_TAG}"   # cloned into $PWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Paths under $HOME — no /home/pi anywhere below this line
ROM_DIR="${HOME}/Amiberry-Lite/roms"
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

# ── 1. Remove conflicting amiberry (full) installations ──────────────────────

info "Removing full Amiberry (dpkg) if installed..."

if dpkg -s amiberry &>/dev/null; then
    sudo apt-get purge -y amiberry
    ok "amiberry dpkg purged"
else
    ok "amiberry dpkg not present"
fi

for f in \
    /etc/apt/sources.list.d/amiberry.sources \
    /usr/share/keyrings/amiberry-archive-keyring.gpg \
    /usr/bin/amiberry-lite; do
    if [[ -e "$f" ]]; then
        sudo rm -f "$f"
        ok "removed $f"
    fi
done

# ── 3. Dependencies ───────────────────────────────────────────────────────────

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

# ── 4. Directory structure ────────────────────────────────────────────────────

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

# ── 5. Clone ──────────────────────────────────────────────────────────────────

if [[ -d "$AMIBERRY_SRC" ]]; then
    info "Source directory '${AMIBERRY_SRC}' already exists — skipping clone."
else
    info "Cloning Amiberry Lite ${AMIBERRY_TAG}..."
    git clone --depth=1 --branch "${AMIBERRY_TAG}" "${AMIBERRY_REPO}" "${AMIBERRY_SRC}"
fi

# ── 6. Apply shader patch ─────────────────────────────────────────────────────

info "Applying 1084S shader modifications..."
cp "${SCRIPT_DIR}/src/osdep/crtemu.h"         "${AMIBERRY_SRC}/src/osdep/crtemu.h"
cp "${SCRIPT_DIR}/src/osdep/amiberry_gfx.cpp" "${AMIBERRY_SRC}/src/osdep/amiberry_gfx.cpp"
ok "crtemu.h + amiberry_gfx.cpp applied"

# ── 7. Build ──────────────────────────────────────────────────────────────────

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

# ── 8. Verify shader compiled in ─────────────────────────────────────────────

if grep -qa "1084" "${BINARY}" && grep -qa "blur_luma" "${BINARY}"; then
    info "1084S shader verified in binary."
else
    warn "1084 shader strings not found in binary — build may be misconfigured."
    exit 1
fi

# ── 9. ROMs ───────────────────────────────────────────────────────────────────
#
# Amiga Forever ROMs are XOR-encrypted with rom.key (11-byte "AMIROMTYPE1"
# header, then the ROM data XOR'd with rom.key cycling).  Decrypt on the fly
# if we find a rom.key alongside the ROM file.

CLOANTO_HEADER='AMIROMTYPE1'

# Decrypt a Cloanto ROM in-place to DST using KEY.
decrypt_rom() {
    local src="$1" dst="$2" key="$3"
    python3 - "$src" "$dst" "$key" <<'PYEOF'
import sys
src, dst, key_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(key_path, 'rb') as f: key = f.read()
with open(src, 'rb') as f: data = f.read()
enc = data[11:]  # skip AMIROMTYPE1 header
out = bytes(b ^ key[i % len(key)] for i, b in enumerate(enc))
with open(dst, 'wb') as f: f.write(out)
PYEOF
}

info "Checking ROMs in ${ROM_DIR}..."

MISSING_ROMS=()
for rom in "${REQUIRED_ROMS[@]}"; do
    if [[ -f "${ROM_DIR}/${rom}" ]]; then
        # Already present — check if it's still encrypted
        header="$(head -c 11 "${ROM_DIR}/${rom}" 2>/dev/null || true)"
        if [[ "$header" == "$CLOANTO_HEADER" ]]; then
            echo "    [DECRYPT] ${rom} — Cloanto-encrypted, decrypting in place..."
            key="$(find_file "rom.key")"
            if [[ -z "$key" ]]; then
                warn "rom.key not found — cannot decrypt ${rom}"
                MISSING_ROMS+=("$rom")
            else
                tmp="${ROM_DIR}/${rom}.tmp"
                decrypt_rom "${ROM_DIR}/${rom}" "$tmp" "$key"
                mv "$tmp" "${ROM_DIR}/${rom}"
                ok "${rom} (decrypted)"
            fi
        else
            ok "${rom}"
        fi
    else
        echo "    [??]     ${rom} — searching \$HOME..."
        hit="$(find_file "$rom")"
        if [[ -n "$hit" ]]; then
            found "${hit} -> ${ROM_DIR}/"
            header="$(head -c 11 "$hit" 2>/dev/null || true)"
            if [[ "$header" == "$CLOANTO_HEADER" ]]; then
                echo "    [DECRYPT] ${rom} — Cloanto-encrypted..."
                key="$(find_file "rom.key")"
                if [[ -z "$key" ]]; then
                    warn "rom.key not found — cannot decrypt ${rom}"
                    MISSING_ROMS+=("$rom")
                else
                    decrypt_rom "$hit" "${ROM_DIR}/${rom}" "$key"
                    ok "${rom} (decrypted)"
                fi
            else
                cp "$hit" "${ROM_DIR}/${rom}"
                ok "${rom} (copied)"
            fi
        else
            miss "${rom}"
            MISSING_ROMS+=("$rom")
        fi
    fi
done

# ── 10. Hard drive images ─────────────────────────────────────────────────────

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

# ── 11. Configs ───────────────────────────────────────────────────────────────

info "Installing configs to ${CONF_DIR}..."

for src in "${SCRIPT_DIR}/configs/"*.uae; do
    name="$(basename "$src")"
    dest="${CONF_DIR}/${name}"
    # Substitute the original /home/pi prefix with $HOME so paths are correct
    # on any user account or SBC.
    sed "s|/home/pi|${HOME}|g" "$src" > "$dest"
    ok "${name}"
done

# ── 12. amiberry.conf — set shader=1084 and fix paths ────────────────────────

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
    info "Creating ${AMIBERRY_CONF} with shader=1084..."
    mkdir -p "$(dirname "$AMIBERRY_CONF")"
    printf 'shader=1084\n' > "$AMIBERRY_CONF"
    ok "shader=1084 (created)"
fi

# ── 13. Install (optional) ────────────────────────────────────────────────────
#
# Uses "cmake --install" rather than a bare binary copy so that the data
# directory (fonts, themes, icons, whdboot, controllers) is installed to
# /usr/share/amiberry-lite/ alongside the binary.  Without the data dir the
# GUI throws "No usable font found in theme" on first launch.

if [[ "$INSTALL" == true ]]; then
    DEST="/usr/bin/amiberry-lite"
    if [[ -f "$DEST" ]]; then
        info "Backing up existing binary to ${DEST}.bak"
        sudo cp "$DEST" "${DEST}.bak"
    fi
    info "Installing via cmake --install (binary + data directory)..."
    sudo cmake --install "${BUILD_DIR}"
    ok "Installed: binary -> /usr/bin/amiberry-lite"
    ok "Installed: data   -> /usr/share/amiberry-lite/"
fi

# ── 14. Final report ──────────────────────────────────────────────────────────

ERRORS=()
if [[ ${#MISSING_ROMS[@]} -gt 0 ]]; then
    for f in "${MISSING_ROMS[@]}"; do ERRORS+=("ROM:          ${f}"); done
fi
if [[ ${#MISSING_HDFS[@]} -gt 0 ]]; then
    for f in "${MISSING_HDFS[@]}"; do ERRORS+=("Hard drive:   ${f}"); done
fi

echo ""
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    warn "Build succeeded but the following required files could not be found"
    warn "anywhere under \$HOME. Place them manually then re-run this script:"
    echo ""
    for e in "${ERRORS[@]}"; do echo "      - ${e}"; done
    echo ""
    echo "  Destination directories:"
    echo "      ROMs:        ${ROM_DIR}/"
    echo "      Hard drives: ${HDF_DIR}/"
    exit 1
fi

echo "==> All done."
echo ""
echo "    Binary:      ${BINARY}"
if [[ "$INSTALL" == true ]]; then
    echo "    Installed:   /usr/bin/amiberry-lite"
    echo "    Data dir:    /usr/share/amiberry-lite/"
fi
echo "    Configs:     ${CONF_DIR}/"
echo "    ROMs:        ${ROM_DIR}/"
echo "    Hard drives: ${HDF_DIR}/"
echo "    Shader:      shader=1084"
echo ""
if [[ "$INSTALL" != true ]]; then
    echo "  To install system-wide:  sudo cmake --install ${BUILD_DIR}"
    echo "  Or re-run with:          ./build.sh --install"
    echo ""
fi
echo "  Launch: amiberry-lite"
