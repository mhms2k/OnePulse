"""Generates the app icon (three score rings). Run: pip install pillow && python3 tools/make_icon.py"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

S = 1024
W = S * 2  # draw at 2x, downsample for smooth edges
img = Image.new("RGB", (W, W), (7, 9, 12))
glow = Image.new("RGB", (W, W), (0, 0, 0))
ImageDraw.Draw(glow).ellipse([W * 0.12, W * 0.05, W * 0.88, W * 0.8], fill=(20, 60, 90))
img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(W * 0.12)), 0.55)
d = ImageDraw.Draw(img)
cx = cy = W / 2
w = int(W * 0.062)
for r, col, sweep in [(0.36, (46, 229, 157), 300), (0.265, (62, 168, 255), 235), (0.17, (156, 140, 255), 320)]:
    R = W * r
    box = [cx - R, cy - R, cx + R, cy + R]
    d.arc(box, 0, 360, fill=(28, 34, 42), width=w)
    d.arc(box, -90, -90 + sweep, fill=col, width=w)
    for ang in (-90, -90 + sweep):  # round caps
        a = math.radians(ang)
        x, y = cx + (R - w / 2) * math.cos(a), cy + (R - w / 2) * math.sin(a)
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=col)
out = Path(__file__).resolve().parent.parent / "OpenPulse/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
img.resize((S, S), Image.LANCZOS).save(out)
print("wrote", out)
