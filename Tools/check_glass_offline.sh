#!/bin/sh
# Offline contracts only; no network, build, simulator, or hardware access.
set -eu
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Reference -p 'test_*.py'
python3 Tools/validate_project.py
