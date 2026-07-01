#!/usr/bin/env bash
# tm.sh — thin wrapper over tmux on a private agent socket.
# Handles the socket + common actions so you don't retype boilerplate.
#
#   Socket dir: $AGENT_TMUX_SOCKET_DIR (default ${TMPDIR:-/tmp}/agent-tmux-sockets)
#   Socket:     $AGENT_TMUX_SOCKET      (default <dir>/agent.sock)
#   Default target pane: <session>:0.0
#   Working dir for new sessions: $TM_CWD (default: current $PWD)
#
# Usage:
#   tm.sh start   <session> [--cwd DIR] [initial-command]   # create detached session
#                                                 # dir: --cwd > $TM_CWD > current $PWD
#   tm.sh send    <session> <text...>             # type text (literal) + Enter
#   tm.sh type    <session> <text...>             # type text (literal), NO Enter
#   tm.sh key     <session> <key...>              # send raw keys (C-c, Enter, Escape, ...)
#   tm.sh run     <session> <command...>          # send a full command line + Enter
#   tm.sh wait    <session> <regex> [timeout]     # wait for regex in pane (default 15s)
#   tm.sh peek    <session> [lines]               # print last N lines (default 50)
#   tm.sh list                                    # list sessions on the socket
#   tm.sh attach-cmd <session>                    # print the copy/paste attach command
#   tm.sh kill    <session>                        # kill one session
#   tm.sh kill-all                                # kill the whole socket server
#   tm.sh doctor                                  # read-only health check (safe)
#
# Every session/target defaults to window 0, pane 0. Names should be slugs.
set -euo pipefail

_TMP="${TMPDIR:-/tmp}"; _TMP="${_TMP%/}"   # strip trailing slash so paths don't get //
SOCKET_DIR="${AGENT_TMUX_SOCKET_DIR:-$_TMP/agent-tmux-sockets}"
CWD="${TM_CWD:-$PWD}"                       # new sessions start here (the project dir)
SOCKET="${AGENT_TMUX_SOCKET:-$SOCKET_DIR/agent.sock}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$SOCKET_DIR"
command -v tmux >/dev/null 2>&1 || { echo "tmux not found in PATH" >&2; exit 1; }

t() { tmux -S "$SOCKET" "$@"; }
target() { printf '%s:0.0' "$1"; }

attach_cmd() {
  local s="$1"
  cat <<EOF
To watch this session live:
  tmux -S "$SOCKET" attach -t $s      (detach with Ctrl+b d)
Or capture output once:
  tmux -S "$SOCKET" capture-pane -p -J -t $s:0.0 -S -200
EOF
}

cmd="${1-}"; shift || true
case "$cmd" in
  start)
    s="${1:?session name required}"; shift || true
    if [[ "${1-}" == "--cwd" || "${1-}" == "-C" ]]; then CWD="${2:?dir required after --cwd}"; shift 2; fi
    [[ -d "$CWD" ]] || { echo "cwd not a directory: $CWD" >&2; exit 1; }
    t has-session -t "$s" 2>/dev/null || t new -d -s "$s" -c "$CWD" -n shell
    if [[ $# -gt 0 ]]; then t send-keys -t "$(target "$s")" -- "$*" Enter; fi
    echo "cwd: $CWD"
    attach_cmd "$s"
    ;;
  send)
    s="${1:?session}"; shift
    t send-keys -t "$(target "$s")" -l -- "$*"
    sleep 0.1
    t send-keys -t "$(target "$s")" Enter
    ;;
  type)
    s="${1:?session}"; shift
    t send-keys -t "$(target "$s")" -l -- "$*"
    ;;
  key)
    s="${1:?session}"; shift
    t send-keys -t "$(target "$s")" "$@"
    ;;
  run)
    s="${1:?session}"; shift
    t send-keys -t "$(target "$s")" -- "$*" Enter
    ;;
  wait)
    s="${1:?session}"; pat="${2:?regex}"; to="${3:-15}"
    "$HERE/wait-for-text.sh" -t "$(target "$s")" -p "$pat" -S "$SOCKET" -T "$to"
    ;;
  peek)
    s="${1:?session}"; n="${2:-50}"
    t capture-pane -p -J -t "$(target "$s")" -S "-${n}"
    ;;
  list)
    "$HERE/find-sessions.sh" -S "$SOCKET"
    ;;
  attach-cmd)
    attach_cmd "${1:?session}"
    ;;
  kill)
    t kill-session -t "${1:?session}"
    ;;
  kill-all)
    t kill-server 2>/dev/null || true
    ;;
  doctor)
    # Read-only preflight. No focus stealing, no attach, no secrets.
    echo "tmux:        $(command -v tmux || echo 'NOT FOUND') ($(tmux -V 2>/dev/null || echo '?'))"
    echo "socket dir:  $SOCKET_DIR $([[ -d $SOCKET_DIR ]] && echo '(exists)' || echo '(missing)')"
    if t list-sessions >/dev/null 2>&1; then
      echo "socket:      $SOCKET (live)"
      echo "sessions:"; "$HERE/find-sessions.sh" -S "$SOCKET" | sed 's/^/  /'
    else
      echo "socket:      $SOCKET (no running server)"
    fi
    if [[ -d $SOCKET_DIR ]]; then
      other=$(find "$SOCKET_DIR" -type s ! -name "$(basename "$SOCKET")" 2>/dev/null)
      [[ -n $other ]] && { echo "other agent sockets:"; echo "$other" | sed 's/^/  /'; }
    fi
    ;;
  *)
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
