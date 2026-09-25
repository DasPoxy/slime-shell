#!/usr/bin/env bash
# Stop the slime spike. The Omarchy shell is left running.
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
qs kill -p "$dir"
