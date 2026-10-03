#!/usr/bin/env python3
"""
Draws the PES Archive Tool app icon and writes it as AppIcon.icns next to this script.

The finished AppIcon.icns is checked in, so this only needs running when the
design changes:  pip install pillow && python3 make-icon.py
"""
import io
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024          # the icon is drawn once at full size and scaled down from there
SCALE = 2            # draw at double size first, which smooths the edges

# macOS icons are a rounded square that leaves some breathing room around it.
PLATE = (100, 100, 924, 924)
PLATE_RADIUS = 185

TOP = (38, 166, 154)      # teal
BOTTOM = (13, 71, 96)     # deep blue-green
WHITE = (255, 255, 255, 255)


def scaled(values):
    return tuple(v * SCALE for v in values)


def draw_icon():
    big = SIZE * SCALE

    # Soft drop shadow under the plate.
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    left, top, right, bottom = scaled(PLATE)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left, top + 12 * SCALE, right, bottom + 12 * SCALE),
        radius=PLATE_RADIUS * SCALE, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * SCALE))

    # The plate: a top-to-bottom gradient, cut to the rounded square.
    gradient = Image.new("RGBA", (big, big))
    pixels = ImageDraw.Draw(gradient)
    for y in range(big):
        t = min(max((y - top) / (bottom - top), 0), 1)
        colour = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)) + (255,)
        pixels.line([(0, y), (big, y)], fill=colour)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(scaled(PLATE), radius=PLATE_RADIUS * SCALE, fill=255)
    icon = Image.alpha_composite(shadow, Image.composite(gradient, Image.new("RGBA", (big, big), (0, 0, 0, 0)), mask))

    # The glyph: an arrow dropping into a tray, i.e. "drop your files here".
    draw = ImageDraw.Draw(icon)
    stroke = 62 * SCALE

    # Arrow shaft and head.
    draw.rounded_rectangle(scaled((481, 270, 543, 560)), radius=stroke // 2, fill=WHITE)
    draw.line([scaled((372, 452)), scaled((512, 592)), scaled((652, 452))],
              fill=WHITE, width=stroke, joint="curve")
    for x, y in ((372, 452), (652, 452), (512, 592)):
        r = stroke // 2
        draw.ellipse((x * SCALE - r, y * SCALE - r, x * SCALE + r, y * SCALE + r), fill=WHITE)

    # Tray: a wide U with rounded corners.
    tray = [scaled((300, 590)), scaled((300, 720)), scaled((724, 720)), scaled((724, 590))]
    draw.line(tray, fill=WHITE, width=stroke, joint="curve")
    for x, y in ((300, 590), (724, 590), (300, 720), (724, 720)):
        r = stroke // 2
        draw.ellipse((x * SCALE - r, y * SCALE - r, x * SCALE + r, y * SCALE + r), fill=WHITE)

    return icon.resize((SIZE, SIZE), Image.LANCZOS)


def write_icns(icon, path):
    # An .icns file is a short header followed by PNGs, each tagged with a code for its size.
    entries = [("ic04", 16), ("ic05", 32), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
               ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
    body = b""
    for code, size in entries:
        png = io.BytesIO()
        icon.resize((size, size), Image.LANCZOS).save(png, format="PNG")
        data = png.getvalue()
        body += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    here = Path(__file__).resolve().parent
    image = draw_icon()
    write_icns(image, here / "AppIcon.icns")
    print("Wrote", here / "AppIcon.icns")
