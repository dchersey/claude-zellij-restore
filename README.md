# claude-resume + clauding-snapshot

[![CI](https://github.com/dchersey/claude-zellij-restore/actions/workflows/ci.yml/badge.svg)](https://github.com/dchersey/claude-zellij-restore/actions/workflows/ci.yml)
[![License: Source Available](https://img.shields.io/badge/license-Source%20Available%20(MIT%20%2B%20Commons%20Clause)-blue.svg)](LICENSE)

Restore a whole screenful of [Claude Code](https://docs.claude.com/en/docs/claude-code) sessions — exactly where you left them — after a reboot, inside a [Zellij](https://zellij.dev) layout.

If you run many parallel Claude Code sessions across git worktrees (often several in the *same* folder), `claude --continue` can't help you: it only knows "most recent in this directory," so it can't tell your six sessions apart, and a reboot scatters all of them. These two scripts fix that. One resumes a session by its real id; the other photographs your live Zellij session into a layout file that brings every pane back, resumed, with no keystrokes.

---

## Quick start

```sh
# install (anywhere on your PATH)
cp claude-resume clauding-snapshot zellij_restore ~/bin/
chmod +x ~/bin/claude-resume ~/bin/clauding-snapshot ~/bin/zellij_restore

# cold start your standard layout
zellij --layout clauding.kdl

# ...work across many sessions...

# right before you reboot, photograph the live session:
clauding-snapshot
# -> prints:  zellij --layout "/Users/you/tmp/clauding-restore.kdl"

# after reboot, paste that command. every pane comes back resumed.
```

---

## What's in here

| File | What it is |
|------|------------|
| `claude-resume` | Resume one Claude Code session for a directory — by picker, by latest, or by exact id. Bakes your launch line in one place. |
| `clauding-snapshot` | Capture the current Zellij session into a `*.kdl` layout that restores every Claude pane to its session. |
| `zellij_restore` | Restore from the latest `clauding-restore-<session>.kdl`: derive the session name, remove the old session, relaunch with the saved layout under the same name. |
| `clauding.kdl` | A cold-start Zellij layout whose Claude panes call `claude-resume` (edit to match your own arrangement). |
| `clauding-resume.example.kdl` | A sample of what `clauding-snapshot` emits, with placeholder session ids. |

## Requirements

- **bash** — works on the ancient bash 3.2 that ships with macOS (no `mapfile`/`readarray` used).
- **[jq](https://jqlang.github.io/jq/)** — reads session metadata from the transcripts.
- **[fzf](https://github.com/junegunn/fzf)** — only needed for the interactive picker; the `--id` and `--latest` paths don't use it.
- **python3** — used by `clauding-snapshot` to rewrite the layout.
- **[zellij](https://zellij.dev)** — the terminal multiplexer.
- **Claude Code** — the `claude` binary on your PATH.

`clauding-snapshot` looks for `claude-resume` on your PATH, then falls back to `~/bin/claude-resume`.

---

## `claude-resume`

Resume a Claude Code session for a directory, applying your standard launch line (LSP tool + skip-permissions) from a single place.

```
claude-resume              pick a session for $PWD (auto-resumes if there's only one)
claude-resume --latest     resume the most-recently-active session, no picker
claude-resume --pick       always show the picker
claude-resume --id <ID>    resume one exact session id (used by generated layouts)
claude-resume --list       print the candidate table and exit
claude-resume --dir <DIR>  operate on DIR instead of $PWD
```

Sessions are read from `~/.claude/projects/<encoded-cwd>/<id>.jsonl` (honoring `$CLAUDE_CONFIG_DIR`). The picker lists candidates keyed by **last activity**, **git branch**, and **first prompt**, so you can recognize a session without ever having named it — and it works after a crash.

When you resume by id, `claude-resume` reads the session's own recorded `cwd` and `cd`s there before launching, so a pane started in the wrong directory still lands in the right project.

If there are no sessions for the target directory, it simply starts a fresh `claude`.

### The launch line lives in one place

Edit the top of the script to match how you start Claude Code:

```sh
: "${CLAUDE_BIN:=claude}"                          # overridable via $CLAUDE_BIN
CLAUDE_ENV=( ENABLE_LSP_TOOL=1 )                    # singular — the real flag
CLAUDE_FLAGS=( --dangerously-skip-permissions )     # your standard flags
```

> **Note:** the environment flag is `ENABLE_LSP_TOOL` (singular), added in Claude Code 2.0.74. The plural `ENABLE_LSP_TOOLS` is a no-op. Drop these if you don't use the LSP tool.

### Dry run

```sh
CLAUDE_RESUME_DRYRUN=1 claude-resume --id <ID>
# prints the exact command it would exec, without running it
```

---

## `clauding-snapshot`

Photograph the current Zellij session into a resume layout. It runs `zellij action dump-layout`, then rewrites every live `command="claude"` pane into a `claude-resume --id <id>` pane — resolving each id from the most-recently-active transcript in that pane's `cwd`. Everything else (geometry, plugin/status panes, floating panes, swap layouts, and any non-Claude command panes) passes through **byte-for-byte**.

```
clauding-snapshot                 dump current session -> ~/tmp/clauding-restore.kdl
clauding-snapshot -o FILE         choose the output path
clauding-snapshot --from DUMP     rewrite an existing dump file (no zellij call)
clauding-snapshot --suspend       keep panes start_suspended (press Enter to resume each)
```

It creates the output directory if needed, prints a per-directory summary of which session each pane was bound to, and ends with the exact restore command:

```
clauding-snapshot: wrote /Users/you/tmp/clauding-restore.kdl

To restore after reboot, run:
    zellij --layout "/Users/you/tmp/clauding-restore.kdl"
```

Or let **`zellij_restore`** do it — it finds the latest
`clauding-restore-<session>.kdl`, removes the old session, and relaunches under the
same name. Run it from a plain terminal, outside zellij (detach first with `Ctrl-q`):

```sh
zellij_restore             # the most recent snapshot
zellij_restore <session>   # a specific session
zellij_restore --run-all   # also auto-run command panes, not just claude
```

`--run-all` (plus `--suspend` / `--keep-swap-layouts` / `--no-stealth`) is passed
through to `clauding-snapshot --from`, which re-shapes the saved layout before launch
— so a snapshot taken with command panes suspended can be restored with them running.

This pairs with per-session snapshots like `clauding-snapshot -o ~/tmp/clauding-restore-$ZELLIJ_SESSION_NAME.kdl` (e.g. the [claude-watch](https://github.com/dchersey/claude-code-notify-watch) auto-snapshot hook), so each session restores independently.

---

## The reboot workflow

1. **Cold start.** `zellij --layout clauding.kdl` opens your standard arrangement. Each Claude pane runs `claude-resume`, which auto-resumes the lone session in its folder or shows the picker when there's more than one.
2. **Work** across as many parallel sessions and worktrees as you like.
3. **Snapshot last.** Right before rebooting, run `clauding-snapshot` as the *final* thing you do, so it captures the true final state from the live `dump-layout`. Copy the printed `zellij --layout ...` command.
4. **Reboot.**
5. **Restore.** Paste the command. Every pane returns resumed to its exact session — no Enter required (unless you used `--suspend`).

---

## How it works

- **Session discovery.** Claude Code stores each session as `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, where `encoded-cwd` is the absolute path with every non-alphanumeric character replaced by `-`. Each line of the transcript carries `sessionId`, `cwd`, `gitBranch`, and timestamps, which is everything the picker and the cwd self-correction need.
- **Pane → session binding.** `clauding-snapshot` can't read a pane's internal session id from a layout dump, so it reconstructs the binding from disk: for each folder, it takes the *N* most-recently-modified transcripts, newest first, and assigns them to that folder's Claude panes in order.
- **The rewrite is surgical.** Only exact `command="claude"` panes are touched (never `claude-resume`); the generated layout points each at an absolute path to `claude-resume` with `args "--id" "<id>"`. Everything else is copied verbatim.

---

## Caveats

- **Single-owner sessions.** You generally can't resume a session that's currently live in another window — Claude Code sessions have a single owner. This toolset is for *post-reboot* restoration, not for cloning a running session into a second pane.
- **The binding is a heuristic.** Because pane→session mapping is reconstructed by transcript modification time, a pane can occasionally resolve to the wrong session. Fix it in place with `claude-resume --pick` in that pane, or edit the `--id` in the generated layout.
- **More panes than transcripts.** If a folder has more Claude panes than it has transcripts, the surplus panes fall back to `args "--pick"` instead of an id.
- **Run it inside the session.** `clauding-snapshot` calls `zellij action dump-layout`, so run it from within the Zellij session you want to capture. Use `--from <dump>` to rewrite a previously saved dump offline.

---

## Configuration reference

| Variable | Used by | Effect |
|----------|---------|--------|
| `CLAUDE_BIN` | `claude-resume` | The Claude Code binary (default `claude`). |
| `CLAUDE_CONFIG_DIR` | both | Root of the Claude config; sessions are read from `$CLAUDE_CONFIG_DIR/projects` (default `~/.claude`). |
| `CLAUDE_RESUME_BIN` | `clauding-snapshot` | Path to `claude-resume` to bake into the layout (default: PATH lookup, then `~/bin/claude-resume`). |
| `CLAUDE_RESUME_DRYRUN` | `claude-resume` | If set, print the launch command instead of running it. |

The environment and flags applied at launch (`CLAUDE_ENV`, `CLAUDE_FLAGS`) are edited directly at the top of `claude-resume`.

---

## Why this license?

Claude Zellij Restore is free to use, modify, and share for any **noncommercial** purpose —
personal use, hobby projects, tinkering, learning, and contributions back are all
welcome and always will be. The one thing the license doesn't permit is **selling**
the software (or charging for hosting/support whose value comes mainly from it).

I built this to solve my own problem and I'm happy to share it freely; I just don't
want it repackaged and sold out from under the people it's meant to help. If you
have a commercial use in mind, get in touch and we can sort something out.

## License

Source-available under the **MIT License with the Commons Clause** — free to use, modify, and redistribute for any **noncommercial** purpose; you may not sell the software. See [LICENSE](LICENSE).
