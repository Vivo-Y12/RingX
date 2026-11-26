#!/usr/bin/env python3
"""Ringx app icon: dark disc, amber ring gauge with a gap + center dot.

Original art, saved as a multi-size .ico for the Windows runner. Run from
anywhere inside the repo:

    python -m pip install pillow
    python tool/make_icon.py

Writes windows/runner/resources/app_icon.ico (the file referenced byRunner.rc). CI runs this step automatically before building.
"""
import math
import os

from PIL import Image, ImageDraw

BG = (14, 17, 22, 255)        # #0E1116 dark
RING = (245, 165, 36, 255)    # #F5A524 amber
RING_DIM = (58, 64, 77, 255)  # #3A404D
HUB = (245, 165, 36, 255)

OUT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "windows", "runner", "resources", "app_icon.ico"))

# Fresh checkouts have no windows/runner/resources/ directory yet; create it
# so the save below never fails with FileNotFoundError (CI runs on a clean tree).
os.makedirs(os.path.dirname(OUT), exist_ok=True)


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Background disc (full square, rounded look comes from the circle).
    d.ellipse([0, 0, size - 1, size - 1], fill=BG)
    m = size / 12  # margin unit
    # Outer dim ring (full circle).
    d.arc([m, m, size - 1 - m, size - 1 - m], start=0, end=360,
          fill=RING_DIM, width=max(1, int(size / 14)))
    # Amber arc: gauge sweep from -60deg to +150deg (leaves a gap).
    w = max(1, int(size / 14))
    d.arc([m, m, size - 1 - m, size - 1 - m], start=300, end=150,
          fill=RING, width=w)
    # Tick marks at the arc ends.
    cx = cy = (size - 1) / 2
    r = (size - 1 - 2 * m) / 2
    for ang in (300, 150):
        a = math.radians(ang)
        x1 = cx + (r - w) * math.cos(a)
        y1 = cy + (r - w) * math.sin(a)
        x2 = cx + (r + w) * math.cos(a)
        y2 = cy + (r + w) * math.sin(a)
        d.line([x1, y1, x2, y2], fill=RING, width=max(1, int(size / 28)))
    # Center hub dot.
    hr = max(2, size / 9)
    d.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=HUB)
    return img


base = draw_icon(256)
base.save(OUT, format="ICO",
          sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128),
                 (256, 256)])
print("saved", OUT)

# Self-check: reopen and confirm it decodes.
im = Image.open(OUT)
print("decoded:", im.size, im.mode, "frames:", getattr(im, "n_frames", 1))
