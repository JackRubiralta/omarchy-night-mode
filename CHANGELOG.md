# Changelog

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
