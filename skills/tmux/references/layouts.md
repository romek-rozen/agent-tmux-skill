# tmux layout presets & workspace file format

## Layout presets

Applied with `tm.sh layout <session> <preset>`. Each preset splits the session's
current window and then applies a native tmux layout, so it works regardless of
the starting geometry. Panes are created in the session's current dir.

| Preset  | Panes | Shape | Intended use |
|---------|-------|-------|--------------|
| `dev`   | 3     | `main-vertical` — one big pane on the left, two stacked on the right | editor (left) + logs + shell |
| `2x2`   | 4     | `tiled` — four equal quadrants | four parallel jobs / dashboards |
| `watch` | 4     | `main-horizontal` — one wide pane on top, a strip of three below | one primary process + several watchers |

After applying a preset, address panes by index to start work in each:

```bash
tm.sh layout dev dev
tm.sh run dev:0.0 'nvim .'            # left / main pane
tm.sh run dev:0.1 'tail -f app.log'  # top-right
tm.sh run dev:0.2 'bash'             # bottom-right
```

Pane indices come from creation order; confirm them any time with `tm.sh tree dev`.

## Workspace file format

`tm.sh save <session> <file>` writes a plain text file: a comment header naming
the session, then one tab-separated record per pane.

```
# tmux workspace — session: dev
0<TAB>0<TAB>/home/me/proj<TAB>nvim
0<TAB>1<TAB>/home/me/proj<TAB>tail
0<TAB>2<TAB>/home/me/proj<TAB>bash
```

Columns: `window_index`, `pane_index`, `pane_current_path` (cwd),
`pane_current_command` (the process running when saved — informational only).

`tm.sh restore <file> [session]` recreates the windows and panes with their
saved cwds (new panes per window are evened out with the `tiled` layout). If the
session name is omitted, it is read from the header comment. The target session
must not already exist.

By design, `restore` does **not** re-launch the saved commands — starting
processes is left explicit so nothing runs unexpectedly on restore. Re-issue the
commands yourself with `tm.sh run <target> '<cmd>'` afterwards.
