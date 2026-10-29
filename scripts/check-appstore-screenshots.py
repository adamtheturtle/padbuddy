#!/usr/bin/env python3
"""Check the canonical macOS screenshot set and its upload instructions."""
import json
import pathlib
import struct

root = pathlib.Path(__file__).resolve().parent.parent
manifest = json.loads((root / "app-store/screenshot-manifest.json").read_text())
directory = root / "app-store/submission/en-US/screenshots"
guide = (directory.parent / "screenshots.md").read_text()
expected = []
for shot in manifest["shots"]:
    name = f'{shot["basename"]}-{manifest["width"]}x{manifest["height"]}.png'
    expected.append(name)
    assert f'`screenshots/{name}`' in guide, f"Upload guide omits {name}"
    with (directory / name).open("rb") as image:
        header = image.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG: {name}"
    assert struct.unpack(">II", header[16:24]) == (manifest["width"], manifest["height"]), name
assert [name for name in expected] == sorted(expected, key=guide.index), "Upload order differs"
assert not (directory / "01-main-window-2880x1800.png").exists(), "Superseded screenshot remains"
print(f"Verified {len(expected)} canonical App Store screenshots and upload order.")
