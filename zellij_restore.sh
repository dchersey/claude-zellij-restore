#!/usr/bin/env bash
# zellij_restore.sh — restore a zellij session from its clauding-snapshot layout.
#
# Finds the latest ~/tmp/clauding-restore-<session>.kdl (written by clauding-snapshot
# — e.g. via the claude-watch auto-snapshot hook), derives the session name from the
# filename, removes the old session, and relaunches zellij with the saved layout under
# the same name.
#
# Run from a PLAIN terminal — OUTSIDE zellij (detach first: Ctrl-q).
#
#   zellij_restore.sh             restore the most recent snapshot
#   zellij_restore.sh <session>   restore a specific session's snapshot
#   zellij_restore.sh -y [...]    skip the confirmation prompt
#
# Override the snapshot directory with CLAUDING_RESTORE_DIR (default ~/tmp).
set -uo pipefail

dir="${CLAUDING_RESTORE_DIR:-$HOME/tmp}"

yes=0
if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]; then yes=1; shift; fi
want="${1:-}"

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

if [ "$yes" -ne 1 ]; then
  printf "Remove session '%s' and relaunch from this layout? [y/N] " "$session"
  read -r ans || ans=n
  case "$ans" in y | Y | yes | YES) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# Remove the old session: --force kills it if running AND clears the resurrectable
# entry, so the relaunch builds fresh from our layout instead of resurrecting the
# old serialized session.
zellij delete-session --force "$session" 2>/dev/null || true

# Relaunch under the same name with the saved layout (replaces this process).
exec zellij --session "$session" --layout "$file"
