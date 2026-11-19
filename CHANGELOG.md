# Changelog

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
