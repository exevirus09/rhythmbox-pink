#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/_build"
RB_BIN="$BUILD_DIR/shell/rhythmbox"
GUI="$ROOT/rhythmbox-controls.py"
LOG="/tmp/rhythmbox-player.log"

HIDE_RHYTHMBOX="${HIDE_RHYTHMBOX:-1}"
RB_PLAYER_NAME="${RB_PLAYER_NAME:-}"

echo "[*] Rhythmbox one-file build and compact controls"
echo "[*] Project root: $ROOT"

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

cd "$ROOT"

echo "[*] Configuring Rhythmbox"

rm -rf "$BUILD_DIR"
meson setup "$BUILD_DIR" "$ROOT"

echo "[*] Building Rhythmbox"

meson compile -C "$BUILD_DIR"

if [[ ! -x "$RB_BIN" ]]; then
    echo "[!] Rhythmbox executable was not found:"
    echo "    $RB_BIN"
    exit 1
fi

cat > "$GUI" <<'PYTHON'
#!/usr/bin/env python3

import os
import subprocess
import sys

from PyQt5.QtCore import QTimer, Qt
from PyQt5.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QPushButton,
    QSlider,
    QVBoxLayout,
    QWidget,
)

PLAYER = os.environ.get("RB_PLAYER", "rhythmbox")


def playerctl(*args):
    try:
        result = subprocess.run(
            ["playerctl", f"--player={PLAYER}", *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
            check=False,
        )
        return result.stdout.strip()
    except Exception:
        return ""


def player_command(*args):
    try:
        subprocess.run(
            ["playerctl", f"--player={PLAYER}", *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
    except Exception:
        pass


def to_seconds(value, microseconds=False):
    try:
        value = float(value)
        return value / 1_000_000 if microseconds else value
    except (TypeError, ValueError):
        return 0.0


class Controls(QWidget):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Rhythmbox")
        self.setFixedSize(300, 64)
        self.setWindowFlags(Qt.Window | Qt.WindowStaysOnTopHint)

        self.progress = QSlider(Qt.Horizontal)
        self.progress.setRange(0, 1000)
        self.progress.setFixedHeight(16)
        self.progress.sliderReleased.connect(self.seek)

        self.play_button = QPushButton("▶")

        button_data = [
            ("«", lambda: player_command("previous")),
            (self.play_button, lambda: player_command("play-pause")),
            ("»", lambda: player_command("next")),
            ("■", lambda: player_command("stop")),
            ("−", lambda: player_command("volume", "0.05-")),
            ("+", lambda: player_command("volume", "0.05+")),
            ("M", lambda: player_command("volume", "0")),
        ]

        controls_row = QHBoxLayout()
        controls_row.setContentsMargins(2, 0, 2, 2)
        controls_row.setSpacing(2)

        for item, action in button_data:
            button = item if isinstance(item, QPushButton) else QPushButton(item)
            button.setFixedSize(34, 25)
            button.clicked.connect(action)
            controls_row.addWidget(button)

        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(3, 3, 3, 3)
        main_layout.setSpacing(1)
        main_layout.addWidget(self.progress)
        main_layout.addLayout(controls_row)

        self.setLayout(main_layout)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_display)
        self.timer.start(1000)

        self.update_display()

    def update_display(self):
        title = playerctl("metadata", "--format", "{{title}}")
        artist = playerctl("metadata", "--format", "{{artist}}")
        status = playerctl("status")

        if title and artist:
            self.setWindowTitle(f"{title} — {artist}")
        elif title:
            self.setWindowTitle(title)
        else:
            self.setWindowTitle("Rhythmbox")

        self.play_button.setText("Ⅱ" if status == "Playing" else "▶")

        length = to_seconds(
            playerctl("metadata", "--format", "{{mpris:length}}"),
            microseconds=True,
        )

        position = to_seconds(playerctl("position"))

        if length > 0 and not self.progress.isSliderDown():
            value = int(position / length * 1000)
            self.progress.setValue(max(0, min(1000, value)))

    def seek(self):
        length = to_seconds(
            playerctl("metadata", "--format", "{{mpris:length}}"),
            microseconds=True,
        )

        if length > 0:
            target = length * self.progress.value() / 1000
            player_command("position", str(target))


app = QApplication(sys.argv)
app.setStyle("Fusion")

app.setStyleSheet("""
    QWidget {
        background-color: #000000;
        color: #ff1493;
        font-size: 13px;
    }

    QPushButton {
        background-color: #000000;
        color: #ff1493;
        border: 1px solid #ff1493;
        border-radius: 3px;
        padding: 0;
        font-weight: bold;
    }

    QPushButton:hover {
        background-color: #ff1493;
        color: #000000;
    }

    QPushButton:pressed {
        background-color: #ff69b4;
        color: #000000;
    }

    QSlider::groove:horizontal {
        height: 4px;
        background: #4d0030;
        border-radius: 2px;
    }

    QSlider::sub-page:horizontal {
        background: #ff1493;
        border-radius: 2px;
    }

    QSlider::handle:horizontal {
        width: 10px;
        margin: -3px 0;
        background: #ff1493;
        border-radius: 5px;
    }
""")

window = Controls()
window.show()
window.raise_()
window.activateWindow()

sys.exit(app.exec_())
PYTHON

chmod +x "$GUI"

echo "[*] Starting Rhythmbox"

: > "$LOG"

"$RB_BIN" >"$LOG" 2>&1 &
RB_PID=$!

cleanup() {
    echo
    echo "[*] Closing Rhythmbox"

    if kill -0 "$RB_PID" 2>/dev/null; then
        kill "$RB_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

for attempt in {1..15}; do
    if kill -0 "$RB_PID" 2>/dev/null; then
        break
    fi
    sleep 1
done

if ! kill -0 "$RB_PID" 2>/dev/null; then
    echo "[!] Rhythmbox stopped unexpectedly."
    cat "$LOG" 2>/dev/null || true
    exit 1
fi

if [[ "$HIDE_RHYTHMBOX" == "1" ]]; then
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

echo "[*] Waiting for the Rhythmbox MPRIS player"

RB_PLAYER=""

if [[ -n "$RB_PLAYER_NAME" ]]; then
    RB_PLAYER="$RB_PLAYER_NAME"
else
    for attempt in {1..30}; do
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

export RB_PLAYER

echo "[*] Using MPRIS player: $RB_PLAYER"
echo "[*] Starting GUI"
echo "[*] The seekbar is stacked above the controls."
echo "[*] To restart later, close this window and run:"
echo "    ./patch2.sh"

python3 -u "$GUI"
