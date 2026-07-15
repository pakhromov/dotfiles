# my-rules + open

Personal window management for Wayfire, replacing the stock `window-rules`
plugin and the launcher scripts previously used (`launch-or-focus.sh`,
`launch-and-assign.py`, `keep-focused-launch.py`). Two components with a
strict division of responsibility:

1. **`open`** (`src/client/open.c`) — a dependency-free C launcher binary used
   from `[command]` keybinds. Handles everything that must happen **before** a
   program is started: the single-instance check ("is it already running? then
   focus it") and switching to the target workspace so the app maps there.
2. **`my-rules`** (`src/my-rules.cpp`) — a purely reactive plugin. Handles
   windows that appear **without** `open` (spawned by file managers, other
   apps, plain commands): workspace assignment + focus, geometry, keep-focused
   marking. It has **no keybinds, no timers, no polling, no launching** — hard
   requirements.

## Why this design (the reasoning, so it doesn't get re-litigated)

- **A compositor plugin only ever sees a window after the app created it.**
  There is no Wayland "may I open a window?" protocol, and the `command`
  plugin blindly fork/execs. Therefore "focus instead of launching" *must*
  live in a launcher; it cannot be a reactive rule. The reactive alternative
  (let the duplicate map, then close it and focus the old one) was considered
  and **explicitly rejected** as a hack (it also breaks Firefox
  Picture-in-Picture and file-open windows).
- **Firefox private windows set their title ("... Private Browsing") a few
  hundred ms after mapping**, so map-time rules can't distinguish private from
  regular. Stock window-rules only evaluates at map → hence the old scripts.
  `open` sidesteps the problem completely: it never classifies *new* windows.
  It matches *existing* windows (whose titles are settled) before launching,
  and places new windows by switching the workspace *first* and letting the
  app map there naturally.
- **Rules must not be tied to keybinds.** Keybinds stay in `[command]` and run
  `open ...` or plain commands. The plugin never registers bindings.
- `kitty-launch-or-focus.sh` is **intentionally not replaced** — it manages
  tabs inside a single kitty instance via kitty remote control, which the
  compositor cannot see.

## The `open` binary

```
open [-w RC] [--single-app-id V | --single-title V] [--exclude-title V] [-e] <command> [args...]
```

| Flag | Meaning |
|---|---|
| `-w RC` | Target workspace, two digits, 1-based: **first digit = row (y), second = column (x)**. `12` = row 1, column 2. Works for any grid up to 9x9. |
| `--single-app-id V` | If a window whose app_id matches V exists → focus it (raise + switch to its workspace) and exit without launching. |
| `--single-title V` | Same, matching by window title. Mutually exclusive with `--single-app-id`. |
| `--exclude-title V` | Skip candidates whose title contains V. Needed because `--single-app-id firefox` would otherwise also match private windows. |
| `-e` | Exact match instead of the default substring match (applies to the `--single-*` value; `--exclude-title` is always substring). |

Flow (see `main()` in `open.c`):

1. If `--single-*` given → IPC `my-rules/focus-existing`. Found → exit 0.
   (Nothing spawned, so no suppression is armed.)
2. Otherwise → IPC `my-rules/prepare-open` (switches workspace if `-w` given
   **and** arms the suppression token), then fork → `setsid()` → `execvp()`,
   parent exits immediately. Zero waiting/polling — the window simply maps on
   the now-current workspace.

Each IPC call is a separate connect/send/close on `$WAYFIRE_SOCKET` (u32
little-endian length prefix + JSON — same framing as the other personal
clients). This is why the wayfire log shows two "New IPC client" lines per
launch. Values are JSON-escaped for `"` and `\` only.

Deployed as a symlink: `~/.local/bin/open -> .../build/src/client/open`.

### Current keybind examples (`[command]` in wayfire.ini)

```ini
command_16 = open -w 12 --single-app-id firefox --exclude-title "Private Browsing" firefox
command_17 = open -w 13 --single-title "Private Browsing" firefox --private-window
command_21 = open -w 33 --single-app-id btm kitty --single-instance --listen-on=unix:@mykitty --class btm btm
command_5  = kitty --single-instance --class float-power power-menu.sh   # keep-focused via rule, no wrapper
```

## The my-rules plugin

### Rule syntax

Config section `[my-rules]`, one dynamic-list option (`rules`, XML entry
prefix `""` → any key in the section is a rule, like stock window-rules):

```ini
[my-rules]
rule_1 = if app_id contains "mpv" then assign-focus 22
rule_2 = if app_id contains "float-power" then set geometry_ppt 45 42 10 16
rule_3 = if app_id contains "float" then keep-focused
```

`if <criteria> then <action>` — **no `on created`** (rules only ever run at
map). `<criteria>` is the standard wayfire condition language, parsed by
`wf::view_matcher_t` (each rule builds a free-standing
`wf::config::option_t<std::string>` to feed the matcher): `app_id`/`title`
with `is`/`contains`, combined with `!`, `&`, `|`, parentheses.

Three actions, nothing else by explicit requirement:

- `assign-focus RC` — move the view to the workspace (same 1-based row+column
  digits as `open -w`), **switch the viewport there** and focus/raise it.
  Applies to any matching appearance (e.g. opening a text file from yazi pulls
  you to the editor's workspace).
- `set geometry_ppt X Y W H` — geometry as percentages of the output size
  (same semantics as stock window-rules).
- `keep-focused` — marks the view via the **keep-focused plugin** through the
  in-process method repository (`ipc_repo->call_method("keep-focused/set")`,
  no socket). Requires the keep-focused plugin to be loaded; logs an error
  otherwise.

### Evaluation model

- Single `view_mapped_signal` connection on core. Only **parentless
  toplevels** are considered (dialogs follow their parents).
- Evaluated **once per view, at map**. No title/app-id watching afterwards —
  explicit requirement ("no timers, no polling").
- **All** matching rules apply (stock window-rules semantics), in
  **lexicographic option-name order**: `rule_1 < rule_10 < rule_2 < rule_20 <
  rule_3`. This ordering comes from wf-config, not from file order. It only
  matters when two rules touch the same window.
- Rules are re-parsed on `reload_config_signal` (config file save).

### The suppression token

`open` must prevent my-rules from acting on the window it is about to spawn
(open already placed it; an `assign-focus` rule for the same app would yank
the viewport or move the window). `my-rules/prepare-open` arms a **one-shot**
token; the **next parentless toplevel to map consumes it** and gets no rules.
It expires after **3 s** (`wf::wl_timer` in the plugin) so a failed launch
cannot eat the rules of an unrelated window later. Known accepted race: if an
unrelated window maps in that window of time, it consumes the token instead.

### IPC methods (used only by `open`)

- `my-rules/focus-existing {by: "app_id"|"title", value, exact, exclude-title?}`
  → scans mapped parentless toplevels, first match is focused via
  `focus_raise_view(view, true)`; returns `{found: bool}`.
- `my-rules/prepare-open {row?, col?}` → validates against
  `wset->get_workspace_grid_size()`, `request_workspace()` on the active
  output (goes through vswitch animation), arms the token; `{}` with no ws
  just arms the token.

## Hard-earned gotchas (do not reintroduce these bugs)

1. **Geometry changes are transactions.** `set_geometry()`/`move()` only set
   *pending* geometry until the client acks. Anything that repositions a view
   at map time must use `get_pending_geometry()` / core helpers like
   `wset->move_to_workspace()` (which uses pending and skips already-visible
   views). Reading `get_geometry()` and calling `move()` **stomps pending
   geometry another rule just set** — this bug lived in keep-focused's
   "bring to viewport" code and broke `geometry_ppt` for any rule that ran
   before the keep-focused rule (i.e. earlier lexicographic name).
2. **`ensure_visible()` judges by the committed bounding box** (`output.cpp`),
   so right after a pending `move_to_workspace()` it thinks the view is still
   visible and won't switch the viewport. That's why `assign-focus` calls
   `wset->request_workspace(rule.ws)` explicitly and then
   `focus_raise_view(view, /*allow_switch_ws*/ false)`.
3. **Rule application order is lexicographic by option name** (see above).

## Files & deployment

```
wayfire-my-rules-plugin/
├── meson.build              # project my-rules (c, cpp), dependency('wayfire')
├── metadata/my-rules.xml    # dynamic-list option "rules", entry prefix ""
├── src/my-rules.cpp         # the plugin (single file)
└── src/client/open.c        # the launcher (single file, libc only)
```

- Build: `meson setup build && ninja -C build` (Pavel builds himself — never
  run the build for him).
- Loading: no system install. `~/.zshenv` points
  `WAYFIRE_PLUGIN_PATH=$HOME/Projects/wayfire-plugins/src` and
  `WAYFIRE_PLUGIN_XML_PATH=$HOME/Projects/wayfire-plugins/metadata`; those
  dirs hold relative symlinks (`libmy-rules.so`, `my-rules.xml`) into this
  repo. A wiped `build/` dir leaves a dangling symlink → "Failed to load
  plugin" until rebuilt.
- `wayfire.ini` plugin list contains `my-rules`; stock `window-rules` is
  removed (my-rules fully replaces it for this setup).

## Interaction with the other personal plugins

- **keep-focused** (separate plugin, `wayfire-keep-focused-plugin/`): pins
  keyboard focus to a view (HIGH-importance scenegraph node, beats
  follow-focus) *and* shows it on all workspaces (removes from wset, OVERLAY
  layer, DESKTOP_ENVIRONMENT role). my-rules' `keep-focused` action is just a
  method-repository call into it.
- **my-activation**: grants all xdg-activation requests unconditionally; when
  an app requests activation before mapping, core logs "Attempting to give
  focus to a view without focus surface!" — harmless, the window still gets
  focused at map.
- **Idle cost**: my-rules does work only on view-map events and IPC calls;
  nothing on input/render paths.
