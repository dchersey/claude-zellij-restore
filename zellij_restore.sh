#!/usr/bin/env bash
# zellij_restore.sh — restore a zellij session from its clauding-snapshot layout.
#
# Finds the latest ~/tmp/clauding-restore-<session>.kdl (written by clauding-snapshot
# — e.g. via the claude-watch auto-snapshot hook), derives the session name from the
# filename, removes the old session, and relaunches zellij with the saved layout under
# the same name. Run from a PLAIN terminal — OUTSIDE zellij (detach first: Ctrl-q).
set -uo pipefail

usage() {
  cat <<'EOF'
zellij_restore.sh — restore a zellij session from its clauding-snapshot layout.
Run from OUTSIDE zellij (detach first: Ctrl-q).

  zellij_restore.sh                 restore the most recent snapshot
  zellij_restore.sh <session>       restore a specific session's snapshot
  zellij_restore.sh -y              skip the confirmation prompt
  zellij_restore.sh --run-all       also auto-run non-claude command panes

--run-all / --suspend / --keep-swap-layouts / --no-stealth are passed through to
`clauding-snapshot --from` to re-shape the saved layout before launching — so the
default snapshot (command panes left suspended) can be restored with them running
(or vice-versa). CLAUDING_RESTORE_DIR overrides the snapshot dir (default ~/tmp).
EOF
}

dir="${CLAUDING_RESTORE_DIR:-$HOME/tmp}"
yes=0
want=""
xform=() # clauding-snapshot transform flags applied to the layout before launch

while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) yes=1 ;;
    --run-all | --suspend | --keep-swap-layouts | --no-stealth) xform+=("$1") ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    *) want="$1" ;;
  esac
  shift
done

# Must be OUTSIDE zellij — we can't kill + relaunch the session from within it.
if [ -n "${ZELLIJ:-}" ]; then
  echo "You're inside zellij. Detach first (Ctrl-q), then run this from a plain terminal." >&2
  exit 1
fi
command -v zellij >/dev/null 2>&1 || { echo "zellij not found on PATH." >&2; exit 1; }

# Pick the snapshot: a named session, else the most recently modified.
if [ -n "$want" ]; then
  file="$dir/clauding-restore-$want.kdl"
  [ -f "$file" ] || { echo "No snapshot for '$want' at $file" >&2; exit 1; }
else
  file="$(ls -t "$dir"/clauding-restore-*.kdl 2>/dev/null | head -1)"
  [ -n "$file" ] || { echo "No snapshots found in $dir (clauding-restore-*.kdl)" >&2; exit 1; }
fi

# Session name = the filename between 'clauding-restore-' and '.kdl'.
base="$(basename "$file" .kdl)"
session="${base#clauding-restore-}"

panes="$(grep -c 'claude-resume' "$file" 2>/dev/null || true)"; panes="${panes:-0}"
saved="$(stat -f '%Sm' "$file" 2>/dev/null || stat -c '%y' "$file" 2>/dev/null || echo '?')"
echo "Restore session '$session'"
echo "  layout: $file"
echo "  saved:  $saved   (${panes} claude pane(s))"
[ ${#xform[@]} -gt 0 ] && echo "  shape:  ${xform[*]}"

if [ "$yes" -ne 1 ]; then
  printf "Remove session '%s' and relaunch from this layout? [y/N] " "$session"
  read -r ans || ans=n
  case "$ans" in y | Y | yes | YES) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# Optionally re-shape the saved layout (e.g. --run-all to un-suspend command panes)
# by re-running it through clauding-snapshot's file-rewrite mode (which keeps its
# MCP-pane safety). Falls back to the saved layout as-is if it can't run.
launch="$file"
if [ ${#xform[@]} -gt 0 ]; then
  self="$0"; [ -L "$self" ] && self="$(readlink "$self")"
  cs="$(command -v clauding-snapshot 2>/dev/null || echo "$(cd "$(dirname "$self")" && pwd)/clauding-snapshot")"
  tmp="${TMPDIR:-/tmp}/zellij-restore-$session.kdl"
  if [ -x "$cs" ] && "$cs" --from "$file" "${xform[@]}" -o "$tmp" >/dev/null 2>&1; then
    launch="$tmp"
  else
    echo "warning: couldn't apply '${xform[*]}' via clauding-snapshot; using the saved layout as-is" >&2
  fi
fi

# Remove the old session: --force kills it if running AND clears the resurrectable
# entry, so the relaunch builds fresh from our layout instead of resurrecting it.
zellij delete-session --force "$session" 2>/dev/null || true

# Relaunch under the same name with the (possibly re-shaped) layout (replaces this process).
exec zellij --session "$session" --layout "$launch"
