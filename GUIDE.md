# Beginner's Guide

A step-by-step guide for people who have never used tmux or agent skills.
If you just want the reference, read [`skills/tmux/SKILL.md`](skills/tmux/SKILL.md).

## 1. What is this, in plain words

Coding agents (Claude Code, pi, Codex, OpenCode) are great at running one-shot
commands, but they struggle with **interactive** programs — things that keep
running and ask you questions: a Python shell, a debugger, an installer, `ssh`,
or even another agent.

**tmux** is a "terminal multiplexer": it lets a program keep running in the
background in a named session, so you (or an agent) can send it keystrokes and
read its screen at any time.

This skill teaches your agent to use tmux **safely**:

- it runs everything on a **private socket**, so it never messes with your own
  tmux sessions;
- it **never takes over your terminal** — it just prints a command you can paste
  to watch live;
- it's **cheap on tokens** — it waits silently and only reads the few lines it
  needs.

## 2. What is tmux (30-second mental model)

- **Session** = a named workspace that keeps running even if you close the
  window. Example name: `agent-py`.
- **Window** = a tab inside a session.
- **Pane** = a split inside a window.
- You **attach** to watch a session live, and **detach** to leave it running.
  Detach = press `Ctrl+b`, then `d`.

That's all you need to start.

### "If it's isolated, can I still watch it?" — yes!

Isolation does **not** mean you're locked out. The skill just puts agent
sessions on a **separate named socket** (called `agent`) so they don't mix with
your own tmux sessions. You can attach and watch live at any time — it's short:

```bash
tmux -L agent attach -t <session>     # watch live (Ctrl+b then d to leave)
```

The `start` command prints this exact line for you. The isolation only buys two
things: safe cleanup (`kill-all` never touches your personal tmux) and zero
conflict with your `~/.tmux.conf`. It never hides anything from you.

## 3. Install tmux (one time)

```bash
# macOS (Homebrew)
brew install tmux

# Debian / Ubuntu
sudo apt install tmux

# Fedora
sudo dnf install tmux

# check it's there
tmux -V
```

You want **tmux 3.5 or newer** for the smoothest experience (see step 7).

## 4. Install the skill

Pick your agent. "Personal" install means it works in all your projects.

### pi
Add the `skills/` folder to your settings (`~/.pi/agent/settings.json`):
```json
{ "skills": ["/absolute/path/to/agent-tmux-skill/skills"] }
```

### Claude Code
```bash
cp -R skills/tmux ~/.claude/skills/tmux
```

### OpenAI Codex
```bash
cp -R skills/tmux ~/.codex/skills/tmux
```

### OpenCode
```bash
cp -R skills/tmux ~/.config/opencode/skills/tmux
```

Restart your agent (or start a new session) so it discovers the skill.

## 5. Check it works

Ask your agent something like:

> Use the tmux skill to start a Python REPL, compute 6*7, and show me the result.

Or run the health check yourself:

```bash
cd skills/tmux
./scripts/tm.sh doctor
```

You should see your tmux version, the socket path, and any live sessions.

## 6. A full example you can run by hand

```bash
cd skills/tmux

# start a Python shell in a session called "demo", in the current folder
./scripts/tm.sh start demo 'PYTHON_BASIC_REPL=1 python3 -q'

# wait until the >>> prompt shows up (max 10s)
./scripts/tm.sh wait demo '^>>>' 10

# type a line of code (this presses Enter for you)
./scripts/tm.sh send demo 'print(6*7)'

# wait for the answer, then look at the last 20 lines
./scripts/tm.sh wait demo '^42$'
./scripts/tm.sh peek demo 20

# watch it live in another terminal (optional) — paste what `start` printed:
#   tmux -L agent attach -t demo      (leave with Ctrl+b then d)

# clean up when done
./scripts/tm.sh kill demo
```

Want it to open in a specific project folder? Add `--cwd`:

```bash
./scripts/tm.sh start demo --cwd ~/my-project 'npm test'
```

## 7. Important: configure tmux if you RUN AGENTS inside tmux

This is a **separate** thing from the skill. If you like to run Claude Code / pi
/ Codex *inside a tmux pane yourself*, tmux by default eats modifier keys, so
`Shift+Enter` (newline) and `Ctrl+Enter` stop working, and Claude Code
notifications don't reach your terminal.

Fix it once in `~/.tmux.conf`:

```tmux
set -g allow-passthrough on
set -g extended-keys on
set -g extended-keys-format csi-u
set -as terminal-features 'xterm*:extkeys'
```

Apply it:

```bash
tmux source-file ~/.tmux.conf      # or: tmux kill-server && tmux
```

Notes:
- `extended-keys-format csi-u` needs **tmux 3.5+**. On 3.2–3.4, drop that one line.
- Use a terminal that supports extended keys: Ghostty, Kitty, iTerm2, WezTerm,
  Windows Terminal.

Full explanation: [`skills/tmux/references/tmux-config.md`](skills/tmux/references/tmux-config.md).

## 8. Command cheat sheet

| Command | What it does |
|---|---|
| `tm.sh start <name> [--cwd DIR] [cmd]` | Create a session (optionally run a command) |
| `tm.sh send <name> <text>` | Type text + Enter (safe for TUIs) |
| `tm.sh type <name> <text>` | Type text, no Enter |
| `tm.sh key <name> C-c` | Send raw keys (`C-c`, `Enter`, `Escape`, …) |
| `tm.sh run <name> <cmd>` | Send a whole command line + Enter |
| `tm.sh wait <name> <regex> [secs]` | Wait until text appears (default 15s) |
| `tm.sh idle <name> [stable] [secs]` | Wait until the pane stops changing (TUIs / live agents) |
| `tm.sh classify <name>` | Triage a pane: running / needs-human / stuck / complete |
| `tm.sh peek <name> [lines]` | Print the last N lines (default 50) |
| `tm.sh list` | List sessions on the private socket |
| `tm.sh doctor` | Read-only health check |
| `tm.sh kill <name>` / `kill-all` | Stop one session / everything |
| `tm.sh split <name> [-h\|-v] [cmd]` | Split a pane (side-by-side / stacked), optionally run a command |
| `tm.sh window <name> <win> [cmd]` | Open a new window (a tab) |
| `tm.sh zoom <name>:0.1` | Toggle a pane to fullscreen and back |
| `tm.sh resize <name>:0.1 -R 10` | Grow/shrink a pane (`-L/-R/-U/-D` by N cells) |
| `tm.sh tree <name>` | Show windows/panes with their running command + cwd |
| `tm.sh layout <name> <preset>` | Arrange into a preset (`dev` / `2x2` / `watch`) |
| `tm.sh save <name> <file>` / `restore <file>` | Snapshot / rebuild a layout |
| `tm.sh dashboard [name]` | Status table of every pane (exit code = worst state) |

Multi-pane targets are `<name>:<window>.<pane>` (e.g. `dev:0.1`); a bare `<name>`
still means window 0, pane 0. See
[skills/tmux/references/layouts.md](skills/tmux/references/layouts.md) for the
layout presets and the workspace file format.

## 9. Troubleshooting

- **"can't find session" / "no server"** — you probably ran raw `tmux` without
  `-S`. The skill uses a private socket; run `./scripts/tm.sh list` or
  `./scripts/tm.sh doctor` instead.
- **Agent doesn't use the skill** — make sure it's installed in the right folder
  (step 4) and you started a fresh session. Try invoking it directly, e.g.
  `/skill:tmux` in pi.
- **`Shift+Enter` acts weird when running an agent in tmux** — do step 7.
- **A stuck program** — interrupt it with `./scripts/tm.sh key <name> C-c`.
- **Left something running** — `./scripts/tm.sh list` then `kill` / `kill-all`.

## 10. Where to go next

- [`skills/tmux/SKILL.md`](skills/tmux/SKILL.md) — the full reference and recipes
  (Python, gdb/lldb, psql, ssh, driving another agent).
- [`README.md`](README.md) — overview, install per harness, credits.
