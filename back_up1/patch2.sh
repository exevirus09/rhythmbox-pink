#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$ROOT/build-rhythmbox.sh"

if [[ ! -f "$BUILD_SCRIPT" ]]; then
    echo "[!] build-rhythmbox.sh was not found."
    exit 1
fi

python3 - "$BUILD_SCRIPT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

start = text.find('cat > "$QT_APP" <<')
if start == -1:
    raise SystemExit("[!] Qt GUI block was not found.")

line_end = text.find("\n", start)
delimiter = text[start + len('cat > "$QT_APP" <<'):line_end].strip()

end = text.find(f"\n{delimiter}", line_end)
if end == -1:
    raise SystemExit("[!] End of Qt GUI block was not found.")

gui = text[line_end + 1:end]

old = '''        layout = QHBoxLayout()
        layout.setContentsMargins(3, 3, 3, 3)
        layout.setSpacing(2)

        for item, action in buttons:
            button = item if isinstance(item, QPushButton) else QPushButton(item)
            button.setFixedSize(34, 25)
            button.clicked.connect(action)
            layout.addWidget(button)

        layout.addWidget(self.progress)
        self.setLayout(layout)
'''

new = '''        controls_row = QHBoxLayout()
        controls_row.setContentsMargins(3, 0, 3, 3)
        controls_row.setSpacing(2)

        for item, action in buttons:
            button = item if isinstance(item, QPushButton) else QPushButton(item)
            button.setFixedSize(34, 25)
            button.clicked.connect(action)
            controls_row.addWidget(button)

        layout = QVBoxLayout()
        layout.setContentsMargins(3, 3, 3, 3)
        layout.setSpacing(1)
        layout.addWidget(self.progress)
        layout.addLayout(controls_row)
        self.setLayout(layout)
'''

if old not in gui:
    raise SystemExit(
        "[!] The expected compact GUI layout was not found.\n"
        "[!] Make sure build-rhythmbox.sh contains the current compact GUI."
    )

gui = gui.replace(old, new)
gui = gui.replace(
    'self.setFixedSize(335, 39)',
    'self.setFixedSize(300, 64)',
)

path.write_text(
    text[:line_end + 1]
    + gui
    + text[end:]
)

print("[*] Patch 3 applied.")
PY

chmod +x "$BUILD_SCRIPT"

echo "[*] Rebuilding Rhythmbox with the seekbar stacked above the controls"

exec "$BUILD_SCRIPT"
