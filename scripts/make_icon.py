"""Generates the app icon PNGs (Resources/AppIcon.iconset). Run: python3 scripts/make_icon.py
Original artwork: two speech bubbles (Cyrillic -> Latin). Not Kaspi's logo."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, sys
S = 1024 * 4  # supersample
RED = (241, 70, 53)
FONT = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

def rounded_mask(size, box, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, r, fill=255)
    return m

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# macOS icon grid: 824/1024 body with ~185 radius
pad = int(S * 100 / 1024)
body = (pad, pad, S - pad, S - pad)
radius = int(S * 185 / 1024)
# shadow
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle((body[0], body[1] + S // 80, body[2], body[3] + S // 80), radius, fill=(0, 0, 0, 90))
sh = sh.filter(ImageFilter.GaussianBlur(S // 60))
img.alpha_composite(sh)
# gradient body
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
top, bot = (255, 104, 86), (214, 48, 34)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
img.paste(grad, (0, 0), rounded_mask((S, S), body, radius))
d = ImageDraw.Draw(img)

def bubble(draw, box, r, tail_left, fill):
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, r, fill=fill)
    w = x1 - x0
    if tail_left:
        pts = [(x0 + w * 0.18, y1 - 5), (x0 + w * 0.10, y1 + w * 0.17), (x0 + w * 0.40, y1 - 5)]
    else:
        pts = [(x1 - w * 0.18, y1 - 5), (x1 - w * 0.10, y1 + w * 0.17), (x1 - w * 0.40, y1 - 5)]
    draw.polygon(pts, fill=fill)

u = S / 1024
# back bubble (Russian), translucent white
back = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(back)
bubble(bd, (210 * u, 230 * u, 610 * u, 560 * u), 90 * u, True, (255, 255, 255, 120))
img.alpha_composite(back)
f1 = ImageFont.truetype(FONT, int(230 * u))
d.text((410 * u, 395 * u), "Я", font=f1, fill=(255, 255, 255, 255), anchor="mm")
# front bubble (English), solid white with red letter
front = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(front)
bubble(fd, (420 * u, 440 * u, 830 * u, 770 * u), 90 * u, False, (0, 0, 0, 60))
front = front.filter(ImageFilter.GaussianBlur(S // 120))
img.alpha_composite(front)
bubble(d, (410 * u, 425 * u, 820 * u, 755 * u), 90 * u, False, (255, 255, 255, 255))
f2 = ImageFont.truetype(FONT, int(240 * u))
d.text((615 * u, 592 * u), "A", font=f2, fill=RED + (255,), anchor="mm")

base = img.resize((1024, 1024), Image.LANCZOS)
out = os.path.join(os.path.dirname(__file__), "..", "Resources", "AppIcon.iconset")
os.makedirs(out, exist_ok=True)
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        base.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
base.save(os.path.join(os.path.dirname(__file__), "..", "docs", "icon.png"))
print("ok")
