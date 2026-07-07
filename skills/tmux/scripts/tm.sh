#!/usr/bin/env bash
# tm.sh — thin wrapper over tmux on a private, named agent socket, with a
# pane/window MANAGER on top: splits, windows, layouts, workspace save/restore,
# and a multi-pane monitoring dashboard.
#
#   Socket name: $AGENT_TMUX_SOCKET (default "agent"), used as tmux -L <name>.
#     Isolated from the user's default tmux, but easy to attach:
#       tmux -L agent attach -t <session>
#   Target form: <session>[:window[.pane]]. A bare <session> defaults to
#     window 0, pane 0 (deterministic). Address other panes as <session>:0.1.
#   Working dir for new sessions: $TM_CWD (default: current $PWD)
#
# Core actions:
#   tm.sh start   <session> [--cwd DIR] [initial-command]   # create detached session
#                                                 # dir: --cwd > $TM_CWD > current $PWD
#   tm.sh send    <target> <text...>              # type text (literal) + Enter
#   tm.sh type    <target> <text...>              # type text (literal), NO Enter
#   tm.sh key     <target> <key...>               # send raw keys (C-c, Enter, Escape, ...)
#   tm.sh run     <target> <command...>           # send a full command line + Enter
#   tm.sh wait    <target> <regex> [timeout]      # wait for regex in pane (default 15s)
#   tm.sh idle    <target> [stable] [timeout]     # wait until pane stops changing (TUIs/agents)
#   tm.sh classify <target> [lines]               # triage: running/needs-human/stuck/complete
#   tm.sh peek    <target> [lines]                # print last N lines (default 50)
#   tm.sh list                                    # list sessions on the socket
#   tm.sh attach-cmd <session>                    # print the copy/paste attach command
#   tm.sh kill    <session>                        # kill one session
#   tm.sh kill-all                                # kill only sessions this skill created
#   tm.sh doctor                                  # read-only health check (safe)
#
# Pane/window manager:
#   tm.sh split   <target> [-h|-v] [command]      # split a pane (-h side-by-side, -v stacked)
#   tm.sh window  <session> <name> [command]      # open a new window
#   tm.sh select  <target>                        # focus a pane/window
#   tm.sh zoom    <target>                         # toggle pane zoom (fullscreen)
#   tm.sh rename  <target> <name>                 # rename window (or set pane title)
#   tm.sh resize  <target> <-L|-R|-U|-D> <N>      # grow/shrink a pane by N cells
#   tm.sh tree    [session]                       # tree of windows/panes with running cmd
#
# Layouts & workspaces:
#   tm.sh layout  <session> <preset>              # apply a preset (dev|2x2|watch)
#   tm.sh save    <session> <file>                # serialize the layout to a workspace file
#   tm.sh restore <file> [session]                # rebuild a session from a workspace file
#
# Monitoring:
#   tm.sh dashboard [session]                     # classify every pane at once (table)
#
# Names should be slugs (no spaces).
set -euo pipefail

SOCKET="${AGENT_TMUX_SOCKET:-agent}"        # tmux -L <name>: private, but easy to attach
CWD="${TM_CWD:-$PWD}"                       # new sessions start here (the project dir)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v tmux >/dev/null 2>&1 || { echo "tmux not found in PATH" >&2; exit 1; }

t() { tmux -L "$SOCKET" "$@"; }
# A bare session name defaults to window 0, pane 0 (deterministic single-pane
# behavior). A target that already names a window/pane (contains ':' or '.') is
# used verbatim, so multi-pane sessions can be addressed as <session>:<win>.<pane>.
target() { case "$1" in *[:.]*) printf '%s' "$1" ;; *) printf '%s:0.0' "$1" ;; esac; }

# Apply a named layout preset: splits + a native tmux layout, so it works no
# matter the current geometry. See references/layouts.md for descriptions.
apply_preset() {
  local s="$1" preset="$2"
  t has-session -t "$s" 2>/dev/null || { echo "no such session: $s" >&2; exit 1; }
  # New panes inherit the session's current dir, not the wrapper's $PWD.
  local pcwd; pcwd="$(t display-message -p -t "$s" '#{pane_current_path}')"
  case "$preset" in
    dev)     # editor (big, left) + logs + shell stacked on the right
      t split-window -h -t "$s" -c "$pcwd"
      t split-window -v -t "$s" -c "$pcwd"
      t select-layout -t "$s" main-vertical
      t select-pane   -t "$s".0 ;;
    2x2)     # four equal tiles
      t split-window -h -t "$s" -c "$pcwd"
      t split-window -v -t "$s" -c "$pcwd"
      t split-window -v -t "$s" -c "$pcwd"
      t select-layout -t "$s" tiled ;;
    watch)   # one big pane on top, a strip of small ones below
      t split-window -v -t "$s" -c "$pcwd"
      t split-window -h -t "$s" -c "$pcwd"
      t split-window -h -t "$s" -c "$pcwd"
      t select-layout -t "$s" main-horizontal ;;
    *) echo "unknown preset: $preset (dev|2x2|watch)" >&2; exit 1 ;;
  esac
}

attach_cmd() {
  local s="$1"
  cat <<EOF
To watch this session live:
  tmux -L $SOCKET attach -t $s      (detach with Ctrl+b d)
Or capture output once:
  tmux -L $SOCKET capture-pane -p -J -t $s:0.0 -S -200
EOF
}

cmd="${1-}"; shift || true
case "$cmd" in
  start)
    s="${1:?session name required}"; shift || true
    if [[ "${1-}" == "--cwd" || "${1-}" == "-C" ]]; then CWD="${2:?dir required after --cwd}"; shift 2; fi
    [[ -d "$CWD" ]] || { echo "cwd not a directory: $CWD" >&2; exit 1; }
    if ! t has-session -t "$s" 2>/dev/null; then
      t new -d -s "$s" -c "$CWD" -n shell
      t set-option -t "$s" @agent_owned 1        # mark ours, so kill-all spares user sessions
    fi
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
    "$HERE/wait-for-text.sh" -t "$(target "$s")" -p "$pat" -L "$SOCKET" -T "$to"
    ;;
  idle)
    s="${1:?session}"; st="${2:-3}"; to="${3:-60}"
    "$HERE/wait-for-idle.sh" -t "$(target "$s")" -L "$SOCKET" -s "$st" -T "$to"
    ;;
  classify)
    s="${1:?session}"; n="${2:-80}"
    # Exit code mirrors state (0 running·1 needs-human·2 stuck·3 complete); don't let set -e abort.
    "$HERE/classify-pane.sh" -t "$(target "$s")" -L "$SOCKET" -l "$n" || true
    ;;
  peek)
    s="${1:?session}"; n="${2:-50}"
    t capture-pane -p -J -t "$(target "$s")" -S "-${n}"
    ;;
  list)
    "$HERE/find-sessions.sh" -L "$SOCKET"
    ;;
  attach-cmd)
    attach_cmd "${1:?session}"
    ;;
  kill)
    t kill-session -t "${1:?session}"
    ;;
  kill-all)
    # Only kill sessions THIS skill created (tagged @agent_owned). Never touch
    # sessions the user started by hand on the same socket. (The tmux server
    # exits on its own once no sessions remain.)
    t list-sessions >/dev/null 2>&1 || exit 0
    killed=0
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      if [[ "$(t show-options -qv -t "$s" @agent_owned 2>/dev/null)" == "1" ]]; then
        t kill-session -t "$s" 2>/dev/null && killed=$((killed+1))
      fi
    done < <(t list-sessions -F '#{session_name}' 2>/dev/null)
    echo "killed $killed owned session(s); left any others intact"
    ;;
  doctor)
    # Read-only preflight. No focus stealing, no attach, no secrets.
    echo "tmux:         $(command -v tmux || echo 'NOT FOUND') ($(tmux -V 2>/dev/null || echo '?'))"
    echo "socket name:  $SOCKET  (attach: tmux -L $SOCKET attach -t <session>)"
    if t list-sessions >/dev/null 2>&1; then
      echo "server:       live"
      echo "sessions:"; "$HERE/find-sessions.sh" -L "$SOCKET" | sed 's/^/  /'
    else
      echo "server:       no running server yet"
    fi
    ;;
  # ---- pane/window manager ----
  split)
    tgt="${1:?target}"; shift || true
    dir="-v"                                   # default: stacked
    if [[ "${1-}" == "-h" || "${1-}" == "-v" ]]; then dir="$1"; shift; fi
    if [[ $# -gt 0 ]]; then
      t split-window "$dir" -t "$(target "$tgt")" -c "$CWD" -- "$*"
    else
      t split-window "$dir" -t "$(target "$tgt")" -c "$CWD"
    fi
    t display-message -p -t "$(target "$tgt")" 'panes now: #{window_panes}'
    ;;
  window)
    s="${1:?session}"; name="${2:?window name}"; shift 2 || true
    if [[ $# -gt 0 ]]; then
      t new-window -t "$s" -n "$name" -c "$CWD" -- "$*"
    else
      t new-window -t "$s" -n "$name" -c "$CWD"
    fi
    ;;
  select)
    tgt="${1:?target}"
    # A dotted target names a pane; otherwise treat it as a window.
    if [[ "$tgt" == *.* ]]; then t select-pane -t "$tgt"; else t select-window -t "$tgt"; fi
    ;;
  zoom)
    tgt="${1:?target}"
    t resize-pane -Z -t "$tgt"
    ;;
  rename)
    tgt="${1:?target}"; name="${2:?new name}"
    if [[ "$tgt" == *.* ]]; then t select-pane -t "$tgt" -T "$name"; else t rename-window -t "$tgt" "$name"; fi
    ;;
  resize)
    tgt="${1:?target}"; d="${2:?direction -L|-R|-U|-D}"; n="${3:?cells}"
    case "$d" in -L|-R|-U|-D) ;; *) echo "direction must be -L|-R|-U|-D" >&2; exit 1 ;; esac
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "cells must be an integer" >&2; exit 1; }
    t resize-pane -t "$tgt" "$d" "$n"
    ;;
  tree)
    s="${1-}"
    if [[ -n "$s" ]]; then
      t list-panes -s -t "$s" -F '#{window_index}.#{pane_index} #{?pane_active,*, } #{pane_title} [#{pane_current_command}] #{pane_current_path}'
    else
      t list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{?pane_active,*, } #{pane_title} [#{pane_current_command}] #{pane_current_path}'
    fi
    ;;

  # ---- layouts & workspaces ----
  layout)
    s="${1:?session}"; preset="${2:?preset (dev|2x2|watch)}"
    apply_preset "$s" "$preset"
    echo "applied '$preset' to $s"
    ;;
  save)
    s="${1:?session}"; file="${2:?output file}"
    t has-session -t "$s" 2>/dev/null || { echo "no such session: $s" >&2; exit 1; }
    {
      echo "# tmux workspace — session: $s"
      # One record per pane: window<TAB>pane<TAB>cwd<TAB>running-command
      t list-panes -s -t "$s" \
        -F $'#{window_index}\t#{pane_index}\t#{pane_current_path}\t#{pane_current_command}'
    } > "$file"
    echo "saved $(grep -vc '^#' "$file") pane(s) to $file"
    ;;
  restore)
    file="${1:?workspace file}"; s="${2-}"
    [[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }
    [[ -n "$s" ]] || s="$(sed -n 's/^# tmux workspace — session: //p' "$file" | head -1)"
    [[ -n "$s" ]] || { echo "session name required (not found in file)" >&2; exit 1; }
    t has-session -t "$s" 2>/dev/null && { echo "session '$s' already exists — kill it first" >&2; exit 1; }
    prev_win=""
    first=1
    while IFS=$'\t' read -r win pane cwd cmdname; do
      [[ "$win" == \#* || -z "$win" ]] && continue
      [[ -d "$cwd" ]] || cwd="$CWD"
      if [[ $first == 1 ]]; then
        t new -d -s "$s" -c "$cwd"; t set-option -t "$s" @agent_owned 1; prev_win="$win"; first=0
      elif [[ "$win" != "$prev_win" ]]; then
        t new-window -t "$s" -c "$cwd"; prev_win="$win"
      else
        t split-window -t "$s:$win" -c "$cwd"
      fi
    done < "$file"
    # Even out each window's panes.
    for w in $(t list-windows -t "$s" -F '#{window_index}'); do
      t select-layout -t "$s:$w" tiled
    done
    echo "restored session '$s' from $file"
    attach_cmd "$s"
    ;;

  # ---- monitoring ----
  dashboard)
    s="${1-}"
    "$HERE/dashboard.sh" -L "$SOCKET" ${s:+-s "$s"} || exit $?
    ;;

  *)
    awk 'NR>=2 && /^#/{sub(/^# ?/,""); print; next} NR>=2{exit}' "${BASH_SOURCE[0]}"
    exit 1
    ;;
esac
