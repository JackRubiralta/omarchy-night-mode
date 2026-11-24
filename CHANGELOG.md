# Changelog

## 1.2.0 – 2026-11-24

- **A monitor that is away still counts as plugged in.** Saved levels now belong to the monitor (its EDID), not the port. Dim, unplug, turn night mode off on the laptop, plug back in: the monitor gets its own brightness back, on the same port or another one, however many times night mode was turned on and off meanwhile. A different monitor plugged into its port no longer wipes its saved level. State from 1.1 moves over by itself.
- **Monitors that are slow to wake are not missed.** A monitor plugged in, or woken with the laptop, often doesn't answer DDC/CI for several seconds, and after one missed read Omarchy's DDC helper refuses that monitor for 60 s, so both of the bar's syncs failed and the monitor stayed dimmed. Night Mode now clears that pause for a monitor that has answered before, `sync` exits 75 while a screen is still unanswered, and the bar asks again for about three minutes.
- The bar also syncs when the laptop wakes from sleep and when the shell starts, runs one sync when every screen's bar asks at once, and never drops a click that comes in during a sync.
- A laptop panel switched off with the lid closed is dimmed and restored with the other screens.
- One missed read no longer drops a monitor from the target (which dimmed the laptop further until the next replug).
- A laptop backlight turned up by hand during night mode is left there by a sync (only monitors reset themselves).

## 1.1.1 – 2026-11-22

- **A monitor plugged in during night mode is dimmed again.** A monitor unplugged while night mode was on often comes back at its own full brightness, but `sync` trusted the level it had set before and left it bright. It now reads every screen and dims any that came back brighter; one you dimmed further by hand is still left alone.
- The bar runs a second `sync` 8 s after a plug or unplug, for monitors that are slow to answer DDC/CI.

## 1.1.0 – 2026-11-19

- **Night mode only ever dims.** Each screen goes to the lower of the matched night level and its own level, so a screen already darker than the night level stays where it is. A screen dimmed further by hand while night mode is on is not raised again when the night level changes (a monitor plugged in, a new setting). The keyboard is never brightened either.
- **Restores are checked.** Every level night mode sets or puts back is read back and retried up to three times, since a monitor can miss a DDC/CI command and Omarchy's brightness command skips a run while another holds its lock. A screen that still misses its original level keeps it saved: the moon stays lit so the next click tries again, and after a second miss the saved level waits for the monitor's next replug or the next on/off.
- `night-mode off` always retries saved levels, even when night mode is already off.
- `info` says when a screen keeps its own, darker level; `info --json` adds `matchedLevel` and `keepsOwnLevel`.
- Calibration skips a screen that was already darker and never goes above your own level.

## 1.0.0 – 2026-11-19

First public release.

- Dims every screen to the same luminance in cd/m², read from each screen's EDID (DisplayID 2.1 brightness range, DisplayID 2.0 display parameters, CTA-861 HDR static metadata), with typical values for screens that report none.
- Automatic target: the light the least-dimmable screen gives at 1 %, remembered when that screen is unplugged. Or a fixed cd/m² in the widget settings.
- Laptop backlights set in raw steps, external monitors over DDC/CI and Apple displays through Omarchy's own brightness command.
- Keyboard backlight: dim, off or unchanged.
- Monitors plugged in while night mode is on dim to match; monitors unplugged while it was on get their brightness back when they return.
- `night-mode calibrate` to match screens by eye; `info`, `info --json`, `forget`, `sync`.
- Tooltips worded like Omarchy's indicators ("Dim Screens" / "Restore Brightness"), in 20 languages.
- Carries over the saved levels of the earlier `~/.local/bin/night-mode` prototype.
