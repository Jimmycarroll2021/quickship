#!/usr/bin/env bash
set -u
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
exec "$PY" "$(dirname "$0")/quality.py"
