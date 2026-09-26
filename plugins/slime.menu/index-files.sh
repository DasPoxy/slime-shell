#!/usr/bin/env bash
# File index for the Slime launcher's fuzzy file search.
#   index-files.sh [max-age-minutes]   rebuild if older than that (default 10)
# Indexes ~ and mounted drives (/mnt, /run/media), skipping backups, game
# libraries and other bulk that would drown real results, into
# ~/.cache/slime-shell/files.txt (on disk, not RAM). Extra patterns to skip
# can go in ~/.config/omarchy/slime-shell/file-search-ignore (fd --exclude
# globs, one per line).
set -uo pipefail

out="${XDG_CACHE_HOME:-$HOME/.cache}/slime-shell/files.txt"
age="${1:-10}"
mkdir -p "$(dirname "$out")"
if [[ -f $out ]] && [[ -n $(find "$out" -mmin "-$age" 2>/dev/null) ]]; then exit 0; fi

excludes=(.git node_modules .cache __pycache__ .venv .local/share/Steam .steam
  steamapps SteamLibrary compatdata shadercache timeshift snapshots
  .wine pfx prefix 'Vortex Mods' .var/app .cargo/registry .rustup .npm target
  'Games/Heroic' .nv .mozilla .java '/Games' '/games' '/GOG' '/Gog')
extra="$HOME/.config/omarchy/slime-shell/file-search-ignore"
[[ -f $extra ]] && while IFS= read -r line; do [[ -n $line && $line != \#* ]] && excludes+=("$line"); done < "$extra"

args=(--type f --color=never)
for e in "${excludes[@]}"; do args+=(--exclude "$e"); done

tmp="$out.tmp.$$"
{
  nice -n 15 fd "${args[@]}" . "$HOME" 2>/dev/null
  for m in $(findmnt -rn -o TARGET | grep -E '^/(mnt|run/media)(/|$)'); do
    nice -n 15 fd "${args[@]}" . "$m" 2>/dev/null
  done
} > "$tmp"
mv "$tmp" "$out"
