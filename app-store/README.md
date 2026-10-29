# App Store screenshots

Screenshots for the Mac App Store listing (#62).
The store requires at least one image at one of its exact sizes (2880×1800, 2560×1600, 1440×900, or 1280×800).

- `main-window-2880x1800.png` — the main window (Mail-style sidebar, a filterable pad list, and a pad detail with participants and syntax-highlighted code), on the seeded `-uiTesting` demo account, so it carries no real candidate data.
  Composited onto a dark background at the exact 2880×1800 size.

## Regenerating at full resolution

This image is composed from the web hero shot (`docs/assets/screenshot-pads@2x.png`).
For a sharper, full-bleed version, capture a fresh shot from the app and pad/crop it to 2880×1800:

1. Run `PadBuddyUITests/testCaptureMarketingScreenshots` with a free GUI session (no other app driving the display) and export the `pads-detail` attachment.
2. `sips --padToHeightWidth 1800 2880 --padColor 0F1115 <shot>.png --out main-window-2880x1800.png` (or scale to width 2880 and crop to 1800 for a full-bleed look).

Uploading these to App Store Connect is a manual step, blocked until the app record exists (#489).

## CoderPad team beta

See [the TestFlight handoff](testflight.md) and its ready-to-paste testing note.
