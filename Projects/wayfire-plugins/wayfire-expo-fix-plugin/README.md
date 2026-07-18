# expo-fix

A standalone copy of Wayfire's **expo** plugin (the workspace overview) with a
lower-cost renderer. It is the *conservative* alternative to `expo-niri`: it keeps
expo's photo-buffer architecture but samples the workspaces from a half-resolution
copy instead of minifying the full-resolution buffer every frame.

Behaviour is identical to expo — same options, same interaction.

## What changed vs. stock expo

The stock expo (via the shared `workspace-wall`) renders each workspace into a
full-resolution buffer and then composites those buffers, minified ~3x, onto the
screen every frame. On a memory-bandwidth-limited GPU that minified sampling
reads most of every buffer's cache lines and dominates the frame cost, and the
per-frame rescaling causes stutter spikes during the zoom.

expo-fix vendors its own copy of the wall (`src/expo-fix-wall.*`, class renamed to
`wf::expo_fix_wall_t` so it never clashes with the built-in one) with these
changes:

- **Half-resolution presentation copy.** The full-resolution buffer stays the
  single source of truth; a 1/2-scale copy of each workspace is maintained by GPU
  blits (or captured directly at 1/2 scale). Compositing samples that copy, so the
  per-frame read traffic is roughly a quarter.
- **No rescaling during the animation.** The buffers are not re-rendered at
  changing scales while zooming; captures are front-loaded onto the first,
  visually static frame.
- **Anchor rule.** During the animation only the workspace under the viewport
  centre is kept at full resolution; the others use the 1/2 copy, so there is no
  simultaneous re-blit storm mid-zoom.
- **Deferred workspace switch.** The workspace is switched at the end of the exit
  animation (as vswitch does), so the switch does not force a full re-capture at
  the start of the exit.

Compared to the full mip approach it drops the extra 1/4-scale copy level and
keeps a stock draw path (normal texture draw + dim rectangle), so **it requires no
Wayfire core changes** and links only against the installed Wayfire.

If you want the biggest win, use `expo-niri` (direct rendering, no photos at all).
expo-fix is the smaller, lower-risk change that stays closest to stock expo.

## Build

```sh
meson setup build --prefix=/usr
ninja -C build
sudo ninja -C build install     # installs libexpo-fix.so + expo-fix.xml
```

Or run against the build dir:

```sh
WAYFIRE_PLUGIN_PATH=$PWD/build/src \
WAYFIRE_PLUGIN_XML_PATH=$PWD/metadata \
    wayfire
```

## Use

Add `expo-fix` to the plugin list and remove `expo` (they share a toggle). All
options match expo's, under `[expo-fix]`:

```ini
[core]
plugins = ... expo-fix

[expo-fix]
toggle = <super> KEY_E
background = 0.1 0.1 0.1 1.0
duration = 300ms circle
offset = 10
keyboard_interaction = true
inactive_brightness = 0.7
transition_length = 200
```

The IPC activator is `expo-fix/toggle`.
