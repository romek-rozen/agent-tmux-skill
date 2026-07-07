# tmux Skill — Gotchas

Non-obvious behaviors and edge cases. Read before debugging "why did it do that".

## `tm.sh classify` always exits 0 — read stdout, not `$?`

`classify-pane.sh` encodes the state in its **exit code**
(`0 running · 1 needs-human · 2 stuck · 3 complete`), so you can branch on it:

```bash
./scripts/classify-pane.sh -t w-foo:0.0 -L agent; case $? in 1) escalate;; esac
```

But `tm.sh classify` wraps it in `|| true` so `set -e` can't abort the wrapper.
That means **through `tm.sh` the exit code is always 0** — parse the state word
from stdout instead:

```bash
state=$(tm.sh classify w-foo | cut -f1)   # running|needs-human|stuck|complete
```

Call `classify-pane.sh` directly when you want exit-code semantics; use
`tm.sh classify` when you want a human-readable line.

## `classify` reads only the *visible* pane, and greps signatures

It inspects the last `-l` lines (default 80). Two consequences:

- A stuck/error signature that scrolled off the top is missed — bump `-l` for
  long, noisy panes.
- It's pattern-matching, not understanding. An error string quoted in ordinary
  output (e.g. a log line containing `permission denied`) can read as `stuck`.
  Treat the state as a **triage hint**, then `peek` to confirm before acting.

## `wait`/`idle` watch pane TEXT; file signals need plain polling

`wait-for-text.sh` and `wait-for-idle.sh` only see pane output. The file-based
handoff signals (`READY_FOR_EXECUTOR`, `DONE`, …) are files on disk — poll them
with `until [ -f SIGNAL ]; do sleep 1; done`, not with the pane waiters.

## A coding-agent TUI is "ready" almost always — use `idle`, not `wait`

Claude Code / Codex keep their prompt char (`❯`) on screen while working, so
`wait '❯'` returns immediately. Wait for quiescence (`idle`) instead, then
`classify`/`peek`. (Also covered in SKILL.md.)

## Never auto-answer secret/destructive prompts

`classify` flags credential and confirmation prompts as `needs-human` by design.
Do not script a blanket `send-keys y Enter` in response — see the auto-answer
guardrail in SKILL.md for the may/never list.

## Layout & panes

- **`select-layout` overrides manual splits.** `tm.sh layout` (and `restore`'s
  evening-out step) calls `tmux select-layout`, which redistributes pane sizes
  and can undo hand-tuned `resize`s. Apply the preset first, then `resize`.
- **Pane indices renumber after a pane closes.** If a pane exits, tmux may
  renumber the rest, so a saved `dev:0.2` can point elsewhere. Re-check with
  `tm.sh tree` before addressing panes by index after anything closed.
- **A bare target hits pane 0; a dotted one is literal.** `send dev '...'`
  resolves to `dev:0.0`. In multi-pane sessions, address panes explicitly
  (`dev:0.1`) — and remember `select`/`zoom`/presets move the *active* pane, which
  only matters for tmux commands that fall back to it.
- **`split` needs room.** A very small window can refuse to split
  ("no space for new pane"). `zoom` out or `resize` first, or use a new
  `window` instead of another split.
- **`-J` capture on narrow panes.** `peek`/`classify` use `capture-pane -J` to
  join wrapped lines; in a narrow pane, wrapping still affects what a regex sees.
  Widen the pane (or `zoom`) if a `wait` regex won't match.

## Workspaces

- **`restore` won't overwrite a live session.** It refuses if the target
  session already exists — `kill` it first.
- **`restore` does not re-run commands.** Only geometry + cwd are rebuilt (by
  design). Re-issue processes with `tm.sh run`/`window`.
- **Saved cwd must still exist.** If a recorded `pane_current_path` is gone,
  `restore` falls back to `TM_CWD`/`$PWD` for that pane.
- **Everything lives on the `agent` socket.** `tm.sh list`/`kill-all`/`dashboard`
  only ever see `tmux -L agent`. Attaching to the wrong socket by mistake is the
  usual "my session disappeared" cause: use `tmux -L agent attach`.
