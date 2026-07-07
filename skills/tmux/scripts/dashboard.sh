#!/usr/bin/env bash
# dashboard.sh — multi-pane monitoring for the agent socket.
#
# Runs classify-pane.sh over EVERY pane (of one session, or the whole socket)
# and prints one compact table row per pane: target, title, state, last line.
# It's the many-panes generalization of a single `tm.sh classify`.
#
# States and their priority match classify-pane.sh:
#   needs-human > stuck > complete > running
#
# Exit code = the highest-priority state seen across all panes, so it composes
# in a watch loop:
#   1 needs-human · 2 stuck · 3 complete · 0 all running (or no panes)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: dashboard.sh [-L socket-name|-S socket-path] [-s session] [-l lines]

Classify every pane on an agent socket and print a status table.

Options:
  -L, --socket-name  tmux socket name (passed to tmux -L)
  -S, --socket       tmux socket path (passed to tmux -S)
  -s, --session      limit to one session (default: all sessions on the socket)
  -l, --lines        pane history lines to inspect per pane (default: 80)
  -h, --help         show this help

Exit: 1 needs-human · 2 stuck · 3 complete · 0 running/empty
USAGE
}

socket_name=""; socket_path=""; session=""; lines=80
while [[ $# -gt 0 ]]; do
  case "$1" in
    -L|--socket-name) socket_name="${2-}"; shift 2 ;;
    -S|--socket)      socket_path="${2-}"; shift 2 ;;
    -s|--session)     session="${2-}"; shift 2 ;;
    -l|--lines)       lines="${2-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done
[[ "$lines" =~ ^[0-9]+$ ]] || { echo "lines must be an integer" >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "tmux not found in PATH" >&2; exit 1; }

tmux_cmd=(tmux)
[[ -n "$socket_name" ]] && tmux_cmd+=(-L "$socket_name")
[[ -n "$socket_path" ]] && tmux_cmd+=(-S "$socket_path")

# List targets + titles: "session:win.pane<TAB>title"
list_args=(list-panes -a -F $'#{session_name}:#{window_index}.#{pane_index}\t#{pane_title}')
[[ -n "$session" ]] && list_args=(list-panes -s -t "$session" \
  -F $'#{session_name}:#{window_index}.#{pane_index}\t#{pane_title}')

panes="$("${tmux_cmd[@]}" "${list_args[@]}" 2>/dev/null || true)"
if [[ -z "$panes" ]]; then
  echo "No panes found${session:+ in session '$session'}."
  exit 0
fi

printf '%-22s %-8s %-14s %s\n' "TARGET" "STATE" "TITLE" "LAST LINE"
printf '%-22s %-8s %-14s %s\n' "------" "-----" "-----" "---------"

worst=0   # 0 running · 3 complete · 2 stuck · 1 needs-human, ranked below
rank() { case "$1" in needs-human) echo 3 ;; stuck) echo 2 ;; complete) echo 1 ;; *) echo 0 ;; esac; }
worst_rank=0

while IFS=$'\t' read -r tgt title; do
  [[ -z "$tgt" ]] && continue
  # classify-pane.sh encodes state in BOTH stdout and its exit code (0 running ·
  # 1 needs-human · 2 stuck · 3 complete). Neutralize the non-zero exit with
  # `|| true` BEFORE cut, so `pipefail` doesn't make the pipeline "fail" and
  # corrupt $state. Read the state word from stdout only.
  raw="$("$HERE/classify-pane.sh" -t "$tgt" ${socket_name:+-L "$socket_name"} \
    ${socket_path:+-S "$socket_path"} -l "$lines" -q 2>/dev/null || true)"
  state="$(printf '%s' "$raw" | cut -f1)"
  [[ -n "$state" ]] || state=running
  last="$("${tmux_cmd[@]}" capture-pane -p -J -t "$tgt" -S -0 2>/dev/null \
    | grep -v '^[[:space:]]*$' | tail -1 || true)"
  printf '%-22s %-8s %-14s %s\n' "$tgt" "$state" "${title:0:14}" "${last:0:60}"
  r="$(rank "$state")"
  if (( r > worst_rank )); then worst_rank="$r"; fi
done <<< "$panes"

case "$worst_rank" in
  3) exit 1 ;;  # needs-human
  2) exit 2 ;;  # stuck
  1) exit 3 ;;  # complete
  *) exit 0 ;;  # running
esac
