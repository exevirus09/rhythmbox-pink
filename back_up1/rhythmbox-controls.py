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
