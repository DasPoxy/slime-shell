#!/usr/bin/env bash
# Compile the shader and start the slime spike alongside the Omarchy shell.
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
/usr/lib/qt6/bin/qsb --qt6 -o "$dir/shaders/slime.frag.qsb" "$dir/shaders/slime.frag"
exec qs -p "$dir" "$@"
