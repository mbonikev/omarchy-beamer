# Beamer

An Omarchy shell plugin for putting the desktop on a second screen. It appears
in the bar as **Project**, and does what Windows' Project panel does —
duplicate, extend, PC screen only, second screen only — plus reordering, a
resolution picker, and saved profiles that come back when the same monitors
are plugged in again.

Omarchy's built-in `omarchy.monitor` widget covers brightness and the laptop
panel. This one covers where the picture goes.

It only acts when a second monitor is actually connected, and it ignores
virtual outputs (`HEADLESS-n`, `WL-n`, `X11-n`) so it can never arrange your
real screen around one that isn't there.

## Install

```bash
omarchy plugin add https://github.com/mbonikev/omarchy-beamer.git --enable

# ...or by hand:
#   git clone https://github.com/mbonikev/omarchy-beamer.git \
#       ~/.config/omarchy/plugins/beamer
#   omarchy-shell shell rescanPlugins
#   omarchy plugin enable beamer right
```

Requires `jq`, which Omarchy already installs.

## How it stays out of your way

The plugin never edits `~/.config/hypr/monitors.lua`. It writes one generated
file:

```
~/.local/state/omarchy/toggles/hypr/zz-display-layout.lua
```

`hyprland.lua` sources that directory after your own monitor config, so the
plugin's rules win while it is in charge, and your `monitors.lua` is still the
thing underneath. **Reset** deletes the generated file and hands control
straight back — nothing of yours was changed to begin with.

The `zz-` prefix matters: the toggles directory loads in sorted order, so this
sorts after Omarchy's own `internal-monitor-*.lua` toggles rather than racing
them. Taking over also clears those two toggles, so there is only ever one
authority for a given output. When the lid is shut and the clamshell watcher
owns the internal panel, the plugin leaves that output out of its config
entirely.

## The panel

Click the monitor icon in the bar. Right-click it to mirror without opening
anything.

- **Arrangement** — Mirror, extend right / left / up / down from the primary
  display, PC screen only, or second screen only. The map underneath shows the
  result to scale.
- **Per display** — turn it off, make it primary, move it along the row, and
  pick its resolution.
- **Profiles** — save the current arrangement under a name. It records which
  monitors were plugged in at the time, so `profile auto` can pick it again.

Keyboard: `j`/`k` between sections, `h`/`l` within one, `Enter` to activate,
`Esc` to close — the same as Omarchy's own panels.

## CLI

Everything the panel does goes through `bin/omarchy-displays`, so a keybinding
or a script drives exactly the same engine:

Scale and rotation are not part of what the panel arranges, but the engine
exposes them, and a generated rule always carries forward whatever scale and
rotation the compositor is already using — so taking over an arrangement never
quietly resets a scale set in `monitors.lua`.

```bash
omarchy-displays mirror [monitor]            # same picture everywhere
omarchy-displays extend right|left|up|down
omarchy-displays arrange [--vertical] DP-1 eDP-2
omarchy-displays only eDP-2
omarchy-displays enable HDMI-A-1 off|on|toggle
omarchy-displays mode HDMI-A-1 1920x1080@60
omarchy-displays scale HDMI-A-1 1.5
omarchy-displays transform eDP-2 90
omarchy-displays position eDP-2 -1920x200    # or `auto` to go back to packing
omarchy-displays align top|center|bottom
omarchy-displays primary eDP-2
omarchy-displays profile save|apply|rm|list|auto [name]
omarchy-displays reset
omarchy-displays state                       # JSON, what the panel reads
omarchy-displays render                      # the Lua it would write
```

### Keybindings

The script is not on `PATH`. Point at it directly in
`~/.config/hypr/bindings.lua`:

```lua
local beamer = os.getenv("HOME") .. "/.config/omarchy/plugins/beamer/bin/omarchy-displays"
o.bind("SUPER + P", "Duplicate screen", beamer .. " mirror")
o.bind("SUPER + SHIFT + P", "Extend screen", beamer .. " extend right")
```

Or go through the shell, which is already running it:

```lua
o.bind("SUPER + P", "Duplicate screen", "omarchy-shell beamer mirror")
o.bind("SUPER + CTRL + P", "Project panel", "omarchy-shell beamer toggle")
```

### Switching profiles on hotplug

`profile auto` applies whichever saved profile matches the monitors currently
connected. To run it whenever that changes, point a monitor hook at it.

## Positioning

Extending packs the enabled displays along one axis in order, using each one's
*logical* size — mode width divided by scale, with the axes swapped for a 90°
or 270° rotation — so a 4K screen at scale 2 takes 1920 pixels of desktop and
its neighbour starts there, not at 3840. `align` sets what happens on the other
axis when the displays are different sizes.

Setting a position by hand pins that display; it keeps its spot while you change
its mode, scale or rotation, and the others pack around it. Choosing an
arrangement preset clears every manual position and repacks the lot.

## Safety

The plugin declines to arrange anything unless a second monitor is connected,
and virtual outputs do not count as one. Monitor names end up inside generated
Lua, so every name is checked against a plain connector pattern before it is
written — a headless output can be called
anything. Modes, scales, rotations and positions are validated the same way, and
a rejected value leaves the existing config untouched. The plugin will not
switch off the last display you have left.

## Updating and uninstalling

```bash
omarchy plugin update beamer    # fast-forwards the checkout, showing a diff first
omarchy plugin remove beamer
```

## Tests

```bash
test/run.sh
```

The engine suite runs against fake monitor sets through
`OMARCHY_DISPLAYS_HW_JSON` and a stub `hyprctl`, so it covers two- and
three-head arrangements, scale preservation, profiles, the clamshell hand-off,
virtual-output filtering and the input validation without touching the
compositor. The model suite checks the
panel's pure helpers against real `omarchy-displays state` output.
