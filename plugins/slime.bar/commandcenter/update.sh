#!/usr/bin/env bash
# Slime Shell self-update, for the Settings > Updates section.
#   update.sh check   fetch, print JSON {status, branch, behind, ahead, dirty, local, remote, log[]}
#   update.sh pull    fast-forward to the remote (refuses on local changes / divergence)
# The repo is the checkout the plugins were copied from (slime.bar/.synced-from
# names it); after pulling, the plugins are copied in again.
set -uo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
plugin="$(dirname "$here")"
src="$plugin"
[[ -f $plugin/.synced-from ]] && src="$(head -1 "$plugin/.synced-from")"
repo="$(git -C "$src" rev-parse --show-toplevel 2>/dev/null)" || {
  echo '{"status":"error","message":"not a git checkout"}'; exit 0; }
cd "$repo" || exit 0

json_err() { jq -cn --arg m "$1" '{status:"error", message:$m}'; exit 0; }

case "${1:-check}" in
  check)
    git fetch --quiet 2>/dev/null || json_err "couldn't reach the remote"
    upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null) || json_err "branch has no upstream"
    read -r ahead behind < <(git rev-list --left-right --count "HEAD...$upstream")
    dirty=$([[ -n $(git status --porcelain) ]] && echo true || echo false)
    log=$(git log --format='%s' "HEAD..$upstream" | head -8 | jq -R . | jq -cs .)
    status="current"
    (( behind > 0 )) && status="behind"
    (( ahead > 0 && behind > 0 )) && status="diverged"
    jq -cn --arg s "$status" --arg b "$(git rev-parse --abbrev-ref HEAD)" --argjson behind "$behind" \
      --argjson ahead "$ahead" --argjson dirty "$dirty" --arg l "$(git rev-parse --short HEAD)" \
      --arg r "$(git rev-parse --short "$upstream")" --argjson log "$log" \
      '{status:$s, branch:$b, behind:$behind, ahead:$ahead, dirty:$dirty, local:$l, remote:$r, log:$log}'
    ;;
  pull)
    [[ -z $(git status --porcelain) ]] || json_err "local changes; commit or stash them first"
    git merge --ff-only --quiet '@{u}' 2>/dev/null || json_err "can't fast-forward (branches diverged)"
    # the running copies in ~/.config/omarchy/plugins
    [[ -x $repo/bin/slime-shell ]] && "$repo/bin/slime-shell" sync >/dev/null 2>&1
    jq -cn --arg l "$(git rev-parse --short HEAD)" '{status:"updated", local:$l}'
    ;;
esac
