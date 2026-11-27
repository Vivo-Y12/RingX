#!/usr/bin/env python3
"""Ringx app icon: dark disc, amber ring gauge with a gap + center dot.

Original art. Two outputs:

  python tool/make_icon.py            -> windows/runner/resources/app_icon.ico
  python tool/make_icon.py --android  -> android mipmap launcher PNGs

Run from anywhere inside the repo (CI runs both before building). Requires
Pillow:  python -m pip install pillow
"""
import math
import os
import sys

from PIL import Image, ImageDraw

BG = (14, 17, 22, 255)        # #0E1116 dark
RING = (245, 165, 36, 255)    # #F5A524 amber
RING_DIM = (58, 64, 77, 255)  # #3A404D
HUB = (245, 165, 36, 255)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_ICO = os.path.normpath(
    os.path.join(HERE, "..", "windows", "runner", "resources",
                 "app_icon.ico"))

# Android launcher PNGs (plain bitmaps; launchers mask them themselves).
ANDROID_MIPMAPS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


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


def write_ico() -> None:
    # Fresh checkouts have no windows/runner/resources/ directory yet; create
    # it so the save never fails with FileNotFoundError on a clean tree.
    os.makedirs(os.path.dirname(OUT_ICO), exist_ok=True)
    base = draw_icon(256)
    base.save(OUT_ICO, format="ICO",
              sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128),
                     (256, 256)])
    print("saved", OUT_ICO)
    # Self-check: reopen and confirm it decodes.
    im = Image.open(OUT_ICO)
    print("decoded:", im.size, im.mode, "frames:", getattr(im, "n_frames", 1))


def write_android() -> None:
    """Launcher icons into android/app/src/main/res/mipmap-*/ic_launcher.png.

    The PNGs are not committed (binary files); CI regenerates them here so a
    fresh checkout still has every resource the manifest references.
    """
    res = os.path.normpath(
        os.path.join(HERE, "..", "android", "app", "src", "main", "res"))
    base = draw_icon(512)
    for bucket, px in ANDROID_MIPMAPS.items():
        out_dir = os.path.join(res, f"mipmap-{bucket}")
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, "ic_launcher.png")
        base.resize((px, px), Image.LANCZOS).save(out, "PNG")
        print("saved", out, f"({px}x{px})")


if __name__ == "__main__":
    if "--android" in sys.argv[1:]:
        write_android()
    else:
        write_ico()
