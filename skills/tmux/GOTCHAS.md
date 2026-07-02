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
