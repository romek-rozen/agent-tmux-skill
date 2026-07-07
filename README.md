# agent-tmux-skill

A portable Agent Skill that teaches coding agents to
drive **tmux** — start interactive programs, poll their output, send input, and
clean up — using a private socket so it never touches your personal tmux.

Works across **pi**, **Claude Code**, **OpenAI Codex**, and **OpenCode**.
Pure `bash` + `tmux` + `grep`. No Python, no Node, no other runtime.

> **New to tmux or skills?** Start with the [Beginner's Guide](GUIDE.md).
>
> **An AI agent installing or editing this?** See [AGENTS.md](AGENTS.md).
>
> **Running an agent *inside* tmux?** You likely need a few `~/.tmux.conf` lines
> so `Shift+Enter` and notifications work — see
> [skills/tmux/references/tmux-config.md](skills/tmux/references/tmux-config.md).

## Why

Agents are great at one-shot commands but bad at *interactive* terminals:
REPLs, debuggers, installers that prompt, SSH sessions, TUIs, or another agent
running in a pane. This skill gives them a safe, token-cheap way to do it:

- **Named private socket** — agent sessions run on `tmux -L agent`, isolated
  from your own tmux (clean up with one `kill-server`) yet easy to watch:
  `tmux -L agent attach -t <session>`.
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
Codex reads skills from `~/.codex/skills` (or `$CODEX_HOME/skills` if set):
```bash
cp -R skills/tmux ~/.codex/skills/tmux
chmod +x ~/.codex/skills/tmux/scripts/*.sh
```
Start a fresh Codex session, then invoke the `tmux` skill.

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
./scripts/tm.sh idle  agent-py                # wait until pane stops changing (TUIs/agents)
./scripts/tm.sh classify agent-py             # triage: running/needs-human/stuck/complete
./scripts/tm.sh peek  agent-py 50             # last 50 lines
./scripts/tm.sh key   agent-py C-c            # raw keys
./scripts/tm.sh list                          # sessions on the socket
./scripts/tm.sh doctor                        # read-only health check
./scripts/tm.sh kill  agent-py                # or: kill-all
```

It also manages multi-pane workspaces — splits, windows, layout presets, and a
monitoring dashboard across many panes:

```bash
./scripts/tm.sh start dev --cwd ~/my-project
./scripts/tm.sh layout dev dev                # editor + logs + shell (also: 2x2, watch)
./scripts/tm.sh run  dev:0.1 'tail -f app.log'   # address a specific pane
./scripts/tm.sh split dev:0.0 -h 'htop'          # split + run a command
./scripts/tm.sh dashboard dev                 # status table of every pane; exit = worst state
./scripts/tm.sh save dev /tmp/dev.tmux        # snapshot the layout; restore with `restore`
```

Core actions: `start | send | type | key | run | wait | idle | classify | peek | list | attach-cmd | kill | kill-all | doctor`.
Pane/window manager: `split | window | select | zoom | rename | resize | tree`.
Layouts & workspaces: `layout | save | restore`. Monitoring: `dashboard`.

See [`skills/tmux/SKILL.md`](skills/tmux/SKILL.md) for the full instructions,
recipes (Python/gdb/lldb/psql/ssh), layout presets, and the raw-tmux reference.

## Layout

```
AGENTS.md                    # deploy/install guide for AI agents
GUIDE.md                     # beginner's guide
skills/tmux/
├── SKILL.md                 # agent instructions
├── GOTCHAS.md               # non-obvious behaviors and edge cases
├── references/
│   ├── tmux-config.md       # ~/.tmux.conf for running agents inside tmux
│   └── layouts.md           # layout presets (dev/2x2/watch) + workspace file format
└── scripts/
    ├── tm.sh                # wrapper: core + pane/window mgmt + layouts + save/restore + dashboard
    ├── wait-for-text.sh     # poll a pane for a regex until match or timeout
    ├── wait-for-idle.sh     # wait until a pane stops changing (TUIs/live agents)
    ├── classify-pane.sh     # watchdog triage: running/needs-human/stuck/complete
    ├── dashboard.sh         # classify every pane into one status table (exit = worst state)
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

## Support

If this skill saves you time, consider supporting the work:

- GitHub Sponsors: https://github.com/sponsors/romek-rozen
- Patreon: https://www.patreon.com/RomanRozenberger

## License

Apache-2.0 — see [LICENSE](LICENSE).

## Note

This skill follows the "Agent Skills" format (a `SKILL.md` directory convention)
used by several coding agents. Some background material we consulted while
building this lives at the community site agentskills.io.
