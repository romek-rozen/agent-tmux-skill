# agent-tmux-skill

A portable [Agent Skill](https://agentskills.io) that teaches coding agents to
drive **tmux** — start interactive programs, poll their output, send input, and
clean up — using a private socket so it never touches your personal tmux.

Works across **pi**, **Claude Code**, **OpenAI Codex**, and **OpenCode**.
Pure `bash` + `tmux` + `grep`. No Python, no Node, no other runtime.

> **New to tmux or skills?** Start with the [Beginner's Guide](GUIDE.md).
>
> **Running an agent *inside* tmux?** You likely need a few `~/.tmux.conf` lines
> so `Shift+Enter` and notifications work — see
> [skills/tmux/references/tmux-config.md](skills/tmux/references/tmux-config.md).

## Why

Agents are great at one-shot commands but bad at *interactive* terminals:
REPLs, debuggers, installers that prompt, SSH sessions, TUIs, or another agent
running in a pane. This skill gives them a safe, token-cheap way to do it:

- **Private socket** — agent sessions live under `$AGENT_TMUX_SOCKET_DIR`,
  isolated from your own tmux. Clean up with one `kill-server`.
- **Token-cheap** — `wait` polls silently and returns just success/failure;
  timeouts print only the last 40 lines; `peek N` fetches exactly N lines.
- **Focus-safe** — automation only uses `send-keys` / `capture-pane`. It never
  `attach`es on your behalf; it prints the attach command for *you*.
- **Project-aware** — sessions start in your project directory (`--cwd` / `$PWD`).

## Install

Clone anywhere and point your agent at the `skills/` directory.

### pi
Add to `~/.pi/agent/settings.json` (or a project `.pi/settings.json`):
```json
{ "skills": ["/path/to/agent-tmux-skill/skills"] }
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

## Usage

The skill ships a wrapper `scripts/tm.sh` so the agent doesn't retype raw tmux:

```bash
./scripts/tm.sh start agent-py --cwd ~/my-project 'PYTHON_BASIC_REPL=1 python3 -q'
./scripts/tm.sh wait  agent-py '^>>>' 10      # wait for prompt
./scripts/tm.sh send  agent-py 'print(6*7)'   # type + Enter (literal, safe)
./scripts/tm.sh wait  agent-py '^42$'
./scripts/tm.sh peek  agent-py 50             # last 50 lines
./scripts/tm.sh key   agent-py C-c            # raw keys
./scripts/tm.sh list                          # sessions on the socket
./scripts/tm.sh doctor                        # read-only health check
./scripts/tm.sh kill  agent-py                # or: kill-all
```

Actions: `start | send | type | key | run | wait | peek | list | attach-cmd | kill | kill-all | doctor`.

See [`skills/tmux/SKILL.md`](skills/tmux/SKILL.md) for the full instructions,
recipes (Python/gdb/lldb/psql/ssh), and the raw-tmux reference.

## Layout

```
GUIDE.md                     # beginner's guide
skills/tmux/
├── SKILL.md                 # agent instructions
├── references/
│   └── tmux-config.md       # ~/.tmux.conf for running agents inside tmux
└── scripts/
    ├── tm.sh                # wrapper: start/send/wait/peek/list/kill/doctor/...
    ├── wait-for-text.sh     # poll a pane for a regex until match or timeout
    └── find-sessions.sh     # list sessions with metadata across agent sockets
```

## Requirements

- `tmux` (>= 3.0), `bash`, `grep` — present on stock macOS and Linux.

## Credits

Built by combining and adapting ideas from prior work:

- **[mitsuhiko/agent-stuff](https://github.com/mitsuhiko/agent-stuff)** — the
  base of this skill: isolated private socket, the `wait-for-text.sh` and
  `find-sessions.sh` helper scripts, REPL/gdb recipes, `PYTHON_BASIC_REPL=1`,
  and the "always print the attach command for the user" rule.
- **[firecrawl/openclaw](https://github.com/firecrawl/openclaw)** — the
  when-to-use / when-not framing and patterns for driving another agent
  (Claude Code / Codex) via prompt detection and safe literal sends.
- **[indigoviolet/pi-tmux](https://github.com/indigoviolet/pi-tmux)** —
  conceptual inspiration for per-project session isolation (that project is a
  pi *extension*; this repo is a portable, shell-only *skill*).
- **[manaflow-ai/cmux](https://github.com/manaflow-ai/cmux)** — the `doctor`
  health-check pattern and the focus-safety policy (automation must not steal
  focus / attach on the user's behalf).

## License

MIT — see [LICENSE](LICENSE).
