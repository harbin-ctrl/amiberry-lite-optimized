#!/usr/bin/env bash
# Decrypt Cloanto Amiga Forever ROMs using rom.key.
# Format: 11-byte "AMIROMTYPE1" header, then XOR-encrypted ROM data.
# Key cycles through rom.key for the full length of the ROM.

set -euo pipefail

SRC_DIR="$HOME/Downloads/Shared/rom"
DST_DIR="$HOME/Amiberry-Lite/roms"
KEY="$SRC_DIR/rom.key"

ok()   { echo "    [OK]     $*"; }
info() { echo "==> $*"; }

ROMS=(
    "amiga-os-130.rom"
    "amiga-os-310-a1200.rom"
    "amiga-os-204-a3000.rom"
)

info "Decrypting Amiga Forever ROMs..."
info "Key: $KEY ($(wc -c < "$KEY") bytes)"
echo ""

python3 - "$KEY" "$SRC_DIR" "$DST_DIR" "${ROMS[@]}" <<'PYEOF'
import sys, os

key_path  = sys.argv[1]
src_dir   = sys.argv[2]
dst_dir   = sys.argv[3]
rom_names = sys.argv[4:]

HEADER = b'AMIROMTYPE1'

with open(key_path, 'rb') as f:
    key = f.read()

for name in rom_names:
    src = os.path.join(src_dir, name)
    dst = os.path.join(dst_dir, name)

    with open(src, 'rb') as f:
        data = f.read()

    if data[:11] != HEADER:
        print(f"    [SKIP]   {name} — not AMIROMTYPE1 (already decrypted?)")
        continue

    encrypted = data[11:]
    decrypted = bytes(b ^ key[i % len(key)] for i, b in enumerate(encrypted))

    with open(dst, 'wb') as f:
        f.write(decrypted)

    print(f"    [OK]     {name} — {len(decrypted)} bytes -> {dst}")
PYEOF

echo ""
info "Done."
