---
name: tmux
description: Remote-control tmux sessions to drive interactive CLIs (python, gdb/lldb, psql, node REPL, ssh, installers, TUIs, other agents) by sending keystrokes and scraping pane output. Use when you must interact with a long-running or interactive terminal program, monitor background work, answer prompts, or observe a process over time — not for one-off non-interactive commands.
license: Apache-2.0
compatibility: Requires tmux (>=3.0), bash, and grep. Works on macOS and Linux with stock tmux.
metadata:
  { "os": ["darwin", "linux"], "requires": { "bins": ["tmux", "bash", "grep"] } }
---

# tmux Skill

Use tmux as a programmable terminal multiplexer for interactive work: start a
program, poll its output, send it input, and clean up. Works on Linux/macOS with
stock tmux. Stay off the user's personal tmux by using a private socket.

## When to use

✅ Interactive REPLs/debuggers (python, ipython, node, gdb, lldb, psql, mysql)
✅ Programs that prompt for input (installers, `ssh`, confirmations, TUIs)
✅ Long-running processes you must watch, or background work to check on later
✅ Driving/monitoring another agent (Claude Code, Codex) running in a pane

❌ One-off non-interactive commands → just run them with `bash`
❌ Fire-and-forget background jobs that need no interaction → run backgrounded

## Fast path: use `./scripts/tm.sh` (don't retype tmux)

A wrapper handles the socket and common actions, so prefer it over raw `tmux`:

```bash
./scripts/tm.sh start agent-py --cwd ~/my-project 'npm test'     # open in a chosen dir
./scripts/tm.sh start agent-py 'PYTHON_BASIC_REPL=1 python3 -q'  # create + run, prints attach cmd
./scripts/tm.sh wait  agent-py '^>>>' 10                         # wait for prompt
./scripts/tm.sh send  agent-py 'print(6*7)'                      # type + Enter (literal, safe)
./scripts/tm.sh wait  agent-py '^42$'
./scripts/tm.sh peek  agent-py 50                                # last 50 lines
./scripts/tm.sh key   agent-py C-c                               # raw keys (C-c, Enter, Escape)
./scripts/tm.sh list                                             # sessions on the socket
./scripts/tm.sh kill  agent-py                                   # or: kill-all
```

Actions: `start | send | type | key | run | wait | idle | peek | list | attach-cmd | kill | kill-all | doctor`.
Use `wait <re>` for deterministic prompts; use `idle` (wait until the pane stops
changing) for TUIs / live agents that have no stable ready-string.
Run `./scripts/tm.sh doctor` first if anything misbehaves (read-only health check:
tmux version, socket name, live sessions).
Socket is the named tmux socket `$AGENT_TMUX_SOCKET` (default `agent`), i.e.
`tmux -L agent ...`; target defaults to `<session>:0.0`. New sessions start in the
current directory (the project you're working in); choose another with
`start <s> --cwd /path ...` or `TM_CWD=/path`. Drop to raw `tmux -L agent ...` (below) only for
anything the wrapper doesn't cover (extra windows/panes, custom capture ranges).

## Quickstart (raw tmux, isolated socket)

```bash
SOCKET=agent                      # named socket: isolated but easy to attach (tmux -L)
SESSION=agent-python              # slug-like names, no spaces

# -c "$PWD" makes the session start in the project dir, not the tmux server's default
tmux -L "$SOCKET" new -d -s "$SESSION" -c "$PWD" -n shell
tmux -L "$SOCKET" send-keys -t "$SESSION":0.0 -- 'PYTHON_BASIC_REPL=1 python3 -q' Enter
tmux -L "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -200   # read output
tmux -L "$SOCKET" kill-session -t "$SESSION"                    # clean up
```

After starting a session, ALWAYS tell the user how to monitor it — give a
copy/paste command right away and again at the end of your work:

```
To watch this session live:
  tmux -L agent attach -t agent-python      (detach with Ctrl+b d)
Or capture output once:
  tmux -L agent capture-pane -p -J -t agent-python:0.0 -S -200
```

## Focus & safety policy

- Automation uses `send-keys` / `capture-pane` only. NEVER `attach` on the user's
  behalf — `attach` hijacks *the agent's* terminal. Attaching is for the human;
  the agent only prints the attach command (see `attach-cmd`).
- Isolation ≠ no visibility. The named socket only *separates* agent sessions
  from the user's personal tmux; the human can attach any time with
  `tmux -L agent attach -t <session>` to watch live, and detach with
  `Ctrl+b d` without killing anything. Isolation is for safe cleanup
  (`kill-server` touches only agent sessions) and zero collision with the
  user's own tmux/config — not to hide the sessions.
- Don't touch sessions outside the agent socket; keep everything under `$SOCKET`.
- `doctor`, `list`, `peek`, `wait`, `classify` are read-only and safe to run anytime.

### Auto-answer guardrail (what you may / may NEVER click)

When driving another agent/TUI you can auto-approve *safe* prompts, but some
must always go to a human. Before sending `y`/Enter to a prompt, apply this:

- ✅ **May auto-answer** (idempotent, non-destructive, easily reversible):
  dev-server port-in-use retries, "install this dev dependency?", "create this
  directory?", linter/formatter fixes, "reload config?".
- 🚫 **NEVER auto-answer** — hand to the human (`classify` reports these as
  `needs-human`):
  - **secrets/credentials**: password, passphrase, API key, token, 2FA / OTP.
    Never type a secret into a pane on the agent's own initiative.
  - **destructive / irreversible**: `rm -rf`, `git push --force`, DROP/DELETE,
    disk format, "overwrite N files?", production deploys.
  - **financial / external side effects**: payments, sending mail, posting to
    third parties, provisioning paid resources.
  - anything you're **unsure** about — default to escalate, not to click.

Encode this as a short policy in your task, not from memory, and log every
auto-answer you make (pane, prompt, what you sent) so it's auditable.

## Socket convention

- Use a **named** tmux socket via `-L "$SOCKET"` (default name `agent`). Named
  sockets stay isolated from the user's default tmux but are trivial to attach
  (`tmux -L agent attach -t <session>`) — no long path to paste.
- Override the name with `AGENT_TMUX_SOCKET=<name>` if you need more isolation.
- Add `-f /dev/null` for a clean config if the user's tmux config interferes;
  omit it when you need their config.

## Targeting & inspecting

- Target format: `{session}:{window}.{pane}`, defaults to `:0.0` if omitted.
- Keep names short: `agent-py`, `agent-gdb`, `agent-ssh`.
- `tmux -L "$SOCKET" list-sessions` — sessions on this socket
- `tmux -L "$SOCKET" list-panes -a` / `list-windows -t "$SESSION"`
- Enumerate with metadata: `./scripts/find-sessions.sh -L "$SOCKET"`
  (add `-q partial-name` to filter).

## Sending input safely

- Prefer literal sends to avoid shell splitting / TUI paste quirks:
  `tmux -L "$SOCKET" send-keys -t "$TARGET" -l -- "$text"`
  then a separate `tmux -L "$SOCKET" send-keys -t "$TARGET" Enter`
  (a short `sleep 0.1` between them helps interactive TUIs).
- Control keys: `C-c` (interrupt), `C-d` (EOF), `C-z` (suspend), `Escape`,
  `Tab`, `Up`. Example: `tmux -L "$SOCKET" send-keys -t "$TARGET" C-c`.
- Inline commands: single-quote or ANSI-C quote to avoid expansion, e.g.
  `send-keys -t "$TARGET" -- $'python3 -m http.server 8000' Enter`.

## Watching output

- Snapshot recent history (joined lines avoid wrap artifacts):
  `tmux -L "$SOCKET" capture-pane -p -J -t "$TARGET" -S -200`.
- Whole scrollback: `capture-pane -p -J -t "$TARGET" -S -`.
- For sync, poll for expected text instead of blind `sleep`. `tmux wait-for`
  does NOT watch pane output — use the helper below.

## Synchronizing / waiting for prompts

Wait for a prompt/marker before sending the next input (avoids races):

```bash
./scripts/wait-for-text.sh -t "$SESSION":0.0 -p '^>>>' -T 15 -l 4000
```

For long commands, poll for a completion marker (e.g. `Program exited`,
`Type quit to exit`, a shell prompt) before proceeding. Exits 0 on match
(silent, token-cheap), 1 on timeout (prints only the last 40 lines to stderr;
use `peek` if you need more).

## Interactive tool recipes

- **Python REPL**: set `PYTHON_BASIC_REPL=1` (the fancy REPL breaks send-keys),
  `send-keys -- 'PYTHON_BASIC_REPL=1 python3 -q' Enter`; wait for `^>>>`; send
  code with `-l`; interrupt with `C-c`.
- **lldb / gdb** (default debugger: lldb): start `lldb ./a.out` or
  `gdb --quiet ./a.out`; disable paging in gdb with `set pagination off`;
  break with `C-c`; run `bt`, `info locals`; exit with `quit` (+ confirm `y`).
- **psql / mysql / node / ipdb / ssh**: same pattern — start it, poll for its
  prompt, then send literal text + `Enter`.

## Driving/monitoring another agent (Claude Code, Codex)

### Waiting for a live agent to finish (use `idle`, not `wait`)

A coding-agent TUI (Claude Code, Codex) redraws constantly and its prompt char
(e.g. `❯`) is almost always on screen, so `wait '❯'` returns immediately even
while it's still working. For agents/TUIs, wait for **quiescence** instead:

```bash
tm.sh idle w-auth-tests            # default: idle = no change for 3s, timeout 60s
tm.sh idle w-auth-tests 5 300      # stricter: 5s of silence, up to 5 min
```

`idle` returns when the pane content stops changing for `--stable` seconds — a
reliable "it finished / is waiting for me" signal. Keep using `wait <regex>`
for deterministic prompts (python `>>>`, shell `$`, gdb). Combine them: send a
task, `idle` until it settles, then `peek` to read the result.

### Triage a quiet pane: `classify` (watchdog)

`idle` tells you a pane went quiet; it doesn't tell you *why*. `classify` greps
the visible pane for known signatures and prints one state — so a watchdog loop
can decide whether to auto-continue, escalate, or move on:

```bash
tm.sh idle w-auth-tests && tm.sh classify w-auth-tests
#   running       still working (assume so if nothing else matches)
#   needs-human   confirmation / credential / "waiting for input" prompt
#   stuck         traceback / error / repeated failure on screen
#   complete      a done / passed / exited marker on screen
```

Exit code mirrors the state (`0 running · 1 needs-human · 2 stuck · 3 complete`),
so it composes in scripts. `needs-human` is where the **auto-answer guardrail**
(above) kicks in: secrets and destructive/financial prompts are surfaced, never
auto-clicked. Watchdog pattern over several agents:

```bash
for s in orch w-auth-tests w-api-refactor; do
  tm.sh classify "$s" 1     # 1 line per pane: STATE<tab>target + evidence
done
```

Use `classify` to *decide*, `peek` to *read the detail*, `wait`/`idle` to *sync*.

### Addressing: who is who, and routing to ONE target

- **One session = one addressable agent.** `send`/`run`/`send-keys -t <session>`
  go ONLY to that session's pane. There is **no broadcast** — input is not
  mirrored to other sessions. Route by choosing the right `-t` target.
- **Never enable `synchronize-panes`.** With `setw synchronize-panes on`, tmux
  mirrors keystrokes to every pane in a window — that's the only way input hits
  "all panes". Keep it off (default). If unsure:
  `tmux -L "$SOCKET" setw synchronize-panes off`.
- **Name sessions by what they DO, not by number.** `w1/w2/w3` is opaque — a
  human looking at the list can't tell what each is for. Use a short role prefix
  plus a task slug: `orch`, `w-auth-tests`, `w-api-refactor`, `w-docs`. Keep it
  slug-like (lowercase, hyphens, no spaces) and short.
  - orchestrator: `orch`
  - workers: `w-<task>` (e.g. `w-login-bug`, `w-migrate-db`)
  Then routing reads clearly: `tm.sh send orch "..."`, `tm.sh send w-auth-tests "..."`.
- **Which one is the orchestrator?** The session named `orch`. List roles any
  time with `tm.sh list` — with task-based names the list itself explains who
  does what. Optionally also set an on-screen pane title:
  `tmux -L "$SOCKET" select-pane -t w-auth-tests:0.0 -T "worker: auth tests"`.
- If you truly don't know a session's purpose, `peek <session>` shows its
  current screen; but prefer naming it right at `start` so this never happens.
- **Reading is per-target too.** `peek <session>` / `capture-pane -t <session>`
  read only that session — logs from one agent never leak into another's capture.

### Handing off work: keystrokes vs. files

Two ways to pass a task from one agent to another. Pick per situation:

- **Keystroke handoff** (below): type the task straight into the target's pane
  with `send-keys -l`. Immediate and simple; best for one-shot instructions and
  approvals. Fragile for big/multi-line payloads (TUI paste quirks, redraws).
- **File-based handoff**: agents coordinate through shared files instead of
  each other's panes — more robust for a planner→executor loop, and every step
  is on disk (auditable, survives a crashed pane). Convention:
  - `handoff.md` — the current task: objective, exact files/commands, acceptance
    criteria. Prefix `BLOCKED:` at the top if an agent gets stuck.
  - `planner-notes.md` / `executor-notes.md` — private scratchpads; neither
    agent overwrites the other's.
  - signal files: planner writes the task then `touch READY_FOR_EXECUTOR`;
    executor does the work, writes results to `executor-notes.md`, removes the
    signal, then `touch READY_FOR_PLANNER`; planner reviews and either issues the
    next task or `touch DONE`.

  Each agent just polls for its signal (no keystrokes into the other's pane):

  ```bash
  # signals are FILES, not pane text — poll them (not wait-for-text/idle):
  until [ -f READY_FOR_EXECUTOR ]; do sleep 1; done   # executor's driver
  until [ -f READY_FOR_PLANNER   ]; do sleep 1; done   # planner's driver
  ```

  Watch the whole handoff from a third pane:
  `watch -n1 'ls READY_* DONE 2>/dev/null; echo ---; sed -n 1,80p handoff.md'`.
  Route the *kickoff* with keystrokes (`tm.sh send w-exec "start the loop"`),
  then let the files carry the back-and-forth.

```bash
# Is it waiting for input?
tmux -L "$SOCKET" capture-pane -p -t "$TARGET" | tail -12 | grep -Ei '❯|yes.*no|proceed|permission|\(y/n\)'
# Approve a prompt / pick an option:
tmux -L "$SOCKET" send-keys -t "$TARGET" 'y' Enter
tmux -L "$SOCKET" send-keys -t "$TARGET" '2' Enter
# Hand it a task:
tmux -L "$SOCKET" send-keys -t "$TARGET" -l -- "Fix the bug in auth.js"; sleep 0.1
tmux -L "$SOCKET" send-keys -t "$TARGET" Enter
```

## Cleanup

- One session: `tmux -L "$SOCKET" kill-session -t "$SESSION"`.
- All on a socket: `tmux -L "$SOCKET" kill-server`.
- Loop-kill: `tmux -L "$SOCKET" list-sessions -F '#{session_name}' | xargs -r -n1 tmux -L "$SOCKET" kill-session -t`.

## Running a coding agent inside tmux (key config)

If you run an interactive agent (Claude Code, pi, Codex) *inside* a tmux pane
(not just this skill's automation), tmux strips modifier keys by default so
`Shift+Enter` / `Ctrl+Enter` break, and Claude Code notifications/progress get
swallowed. Fix it in the user's `~/.tmux.conf` — see
[references/tmux-config.md](references/tmux-config.md) for the exact lines
(`allow-passthrough`, `extended-keys`, `csi-u`) and version notes.

## Helper scripts

- `./scripts/tm.sh <action> ...` — one wrapper for start/send/run/wait/peek/list/kill
  on the private socket (see "Fast path" above). Use this first.
- `./scripts/wait-for-text.sh -t target -p pattern [-F] [-T 20] [-i 0.5] [-l 2000]`
  — poll a pane for a regex (`-F` = fixed string) until match or timeout.
  For deterministic prompts.
- `./scripts/wait-for-idle.sh -t target [-L name] [-s 3] [-T 60] [-l 200]`
  — wait until the pane stops changing (quiescence). For TUIs / live agents
  with no stable ready-string.
- `./scripts/classify-pane.sh -t target [-L name] [-l 80] [-q]`
  — watchdog triage: prints `running|needs-human|stuck|complete` for a pane
  (exit code mirrors state). Use after `idle` to decide auto-continue vs.
  escalate; honors the auto-answer guardrail (secrets → `needs-human`).
- `./scripts/find-sessions.sh [-S socket-path | -L socket-name | --all] [-q filter]`
  — list sessions with attached/created metadata across agent sockets.

Non-obvious behaviors and edge cases are collected in
[GOTCHAS.md](GOTCHAS.md) — read it before debugging surprising output.
