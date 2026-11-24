# Night Mode for Omarchy

A moon in the Omarchy bar. One click dims every screen to the **same real brightness**, plus the keyboard backlight. A second click puts everything back where it was.

![Night Mode in the Omarchy bar](docs/preview.png)

## Why not just a percentage?

A brightness percentage means something different on every screen. My laptop panel reaches 400 cd/m² and my monitor about 283 cd/m², and the monitor's backlight never goes fully dark, so the same percentage looks different on each. Set both to 5 % and one glows while the other is nearly black.

Night Mode works in cd/m² (nits), the unit for how much light a screen actually gives off. It reads each screen's maximum luminance from the screen's own EDID, works out the level on each screen that gives the same luminance, and sets it. With my two screens it puts the monitor at 1 % and the laptop at 17 of 400 steps, so both glow at about 17 cd/m².

## Install

```bash
omarchy plugin add https://github.com/JackRubiralta/omarchy-night-mode.git --enable
```

The moon lands next to the clock, beside Do Not Disturb and Stay Awake. Move it like any other widget:

```bash
omarchy bar move io.github.jackrubiralta.night-mode --section right
```

Night Mode needs Omarchy 4.5 or newer. Everything else it uses ships with Omarchy: `brightnessctl` for laptop backlights, `ddcutil` (through `omarchy-brightness-display`) for external monitors, and `jq`.

Update or remove it the usual way:

```bash
omarchy plugin update io.github.jackrubiralta.night-mode
omarchy plugin remove io.github.jackrubiralta.night-mode
```

## Use

| Action | What happens |
|---|---|
| Click the moon | Turn night mode on or off |
| Right-click the moon | Open calibration in a terminal (see below) |
| Hover | **Dim Screens** when off, **Restore Brightness** when on, like Omarchy's own indicators |

The moon is full strength while night mode is on and dimmed while it is off.

**Your own brightness comes back.** Turning night mode on saves the exact level of every screen and the keyboard first; turning it off puts those levels back, even if you pressed the brightness keys in between, and even after a reboot. Night Mode reads each level back to check it took, and tries again if a monitor missed the command. If a monitor still won't take it, the moon stays lit and the next click tries again; the saved level is kept until it goes back, so it is never lost.

**Night mode only ever dims.** A screen that is already darker than the night level stays where it is, and turning night mode off leaves it there too. The same goes for a screen you dim further by hand while night mode is on, and for a keyboard that is already dim or unlit.

**A monitor that is away still counts as plugged in.** Night Mode remembers each monitor by its EDID, not by the port, so when one comes back (on any port, after any number of clicks) it is set to whatever night mode is now:

| While it was away | When it comes back |
|---|---|
| Night mode stayed on | Stays dimmed, or is dimmed again if it came back at its own brightness |
| You turned night mode off | Gets its own brightness back, the level it had before night mode |
| You turned night mode on | Dims to match; its own level is saved first |
| Off, then on again | Stays dimmed; turning off later gives the level from before it left |
| Another monitor used its port | That monitor is left alone; this one still gets its own level |

A monitor that has just been plugged in, or woken with the laptop, can take a while to answer. The bar keeps asking for about three minutes, and gets past the 60 s pause Omarchy's DDC helper puts on a monitor that missed one read. It also catches up after the laptop wakes from sleep and when the shell starts. A laptop panel switched off with its lid closed is dimmed and restored with the rest, so it is right when the lid opens.

The same script runs from a terminal or a keybinding. Link it onto your `PATH` once:

```bash
ln -s ~/.config/omarchy/plugins/io.github.jackrubiralta.night-mode/bin/night-mode ~/.local/bin/night-mode
```

and bind it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + N", "Night mode", "night-mode toggle")
```

```
night-mode               toggle (the default)
night-mode on | off      turn on or off
night-mode status        print "on" or "off"
night-mode info          show every screen, its luminance and its night level
night-mode info --json   the same as JSON
night-mode calibrate     match screens to each other by eye
night-mode sync          re-apply after a monitor change (the bar does this for you)
night-mode forget [eDP-1]  forget one screen's data and calibration, or all of them
```

`night-mode info` on my laptop with its monitor plugged in:

```
Night mode off · 17 cd/m² (automatic: Shenzhen KTC Technology Group H24T27 at 1 %)

eDP-1  LG Display 0x07B4
  control   backlight intel_backlight (0-400)
  maximum   400 cd/m² (EDID brightness range)
  at 1 %    4 cd/m²
  now       400/400 · 400 cd/m²
  night     17/400

DP-2  Shenzhen KTC Technology Group H24T27
  control   DDC/CI or Apple display (1-100 %)
  maximum   283 cd/m² (EDID HDR frame average)
  at 1 %    17 cd/m² (assumes 5 % of maximum at 0 %)
  now       100 % · 283 cd/m²
  night     1 %
```

## Settings

Set them in Omarchy's widget settings, or in the widget's entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.jackrubiralta.night-mode", "brightness": 0, "keyboard": "dim" }
```

| Key | Values | Default |
|---|---|---|
| `brightness` | cd/m² while night mode is on. `0` picks it automatically (below). | `0` |
| `keyboard` | `dim` (lowest lit step), `off`, or `unchanged` | `dim` |

`NIGHT_MODE_BRIGHTNESS` and `NIGHT_MODE_KEYBOARD` override both for one run.

## How the brightness is worked out

**Each screen's maximum.** Night Mode reads the screen's EDID from `/sys/class/drm/*/edid` and takes the first of these that the screen reports:

1. DisplayID 2.1 brightness luminance range: the maximum suggested SDR luminance (modern laptop panels)
2. DisplayID 2.0 display parameters: the native maximum luminance at full coverage
3. CTA-861 HDR static metadata: the maximum frame-average luminance (most HDR-capable monitors)
4. CTA-861 HDR static metadata: the maximum luminance

A screen that reports none of them is taken as a typical 300 cd/m² laptop panel or 250 cd/m² monitor. `night-mode info` names the source for every screen.

**Each screen's curve.** A laptop backlight in `/sys/class/backlight` gives light in proportion to its level, so level 17 of 400 on a 400 cd/m² panel gives 17 cd/m². On some panels, like the LG one above, the level is itself in cd/m²: 400 steps for a 400 cd/m² panel. An external monitor, dimmed over DDC/CI from 1 to 100 %, never goes fully dark: at 0 % its backlight still glows. EDID doesn't say how much, so Night Mode assumes 5 % of the maximum and spreads the rest evenly up to 100 %.

**The target.** Left on automatic, the target is the light the least-dimmable screen gives at 1 %, Omarchy's lowest brightness step. Every screen can reach that, so they all match. Night Mode remembers each screen it has dimmed, so the target stays the same when that screen is unplugged: the laptop alone still dims to the level that matches the monitor. `night-mode forget` clears that memory.

**Each screen's night level** is the lower of the matched level and the level the screen had when night mode turned on, so a screen that was already darker keeps its own level.

**Calibrating.** The EDID figures are the maker's, and the 5 % floor is an estimate. If two screens don't look the same at night, run `night-mode calibrate` (or right-click the moon). It turns night mode on and lets you raise or lower each screen with the arrow keys until it matches the reference screen; Enter saves. The correction belongs to that monitor model on any port. A screen can't be calibrated brighter than the level you had it at.

## Files

| Path | What it holds |
|---|---|
| `bin/night-mode` | Everything that reads and sets brightness (bash, no daemon) |
| `BarWidget.qml` | The moon, its tooltip, and the hotplug watcher |
| `i18n/*.json` | Tooltip translations; follows Setup > Language |
| `~/.local/state/night-mode/state.json` | On or off, the saved levels, and every screen seen |

Nothing runs in the background. The widget follows `state.json` and calls the script on a click, a monitor change, waking from sleep or the shell starting. `night-mode sync` exits 75 while a screen has not answered yet, and the widget asks again.

## Limits

- **HDR mode.** In HDR the compositor, not the backlight, sets how bright white is, so the matching assumes SDR.
- **Monitors without DDC/CI**, and some TVs, can't be dimmed from the computer. `night-mode info` marks them, and they don't count towards the target.
- **Two identical monitors** (same EDID, serial number included) are told apart by their ports, so swapping their cables while night mode is on swaps their saved levels.
- **The figures are the maker's.** EDID luminance is what the panel was designed for, not a measurement of your unit; calibrate if it looks off.

## Development

```bash
tests/run.sh                           # 69 tests on a fake /sys with mock tools
shellcheck bin/night-mode tests/run.sh
omarchy plugin validate .
```

The tests use the EDIDs of a 2880×1800 LG laptop panel and a KTC H24T27 monitor, in `tests/fixtures/`. EDIDs from other screens are welcome as new fixtures.

## Credits

The moon is Material Design Icons' "weather-night" ([Pictogrammers](https://pictogrammers.com/library/mdi/), Apache License 2.0) with its inner outline filled in. Everything else is MIT, © 2026 Jack Rubiralta. See [LICENSE](LICENSE).
