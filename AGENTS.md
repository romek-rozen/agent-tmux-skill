# AGENTS.md

Guidance for AI coding agents (pi, Claude Code, Codex, OpenCode) working in or
deploying this repository. Humans: see [GUIDE.md](GUIDE.md) and [README.md](README.md).

## What this repo is

A single, portable **Agent Skill** (`skills/tmux/`) that teaches an agent to
drive interactive terminal programs through tmux. It is shell-only
(`bash` + `tmux` + `grep`) and follows the [Agent Skills](https://agentskills.io)
standard, so the same directory works across harnesses.

Source of truth for the skill is `skills/tmux/`. Everything else is docs.

## Repo layout

```
AGENTS.md                        # this file
GUIDE.md                         # human beginner guide
README.md                        # overview + install + credits
LICENSE                          # MIT
skills/tmux/
├── SKILL.md                     # the skill (agent instructions)  <-- source of truth
├── references/
│   └── tmux-config.md           # ~/.tmux.conf for running agents inside tmux
└── scripts/
    ├── tm.sh                    # wrapper: start/send/type/key/run/wait/peek/list/attach-cmd/kill/kill-all/doctor
    ├── wait-for-text.sh         # poll a pane for a regex until match or timeout
    └── find-sessions.sh         # list sessions with metadata across agent sockets
```

## Core design rules (do not break these)

1. **Private socket.** All agent sessions live under `$AGENT_TMUX_SOCKET_DIR`
   (default `${TMPDIR:-/tmp}/agent-tmux-sockets`), socket `agent.sock`. Always
   pass `-S "$SOCKET"`. This isolates agent sessions from the user's tmux and
   makes cleanup safe (`kill-server` only affects agent sessions).
2. **Never attach on the user's behalf.** Automation uses `send-keys` /
   `capture-pane` only. Print the attach command for the human instead
   (`tm.sh attach-cmd`). Isolation ≠ hiding: the human can attach any time.
3. **Token discipline.** `wait` returns silently on success; timeout dumps only
   ~40 lines. `peek N` fetches exactly N lines (default 50). Never stream full
   scrollback into context.
4. **Project-aware cwd.** New sessions start in `--cwd` > `$TM_CWD` > current
   `$PWD`. Don't drop the `-c` flag on `tmux new`.
5. **Shell only.** No new runtime dependencies. Keep scripts `bash` + `tmux` +
   `grep`. Prefer editing `tm.sh` over adding new scripts.

## How to install the skill (per harness)

Pick the target harness. "Personal" install = available in all projects.

```bash
REPO="$(pwd)"   # run from a checkout of this repo

# pi — add the skills/ dir to settings (~/.pi/agent/settings.json):
#   { "skills": ["'"$REPO"'/skills"] }
# (pi also auto-loads ~/.claude/skills if that path is already in settings)

# Claude Code
cp -R "$REPO/skills/tmux" ~/.claude/skills/tmux

# OpenAI Codex
cp -R "$REPO/skills/tmux" ~/.codex/skills/tmux

# OpenCode
cp -R "$REPO/skills/tmux" ~/.config/opencode/skills/tmux

# ensure scripts are executable in every target
chmod +x ~/.claude/skills/tmux/scripts/*.sh \
         ~/.codex/skills/tmux/scripts/*.sh \
         ~/.config/opencode/skills/tmux/scripts/*.sh 2>/dev/null || true
```

Notes:
- Codex reads skills from `$CODEX_HOME/skills` when `CODEX_HOME` is set, else
  `~/.codex/skills`.
- pi can also load skills from `~/.claude/skills` / `~/.codex/skills` if those
  paths are listed in its `skills` setting; avoid installing to both a native pi
  path and a shared path to prevent a duplicate-name warning.
- After install, start a fresh agent session so the skill is discovered.

## Verifying an install

```bash
cd <install-dir>/tmux            # e.g. ~/.claude/skills/tmux
bash -n scripts/tm.sh            # syntax check
./scripts/tm.sh doctor           # read-only health check (tmux, socket, sessions)

# smoke test end-to-end
./scripts/tm.sh start _verify 'PYTHON_BASIC_REPL=1 python3 -q'
./scripts/tm.sh wait  _verify '^>>>' 10
./scripts/tm.sh send  _verify 'print(6*7)'
./scripts/tm.sh wait  _verify '^42$' 10 && echo OK
./scripts/tm.sh kill  _verify
```

## Keeping copies in sync (when editing the skill)

`skills/tmux/` in this repo is the source of truth. After editing it, re-copy to
any installed locations and confirm they match:

```bash
for d in ~/.claude/skills/tmux ~/.codex/skills/tmux ~/.config/opencode/skills/tmux; do
  [ -d "$d" ] && { rm -rf "$d"; mkdir -p "$d"; cp -R skills/tmux/. "$d/"; chmod +x "$d"/scripts/*.sh; }
done
diff -rq skills/tmux ~/.claude/skills/tmux && echo "in sync"
```

## Making changes

- Edit `skills/tmux/SKILL.md` for behavior/instructions; keep it concise (its
  content stays in the agent's context once loaded — every line is recurring
  token cost). Move long material into `references/` (loaded on demand).
- Edit `skills/tmux/scripts/tm.sh` for wrapper actions. Run `bash -n` after.
- Keep the `license: MIT` frontmatter in `SKILL.md` consistent with `LICENSE`.
- Update `README.md` / `GUIDE.md` if user-facing behavior changes.
- Credit upstream sources in `README.md` (see its Credits section) when porting
  ideas.

## Commit & push

```bash
git add -A
git commit -m "<what changed>"
git push origin main
```

There is no build or test suite beyond the smoke test above. Prefer small,
verifiable changes.
