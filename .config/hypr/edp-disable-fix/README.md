# eDP-1 startup disable fix

Rebuilt for Hyprland **0.57.0** (`0aa6745f705f2c4b0a5004eb019ef76e5bbdb426`),
plugin API **0.2**, and Aquamarine **0.16.0**. Compilation, ABI-hash, exported-hook,
and dynamic-symbol checks passed against the installed release. Live output and
VRAM behavior still need verification in the desktop session.

## Cause

The current session log contains:

```text
[Monitor::CMonitorState::updateSwapchain] updateSwapchain: No mode?
[Monitor::CMonitor::onConnect] Couldn't commit disabled state on output eDP-1
```

Meanwhile `/sys/class/drm/card1-eDP-1/enabled` says `enabled` and `dpms`
says `On`. The panel was logically disabled but its initial KMS disable
commit failed, leaving the console framebuffer displayed.

Hyprland's `CMonitorState::updateSwapchain()` runs for disable commits too.
Aquamarine's `CDRMOutput::commitState()` rejects commits without a mode,
including disable commits. Enabling the panel first supplies a mode but also
allocates its render buffers.

This plugin hooks `CMonitorState::updateSwapchain()` only for a logically
disabled eDP-1 with pending `enabled=false`. It selects preferred-mode
metadata if missing and skips swapchain configuration. The existing disabled
branch of `ensureBufferPresent()` skips buffer allocation, and the normal
commit reaches KMS. Loading the plugin retries the failed startup commit.
The hook also handles subsequent reloads. Enabled eDP-1 and every other
output use the original function.

Sources inspected:

- https://github.com/hyprwm/Hyprland/blob/main/src/output/Monitor.cpp
- https://github.com/hyprwm/aquamarine/blob/f31c47a/src/backend/drm/DRM.cpp

## Apply and verify

Keep the existing rule:

```lua
hl.monitor({ output = "eDP-1", disabled = true })
```

Run from a terminal inside the Hyprland session:

```sh
hyprctl plugin load /home/pavel/.config/hypr/edp-disable-fix/libedp-disable-fix.so
hyprctl edp-disable-status
cat /sys/class/drm/card1-eDP-1/enabled
cat /sys/class/drm/card1-eDP-1/dpms
```

For a panel that has never been enabled by the workaround, the status should be:

```text
eDP-1: enabled=false, pending_enabled=false, swapchain_length=0, pending_buffer=false
```

The kernel `enabled` file should report `disabled`, and the panel should turn
off. Also verify that `hyprctl reload` preserves this state and the zero-length
swapchain. Kernel `dpms` reporting can depend on the driver; use `enabled`
and the visible panel state as well.

This avoids creating the panel's render buffers; it does not reclaim buffers
already created by a prior on/off workaround. If that workaround already ran,
test from a fresh session. A zero-length output swapchain does not alone
prove total GPU memory usage, so compare VRAM with the same applications open.

## Persist after the live check

Add this inside the existing `hl.on("hyprland.start", function() ... end)`:

```lua
hl.exec_cmd("hyprctl plugin load /home/pavel/.config/hypr/edp-disable-fix/libedp-disable-fix.so")
```

The old `wlr-randr` on/off sequence and renderer reload are unnecessary for
this approach. They are already commented out in the current configuration.

To unload:

```sh
hyprctl plugin unload /home/pavel/.config/hypr/edp-disable-fix/libedp-disable-fix.so
```

Remove its autostart line if added. A fresh session restores the original
unmodified compositor behavior.

## Rebuild

Rebuild after changing Hyprland or its development headers:

```sh
sh /home/pavel/.config/hypr/edp-disable-fix/build.sh
```

The plugin checks the compositor/header ABI hash and refuses to initialize
if they differ. The build atomically replaces the library, so rebuilding does
not overwrite a library mapped by the running compositor. Reload the plugin to
use the rebuilt binary. For an upstream fix, Hyprland needs a disable path that skips
swapchain allocation, and Aquamarine needs to accept modeless disable commits
or receive valid mode metadata without an enable/render cycle.
