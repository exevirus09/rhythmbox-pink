#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/_build"
RB_BIN="$BUILD_DIR/shell/rhythmbox"
QT_APP="$ROOT/rhythmbox-controls.py"
RB_LOG="/tmp/rhythmbox-player.log"

HIDE_RHYTHMBOX="${HIDE_RHYTHMBOX:-1}"
RB_PLAYER_NAME="${RB_PLAYER_NAME:-}"

echo "[*] Rhythmbox build and compact pink Qt controls"
echo "[*] Source directory: $ROOT"

if [[ "$EUID" -eq 0 ]]; then
    echo "[!] Do not run this script as root."
    exit 1
fi

cd "$ROOT"

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "[!] No graphical display was detected."
    echo "[!] Run this script from inside your desktop session."
    exit 1
fi

if ! command -v meson >/dev/null 2>&1; then
    echo "[!] Meson is not installed."
    echo "    sudo dnf install meson"
    exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
    echo "[!] Ninja is not installed."
    echo "    sudo dnf install ninja-build"
    exit 1
fi

if ! command -v playerctl >/dev/null 2>&1; then
    echo "[!] playerctl is not installed."
    echo "    sudo dnf install playerctl"
    exit 1
fi

if ! command -v wmctrl >/dev/null 2>&1; then
    echo "[!] wmctrl is not installed."
    echo "    sudo dnf install wmctrl"
    exit 1
fi

if ! python3 -c 'import PyQt5' >/dev/null 2>&1; then
    echo "[!] PyQt5 is not installed."
    echo "    sudo dnf install python3-qt5"
    exit 1
fi

echo "[*] Removing old build"

if [[ -d "$BUILD_DIR" ]]; then
    rm -rf "$BUILD_DIR"
fi

echo "[*] Configuring Rhythmbox"

meson setup "$BUILD_DIR" "$ROOT"

echo "[*] Building Rhythmbox"

meson compile -C "$BUILD_DIR"

if [[ ! -x "$RB_BIN" ]]; then
    echo "[!] Rhythmbox executable was not found:"
    echo "    $RB_BIN"
    echo
    echo "[!] Matching executables:"
    find "$BUILD_DIR" -type f -executable -iname '*rhythmbox*' -print
    exit 1
fi

cat > "$QT_APP" <<'PYTHON'
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


def playerctl(*arguments):
    command = [
        "playerctl",
        f"--player={PLAYER}",
        *arguments,
    ]

    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
            check=False,
        )
        return result.stdout.strip()
    except Exception:
        return ""


def player_command(*arguments):
    command = [
        "playerctl",
        f"--player={PLAYER}",
        *arguments,
    ]

    try:
        subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
    except Exception:
        pass


def to_seconds(value, microseconds=False):
    try:
        number = float(value)

        if microseconds:
            number /= 1_000_000

        return number
    except (TypeError, ValueError):
        return 0.0


class RhythmboxControls(QWidget):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Rhythmbox")
        self.setFixedSize(300, 94)

        self.setWindowFlags(
            Qt.Window |
            Qt.WindowStaysOnTopHint
        )

        self.progress = QSlider(Qt.Horizontal)
        self.progress.setRange(0, 1000)
        self.progress.setFixedHeight(15)
        self.progress.sliderReleased.connect(self.seek)

        previous_button = self.make_button("«")
        self.play_button = self.make_button("▶")
        next_button = self.make_button("»")
        stop_button = self.make_button("■")

        volume_down_button = self.make_button("−")
        volume_up_button = self.make_button("+")
        mute_button = self.make_button("M")

        previous_button.clicked.connect(
            lambda: player_command("previous")
        )

        self.play_button.clicked.connect(
            lambda: player_command("play-pause")
        )

        next_button.clicked.connect(
            lambda: player_command("next")
        )

        stop_button.clicked.connect(
            lambda: player_command("stop")
        )

        volume_down_button.clicked.connect(
            lambda: player_command("volume", "0.05-")
        )

        volume_up_button.clicked.connect(
            lambda: player_command("volume", "0.05+")
        )

        mute_button.clicked.connect(
            lambda: player_command("volume", "0")
        )

        playback_layout = QHBoxLayout()
        playback_layout.setSpacing(3)

        for button in (
            previous_button,
            self.play_button,
            next_button,
            stop_button,
        ):
            playback_layout.addWidget(button)

        volume_layout = QHBoxLayout()
        volume_layout.setSpacing(3)

        for button in (
            volume_down_button,
            volume_up_button,
            mute_button,
        ):
            volume_layout.addWidget(button)

        layout = QVBoxLayout()
        layout.setContentsMargins(6, 5, 6, 5)
        layout.setSpacing(3)
        layout.addWidget(self.progress)
        layout.addLayout(playback_layout)
        layout.addLayout(volume_layout)

        self.setLayout(layout)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_display)
        self.timer.start(1000)

        self.update_display()

    @staticmethod
    def make_button(text):
        button = QPushButton(text)
        button.setFixedSize(35, 25)
        return button

    def update_display(self):
        title = playerctl(
            "metadata",
            "--format",
            "{{title}}",
        )

        artist = playerctl(
            "metadata",
            "--format",
            "{{artist}}",
        )

        status = playerctl("status")

        length = playerctl(
            "metadata",
            "--format",
            "{{mpris:length}}",
        )

        position = playerctl("position")

        if title and artist:
            self.setWindowTitle(f"{title} — {artist}")
        elif title:
            self.setWindowTitle(title)
        else:
            self.setWindowTitle("Rhythmbox")

        self.play_button.setText(
            "Ⅱ" if status == "Playing" else "▶"
        )

        length_seconds = to_seconds(
            length,
            microseconds=True,
        )

        position_seconds = to_seconds(position)

        if length_seconds > 0:
            slider_value = int(
                position_seconds /
                length_seconds *
                1000
            )

            slider_value = max(
                0,
                min(1000, slider_value),
            )

            if not self.progress.isSliderDown():
                self.progress.setValue(slider_value)
        else:
            self.progress.setValue(0)

    def seek(self):
        length = playerctl(
            "metadata",
            "--format",
            "{{mpris:length}}",
        )

        length_seconds = to_seconds(
            length,
            microseconds=True,
        )

        if length_seconds <= 0:
            return

        target_seconds = (
            length_seconds *
            self.progress.value() /
            1000
        )

        player_command(
            "position",
            str(target_seconds),
        )


def main():
    application = QApplication(sys.argv)
    application.setStyle("Fusion")

    application.setStyleSheet(
        """
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
            padding: 1px;
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
            width: 11px;
            margin: -4px 0;
            background: #ff1493;
            border: 1px solid #ff69b4;
            border-radius: 6px;
        }
        """
    )

    window = RhythmboxControls()
    window.show()
    window.raise_()
    window.activateWindow()

    return application.exec_()


if __name__ == "__main__":
    sys.exit(main())
PYTHON

chmod +x "$QT_APP"

echo "[*] Starting Rhythmbox"

: > "$RB_LOG"

"$RB_BIN" >"$RB_LOG" 2>&1 &
RB_PID=$!

cleanup() {
    echo
    echo "[*] Closing Rhythmbox"

    if kill -0 "$RB_PID" 2>/dev/null; then
        kill "$RB_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

echo "[*] Waiting for Rhythmbox process"

RB_RUNNING=0

for attempt in {1..15}; do
    if kill -0 "$RB_PID" 2>/dev/null; then
        RB_RUNNING=1
        break
    fi

    sleep 1
done

if [[ "$RB_RUNNING" -ne 1 ]]; then
    echo "[!] Rhythmbox exited before starting."
    echo
    echo "[!] Rhythmbox log:"
    cat "$RB_LOG" 2>/dev/null || true
    exit 1
fi

echo "[*] Rhythmbox process is running with PID $RB_PID"

if [[ "$HIDE_RHYTHMBOX" == "1" ]]; then
    echo "[*] Waiting for the Rhythmbox window"

    WINDOW_ID=""

    for attempt in {1..30}; do
        WINDOW_ID="$(
            wmctrl -l 2>/dev/null |
            grep -i 'rhythmbox' |
            awk 'NR == 1 { print $1 }' ||
            true
        )"

        if [[ -n "$WINDOW_ID" ]]; then
            break
        fi

        sleep 1
    done

    if [[ -n "$WINDOW_ID" ]]; then
        echo "[*] Hiding Rhythmbox window: $WINDOW_ID"
        wmctrl -i -r "$WINDOW_ID" -b add,hidden || true
    else
        echo "[!] Rhythmbox window was not detected."
        echo "[!] Rhythmbox may be running under Wayland."
    fi
else
    echo "[*] Rhythmbox window will remain visible."
fi

echo "[*] Waiting for Rhythmbox MPRIS player"

RB_PLAYER=""

if [[ -n "$RB_PLAYER_NAME" ]]; then
    RB_PLAYER="$RB_PLAYER_NAME"
else
    for attempt in {1..30}; do
        RB_PLAYER="$(
            playerctl -l 2>/dev/null |
            grep -i 'rhythmbox' |
            head -n 1 ||
            true
        )"

        if [[ -n "$RB_PLAYER" ]]; then
            break
        fi

        sleep 1
    done
fi

echo "[*] Available MPRIS players:"
playerctl -l 2>/dev/null || true

if [[ -z "$RB_PLAYER" ]]; then
    echo "[!] Rhythmbox MPRIS player was not found."
    echo
    echo "[!] Rhythmbox log:"
    cat "$RB_LOG" 2>/dev/null || true
    echo
    echo "[!] The Qt controls cannot control Rhythmbox without MPRIS."
    exit 1
fi

export RB_PLAYER

echo "[*] Using MPRIS player: $RB_PLAYER"
echo "[*] Starting compact pink Qt controls"
echo "[*] Qt controls file: $QT_APP"

python3 -u "$QT_APP"

QT_EXIT_CODE=$?

echo "[!] Qt controls exited with status $QT_EXIT_CODE"

exit "$QT_EXIT_CODE"
