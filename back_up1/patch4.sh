#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/_build-patch3"
INSTALL_DIR="$ROOT/_install"
RB_BIN="$INSTALL_DIR/bin/rhythmbox"
GUI="$ROOT/rhythmbox-controls.py"
LOG="/tmp/rhythmbox-player.log"

HIDE_RHYTHMBOX="${HIDE_RHYTHMBOX:-1}"
RB_PLAYER_NAME="${RB_PLAYER_NAME:-}"

echo "[*] Rhythmbox patch3 build, install, and compact controls"
echo "[*] Project root: $ROOT"
echo "[*] Install directory: $INSTALL_DIR"

if [[ "$EUID" -eq 0 ]]; then
    echo "[!] Do not run this script as root."
    exit 1
fi

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "[!] No graphical display detected."
    exit 1
fi

missing=()

for program in meson ninja playerctl wmctrl python3; do
    command -v "$program" >/dev/null 2>&1 || missing+=("$program")
done

if ! python3 -c 'import PyQt5' >/dev/null 2>&1; then
    missing+=("python3-pyqt5")
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "[!] Missing software: ${missing[*]}"
    echo
    echo "Install it with:"
    echo "sudo apt update && sudo apt install meson ninja-build playerctl wmctrl python3-pyqt5"
    exit 1
fi

if [[ ! -f "$GUI" ]]; then
    echo "[!] GUI file was not found:"
    echo "    $GUI"
    exit 1
fi

cd "$ROOT"

echo "[*] Removing previous patch3 build and installation"

rm -rf "$BUILD_DIR"
rm -rf "$INSTALL_DIR"

echo "[*] Configuring Rhythmbox"

meson setup \
    "$BUILD_DIR" \
    "$ROOT" \
    --prefix="$INSTALL_DIR"

echo "[*] Building Rhythmbox"

meson compile -C "$BUILD_DIR"

echo "[*] Installing Rhythmbox into $INSTALL_DIR"

meson install -C "$BUILD_DIR"

if [[ ! -x "$RB_BIN" ]]; then
    echo "[!] Rhythmbox executable was not found:"
    echo "    $RB_BIN"
    echo
    echo "Installed files:"
    find "$INSTALL_DIR" -type f -perm -111 2>/dev/null || true
    exit 1
fi

echo "[*] Starting installed Rhythmbox"

: > "$LOG"

"$RB_BIN" >"$LOG" 2>&1 &
RB_PID=$!

cleanup() {
    echo
    echo "[*] Closing Rhythmbox"

    if kill -0 "$RB_PID" 2>/dev/null; then
        kill "$RB_PID" 2>/dev/null || true
    fi

    wait "$RB_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

echo "[*] Waiting for Rhythmbox MPRIS player"

RB_PLAYER=""

if [[ -n "$RB_PLAYER_NAME" ]]; then
    RB_PLAYER="$RB_PLAYER_NAME"
else
    for attempt in {1..30}; do
        if ! kill -0 "$RB_PID" 2>/dev/null; then
            echo "[!] Rhythmbox stopped unexpectedly."
            cat "$LOG" 2>/dev/null || true
            exit 1
        fi

        RB_PLAYER="$(
            playerctl -l 2>/dev/null |
            grep -i rhythmbox |
            head -n 1 ||
            true
        )"

        if [[ -n "$RB_PLAYER" ]]; then
            break
        fi

        sleep 1
    done
fi

if [[ -z "$RB_PLAYER" ]]; then
    echo "[!] Rhythmbox MPRIS player was not found."
    cat "$LOG" 2>/dev/null || true
    exit 1
fi

if [[ "$HIDE_RHYTHMBOX" == "1" ]]; then
    echo "[*] Hiding the main Rhythmbox window"

    for attempt in {1..30}; do
        WINDOW_ID="$(
            wmctrl -l 2>/dev/null |
            grep -i rhythmbox |
            awk 'NR == 1 { print $1 }' ||
            true
        )"

        if [[ -n "$WINDOW_ID" ]]; then
            wmctrl -i -r "$WINDOW_ID" -b add,hidden || true
            break
        fi

        sleep 1
    done
fi

export RB_PLAYER

echo "[*] Using MPRIS player: $RB_PLAYER"
echo "[*] Starting GUI"
echo "[*] Installed program: $RB_BIN"

python3 -u "$GUI"
