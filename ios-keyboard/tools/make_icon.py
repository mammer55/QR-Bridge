#!/usr/bin/env python3
"""Generate the ClipKeyboard app icon: mint→teal gradient + white mic."""
from PIL import Image, ImageDraw, ImageFilter
import os

S = 4                     # supersample factor
SIZE = 1024 * S
cx = SIZE / 2

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# Diagonal gradient: teal (top-left) -> mint (bottom-right)
TOP = (11, 148, 136)      # teal
BOT = (150, 240, 205)     # mint
bg = Image.new("RGB", (SIZE, SIZE))
px = bg.load()
for y in range(SIZE):
    for x in range(0, SIZE, 1):
        t = (x + y) / (2 * SIZE)
        px[x, y] = lerp(TOP, BOT, t)

img = bg.convert("RGBA")

def draw_mic(d, color):
    # Mic body (capsule)
    bw = 300 * S
    bh = 470 * S
    bx0 = cx - bw / 2
    by0 = 250 * S
    d.rounded_rectangle([bx0, by0, bx0 + bw, by0 + bh], radius=bw / 2, fill=color)

    # Cradle (U-arc around the lower body)
    cw = 460 * S
    ch = 470 * S
    ccy = by0 + bh - 150 * S
    lw = 46 * S
    d.arc([cx - cw / 2, ccy - ch / 2, cx + cw / 2, ccy + ch / 2],
          start=18, end=162, fill=color, width=lw)

    # Stem
    stem_top = ccy + ch / 2 - lw / 2
    stem_bot = stem_top + 120 * S
    d.rounded_rectangle([cx - lw / 2, stem_top, cx + lw / 2, stem_bot],
                        radius=lw / 2, fill=color)

    # Base
    base_w = 240 * S
    d.rounded_rectangle([cx - base_w / 2, stem_bot - lw / 2,
                         cx + base_w / 2, stem_bot + lw / 2],
                        radius=lw / 2, fill=color)

# Soft shadow
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
draw_mic(sd, (0, 40, 30, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(18 * S))
shadow = shadow.transform(
    shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, 14 * S))
img = Image.alpha_composite(img, shadow)

# White mic
d = ImageDraw.Draw(img)
draw_mic(d, (255, 255, 255, 255))

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
dest = os.path.join(os.path.dirname(__file__), "AppIcon-1024.png")
out.save(dest)
print("wrote", dest)
