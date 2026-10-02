#!/bin/bash
# Lance l'interface (macOS / Linux).
cd "$(dirname "$0")" || exit 1
command -v ffmpeg >/dev/null || { echo "ffmpeg introuvable : brew install ffmpeg (macOS) ou sudo apt install ffmpeg"; exit 1; }
python3 -m pip install --quiet --disable-pip-version-check -r requirements.txt || exit 1
exec python3 interface.py
