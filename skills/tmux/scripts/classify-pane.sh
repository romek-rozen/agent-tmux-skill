#!/usr/bin/env bash
# classify-pane.sh — watchdog: classify what a tmux pane is DOING right now.
#
# `idle`/wait-for-idle tells you a pane went quiet; this tells you WHY it is
# quiet — is it waiting for a confirmation, begging for a secret, crashed, or
# just done? It greps the visible pane for known stuck/needs-human signatures
# and prints a one-word state plus the evidence lines.
#
# States (printed on stdout as: "STATE\t<session/target>"):
#   needs-human   confirmation prompt, credential/secret request, or explicit
#                 "waiting for input" — a HUMAN (or policy) must decide. NEVER
#                 auto-answer credential/secret prompts (see SKILL.md guardrail).
#   stuck         error/traceback/repeated-failure signature on screen
#   complete      a done/exit/finished marker on screen
#   running       none of the above (assume still working)
#
# Exit code mirrors the state so it composes in scripts:
#   0 running · 1 needs-human · 2 stuck · 3 complete
#
# For deterministic prompts prefer wait-for-text.sh; to detect quiescence
# prefer wait-for-idle.sh. Use this to TRIAGE a pane (esp. an agent TUI) once
# it has gone idle: `tm.sh idle w-foo && tm.sh classify w-foo`.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: classify-pane.sh -t target [options]

Classify a tmux pane's current state from its visible output.

Options:
  -t, --target       tmux target (session:window.pane), required
  -S, --socket       tmux socket path (passed to tmux -S), optional
  -L, --socket-name  tmux socket name (passed to tmux -L), optional
  -l, --lines        pane history lines to inspect (default: 80)
  -q, --quiet        print only the state word, no evidence lines
  -h, --help         show this help

Output: "<state>\t<target>" then indented evidence lines (unless --quiet).
Exit:   0 running · 1 needs-human · 2 stuck · 3 complete
USAGE
}

target=""; socket=""; socket_name=""; lines=80; quiet=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)      target="${2-}"; shift 2 ;;
    -S|--socket)      socket="${2-}"; shift 2 ;;
    -L|--socket-name) socket_name="${2-}"; shift 2 ;;
    -l|--lines)       lines="${2-}"; shift 2 ;;
    -q|--quiet)       quiet=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$target" ]] || { echo "target is required" >&2; usage; exit 1; }
[[ "$lines" =~ ^[0-9]+$ ]] || { echo "lines must be an integer" >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "tmux not found in PATH" >&2; exit 1; }

tmux_cmd=(tmux)
[[ -n "$socket" ]] && tmux_cmd+=(-S "$socket")
[[ -n "$socket_name" ]] && tmux_cmd+=(-L "$socket_name")

pane="$("${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S "-${lines}" 2>/dev/null)" \
  || { echo "cannot capture pane: $target" >&2; exit 1; }

# Signature sets. Order matters: needs-human (secrets first) > stuck > complete.
# Patterns are case-insensitive extended regex; keep them conservative to avoid
# false positives on ordinary log lines.
SECRET_RE='password[: ]|passphrase|enter.*(token|api[ _-]?key|secret)|authenticat|2fa|one[- ]time code'
CONFIRM_RE='\[y/n\]|\(y/n\)|\(yes/no\)|\[yes/no\]|proceed\?|continue\?|are you sure|overwrite\?|press enter to'
WAIT_RE='waiting for (your )?input|awaiting.*(input|response|instruction)|what should i do|how would you like'
STUCK_RE='traceback \(most recent|^error:|fatal:|segmentation fault|panic:|unhandled exception|command not found|no such file or directory|permission denied|address already in use'
DONE_RE='✓ done|^done\.?$|build succeeded|tests? passed|all checks passed|process exited|program exited|completed successfully|finished'

evidence() {
  [[ "$quiet" == 1 ]] && return 0
  printf '%s' "$pane" | grep -iE "$1" | tail -4 | sed 's/^/    /'
}

if printf '%s' "$pane" | grep -iqE "$SECRET_RE"; then
  printf 'needs-human\t%s\n' "$target"; evidence "$SECRET_RE"; exit 1
elif printf '%s' "$pane" | grep -iqE "$CONFIRM_RE"; then
  printf 'needs-human\t%s\n' "$target"; evidence "$CONFIRM_RE"; exit 1
elif printf '%s' "$pane" | grep -iqE "$WAIT_RE"; then
  printf 'needs-human\t%s\n' "$target"; evidence "$WAIT_RE"; exit 1
elif printf '%s' "$pane" | grep -iqE "$STUCK_RE"; then
  printf 'stuck\t%s\n' "$target"; evidence "$STUCK_RE"; exit 2
elif printf '%s' "$pane" | grep -iqE "$DONE_RE"; then
  printf 'complete\t%s\n' "$target"; evidence "$DONE_RE"; exit 3
else
  printf 'running\t%s\n' "$target"; exit 0
fi
