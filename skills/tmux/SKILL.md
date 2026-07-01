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

Actions: `start | send | type | key | run | wait | peek | list | attach-cmd | kill | kill-all | doctor`.
Run `./scripts/tm.sh doctor` first if anything misbehaves (read-only health check:
tmux version, socket dir/socket, live sessions, other agent sockets).
Socket is `$AGENT_TMUX_SOCKET` (default `<AGENT_TMUX_SOCKET_DIR>/agent.sock`); target
defaults to `<session>:0.0`. New sessions start in the current directory (the project
you're working in); choose another with `start <s> --cwd /path ...` or `TM_CWD=/path`. Drop to raw `tmux -S "$SOCKET" ...` (below) only for
anything the wrapper doesn't cover (extra windows/panes, custom capture ranges).

## Quickstart (raw tmux, isolated socket)

```bash
SOCKET_DIR="${AGENT_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/agent-tmux-sockets}"
mkdir -p "$SOCKET_DIR"
SOCKET="$SOCKET_DIR/agent.sock"    # keep agent sessions separate from user tmux
SESSION=agent-python              # slug-like names, no spaces

# -c "$PWD" makes the session start in the project dir, not the tmux server's default
tmux -S "$SOCKET" new -d -s "$SESSION" -c "$PWD" -n shell
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- 'PYTHON_BASIC_REPL=1 python3 -q' Enter
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -200   # read output
tmux -S "$SOCKET" kill-session -t "$SESSION"                    # clean up
```

After starting a session, ALWAYS tell the user how to monitor it — give a
copy/paste command right away and again at the end of your work:

```
To watch this session live:
  tmux -S "$SOCKET" attach -t agent-python      (detach with Ctrl+b d)
Or capture output once:
  tmux -S "$SOCKET" capture-pane -p -J -t agent-python:0.0 -S -200
```

## Focus & safety policy

- Automation uses `send-keys` / `capture-pane` only. NEVER `attach` on the user's
  behalf — `attach` hijacks their terminal. Attaching is for the human; the agent
  only prints the attach command (see `attach-cmd`).
- Don't touch sessions outside the agent socket; keep everything under `$SOCKET`.
- `doctor`, `list`, `peek`, `wait` are read-only and safe to run anytime.

## Socket convention

- Place sockets under `AGENT_TMUX_SOCKET_DIR` (default
  `${TMPDIR:-/tmp}/agent-tmux-sockets`) and always pass `-S "$SOCKET"` so
  sessions can be enumerated and cleaned. Create the dir first with `mkdir -p`.
- Default socket path unless you need further isolation:
  `SOCKET="$AGENT_TMUX_SOCKET_DIR/agent.sock"`.
- Add `-f /dev/null` for a clean config if the user's tmux config interferes;
  omit it when you need their config.

## Targeting & inspecting

- Target format: `{session}:{window}.{pane}`, defaults to `:0.0` if omitted.
- Keep names short: `agent-py`, `agent-gdb`, `agent-ssh`.
- `tmux -S "$SOCKET" list-sessions` — sessions on this socket
- `tmux -S "$SOCKET" list-panes -a` / `list-windows -t "$SESSION"`
- Enumerate with metadata: `./scripts/find-sessions.sh -S "$SOCKET"`
  (add `-q partial-name` to filter, or `--all` to scan every agent socket).

## Sending input safely

- Prefer literal sends to avoid shell splitting / TUI paste quirks:
  `tmux -S "$SOCKET" send-keys -t "$TARGET" -l -- "$text"`
  then a separate `tmux -S "$SOCKET" send-keys -t "$TARGET" Enter`
  (a short `sleep 0.1` between them helps interactive TUIs).
- Control keys: `C-c` (interrupt), `C-d` (EOF), `C-z` (suspend), `Escape`,
  `Tab`, `Up`. Example: `tmux -S "$SOCKET" send-keys -t "$TARGET" C-c`.
- Inline commands: single-quote or ANSI-C quote to avoid expansion, e.g.
  `send-keys -t "$TARGET" -- $'python3 -m http.server 8000' Enter`.

## Watching output

- Snapshot recent history (joined lines avoid wrap artifacts):
  `tmux -S "$SOCKET" capture-pane -p -J -t "$TARGET" -S -200`.
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

```bash
# Is it waiting for input?
tmux -S "$SOCKET" capture-pane -p -t "$TARGET" | tail -12 | grep -Ei '❯|yes.*no|proceed|permission|\(y/n\)'
# Approve a prompt / pick an option:
tmux -S "$SOCKET" send-keys -t "$TARGET" 'y' Enter
tmux -S "$SOCKET" send-keys -t "$TARGET" '2' Enter
# Hand it a task:
tmux -S "$SOCKET" send-keys -t "$TARGET" -l -- "Fix the bug in auth.js"; sleep 0.1
tmux -S "$SOCKET" send-keys -t "$TARGET" Enter
```

## Cleanup

- One session: `tmux -S "$SOCKET" kill-session -t "$SESSION"`.
- All on a socket: `tmux -S "$SOCKET" kill-server`.
- Loop-kill: `tmux -S "$SOCKET" list-sessions -F '#{session_name}' | xargs -r -n1 tmux -S "$SOCKET" kill-session -t`.

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
- `./scripts/find-sessions.sh [-S socket-path | -L socket-name | --all] [-q filter]`
  — list sessions with attached/created metadata across agent sockets.
