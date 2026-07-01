# tmux configuration for running coding agents inside tmux

This is only needed when a **human runs a coding agent (Claude Code, pi, Codex)
inside a tmux pane** — i.e. your normal interactive tmux, `~/.tmux.conf`.

It is **separate** from this skill's automation: the skill drives programs on a
private socket and never attaches, so it is unaffected. But if you (or the skill)
run an interactive agent inside tmux, tmux strips modifier keys by default and
`Shift+Enter` / `Ctrl+Enter` collapse to plain `Enter`. Two things break:

- **Newline shortcuts** — `Shift+Enter` submits instead of inserting a newline.
- **Notifications / progress bar** (Claude Code) never reach the outer terminal.

## Recommended `~/.tmux.conf` (works for both Claude Code and pi)

```tmux
set -g allow-passthrough on                       # let notifications/progress pass through (Claude Code)
set -g extended-keys on                           # tmux distinguishes modified keys
set -g extended-keys-format csi-u                 # forward modified keys in CSI-u form (pi's preferred)
set -as terminal-features 'xterm*:extkeys'        # advertise extended keys to apps (Claude Code)
```

Apply without restarting:

```bash
tmux source-file ~/.tmux.conf
```

If key handling still misbehaves, restart the server fully:

```bash
tmux kill-server && tmux
```

## Requirements & version notes

- `extended-keys-format csi-u` requires **tmux 3.5+** (`tmux -V` to check).
- On **tmux 3.2–3.4**, omit the `extended-keys-format csi-u` line; agents still
  work with tmux's default `xterm` modifyOtherKeys format.
- Terminal emulator must support extended keys: Ghostty, Kitty, iTerm2, WezTerm,
  Windows Terminal.

## What each line does

| Line | Fixes |
|------|-------|
| `allow-passthrough on` | Desktop notifications and the progress bar reach the outer terminal instead of being swallowed by tmux (Claude Code). |
| `extended-keys on` | tmux tells modified keys apart from plain ones (e.g. `Shift+Enter` vs `Enter`). |
| `extended-keys-format csi-u` | Modified keys forwarded as `\x1b[13;2u` (CSI-u), the most reliable form; pi's recommended setting. |
| `terminal-features 'xterm*:extkeys'` | Advertises extended-key capability to applications (Claude Code). |

## csi-u vs xterm format (why csi-u)

With only `extended-keys on`, tmux defaults to `extended-keys-format xterm`
(modifyOtherKeys), e.g. `Ctrl+Enter → \x1b[27;5;13~`. With `csi-u` the same key
is `\x1b[13;5u`. Both are supported by pi, but `csi-u` is the recommended,
most reliable setup.
