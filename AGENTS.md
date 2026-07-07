# AGENTS.md

Guidance for AI coding agents (pi, Claude Code, Codex, OpenCode) working in or
deploying this repository. Humans: see [GUIDE.md](GUIDE.md) and [README.md](README.md).

## What this repo is

A single, portable **Agent Skill** (`skills/tmux/`) that teaches an agent to
drive interactive terminal programs through tmux. It is shell-only
(`bash` + `tmux` + `grep`) and follows the common "Agent Skills" format (a
`SKILL.md` directory convention), so the same directory works across harnesses.

Source of truth for the skill is `skills/tmux/`. Everything else is docs.

## Repo layout

```
AGENTS.md                        # this file
GUIDE.md                         # human beginner guide
README.md                        # overview + install + credits
LICENSE                          # Apache-2.0
skills/tmux/
├── SKILL.md                     # the skill (agent instructions)  <-- source of truth
├── GOTCHAS.md                   # non-obvious behaviors and edge cases
├── references/
│   ├── tmux-config.md           # ~/.tmux.conf for running agents inside tmux
│   └── layouts.md               # layout presets (dev/2x2/watch) + workspace file format
└── scripts/
    ├── tm.sh                    # wrapper: core (start/send/type/key/run/wait/idle/classify/peek/list/attach-cmd/kill/kill-all/doctor) + pane/window mgmt (split/window/select/zoom/rename/resize/tree) + layouts (layout/save/restore) + dashboard
    ├── wait-for-text.sh         # poll a pane for a regex until match or timeout
    ├── wait-for-idle.sh         # wait until a pane stops changing (TUIs/live agents)
    ├── classify-pane.sh         # watchdog triage: running/needs-human/stuck/complete
    ├── dashboard.sh             # classify every pane into one status table (exit = worst state)
    └── find-sessions.sh         # list sessions with metadata across agent sockets
```

## Core design rules (do not break these)

1. **Named private socket.** All agent sessions run on a named tmux socket
   `$AGENT_TMUX_SOCKET` (default `agent`) via `tmux -L "$SOCKET"`. This isolates
   agent sessions from the user's default tmux (cleanup safe: `kill-server` only
   affects agent sessions) while staying trivial to attach:
   `tmux -L agent attach -t <session>` — no long socket path to paste.
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
6. **Deterministic single-pane, opt-in multi-pane.** A bare `<session>` target
   still resolves to `:0.0` (unchanged behavior); the pane/window manager and
   layouts are additive. Address extra panes explicitly as `<session>:win.pane`.
7. **State lives in exit codes AND stdout.** `classify-pane.sh` signals state
   both ways (`0 running · 1 needs-human · 2 stuck · 3 complete`). Any consumer
   under `set -o pipefail` (e.g. `dashboard.sh`) MUST neutralize the non-zero
   exit with `|| true` before piping, then read the state word from stdout —
   otherwise the failing pipeline corrupts the result and swallows non-running
   states. Read state from stdout; use the exit code only for direct branching.

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
- Keep the `license: Apache-2.0` frontmatter in `SKILL.md` consistent with `LICENSE`.
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
