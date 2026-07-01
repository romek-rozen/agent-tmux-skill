#!/usr/bin/env bash
# wait-for-idle.sh — wait until a tmux pane's output goes QUIET (stops changing).
#
# Use this for TUIs / live agents (Claude Code, Codex, installers with spinners)
# where there is no single stable "ready" string to match. It detects
# quiescence: the visible pane content is unchanged for `--stable` seconds.
#
# For deterministic prompts (python >>>, shell $, gdb) prefer wait-for-text.sh.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: wait-for-idle.sh -t target [options]

Wait until a tmux pane stops changing (goes idle), or until timeout.

Options:
  -t, --target       tmux target (session:window.pane), required
  -S, --socket       tmux socket path (passed to tmux -S), optional
  -L, --socket-name  tmux socket name (passed to tmux -L), optional
  -s, --stable       seconds of no change to call it idle (default: 3)
  -T, --timeout      max seconds to wait overall (default: 60)
  -i, --interval     poll interval in seconds (default: 0.5)
  -l, --lines        pane history lines to hash (default: 200)
  -h, --help         show this help

Exit: 0 when idle for --stable seconds; 1 on overall timeout.
USAGE
}

target=""; socket=""; socket_name=""
stable=3; timeout=60; interval=0.5; lines=200

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)      target="${2-}"; shift 2 ;;
    -S|--socket)      socket="${2-}"; shift 2 ;;
    -L|--socket-name) socket_name="${2-}"; shift 2 ;;
    -s|--stable)      stable="${2-}"; shift 2 ;;
    -T|--timeout)     timeout="${2-}"; shift 2 ;;
    -i|--interval)    interval="${2-}"; shift 2 ;;
    -l|--lines)       lines="${2-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$target" ]] || { echo "target is required" >&2; usage; exit 1; }
for n in stable timeout lines; do
  v="${!n}"; [[ "$v" =~ ^[0-9]+$ ]] || { echo "$n must be an integer" >&2; exit 1; }
done
command -v tmux >/dev/null 2>&1 || { echo "tmux not found in PATH" >&2; exit 1; }

tmux_cmd=(tmux)
[[ -n "$socket" ]] && tmux_cmd+=(-S "$socket")
[[ -n "$socket_name" ]] && tmux_cmd+=(-L "$socket_name")

snapshot() { "${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S "-${lines}" 2>/dev/null | cksum; }

start=$(date +%s)
deadline=$((start + timeout))
last="$(snapshot)"
last_change=$(date +%s)

while true; do
  sleep "$interval"
  now=$(date +%s)
  cur="$(snapshot)"

  if [[ "$cur" != "$last" ]]; then
    last="$cur"; last_change=$now
  elif (( now - last_change >= stable )); then
    exit 0                          # unchanged long enough → idle
  fi

  if (( now >= deadline )); then
    echo "Timed out after ${timeout}s; pane still changing (never idle for ${stable}s)." >&2
    echo "Last 40 lines from $target:" >&2
    "${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S "-${lines}" 2>/dev/null | tail -40 >&2
    exit 1
  fi
done
