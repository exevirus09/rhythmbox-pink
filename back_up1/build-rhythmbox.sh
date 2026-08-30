#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/_build"
PATCH_FILE="$ROOT/patches.sh"
RB_BIN="$BUILD_DIR/src/rhythmbox"

echo "[*] Rhythmbox patched build + launch"
echo "[*] Project root: $ROOT"

cd "$ROOT"

if [[ ! -f "$PATCH_FILE" ]]; then
    PATCH_FILE="$(find "$ROOT" -maxdepth 2 -type f -name 'patches.sh' -print -quit)"

    if [[ -z "$PATCH_FILE" ]]; then
        echo "[!] patches.sh was not found."
        echo "[!] Put patches.sh in: $ROOT"
        exit 1
    fi
fi

echo "[*] Applying patches from: $PATCH_FILE"
bash "$PATCH_FILE"

if [[ -d "$BUILD_DIR" ]]; then
    echo "[*] Removing old build directory"

    if [[ -w "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    else
        sudo rm -rf "$BUILD_DIR"
    fi
fi

echo "[*] Configuring Meson"
meson setup "$BUILD_DIR" "$ROOT"

echo "[*] Building Rhythmbox"
meson compile -C "$BUILD_DIR"

if [[ -x "$RB_BIN" ]]; then
    echo "[*] Launching patched Rhythmbox"
    exec "$RB_BIN"
else
    echo "[!] Rhythmbox binary not found: $RB_BIN"
    exit 1
fi
