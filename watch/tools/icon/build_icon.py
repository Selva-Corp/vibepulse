#!/usr/bin/env python3
"""AgentTap's app icon: a quota ring with a tap point, drawn at 1024px.

Programmatic so the icon is reproducible and reviewable as code. watchOS
masks icons circular; the composition keeps everything inside the safe
circle. Run with the repo venv (needs Pillow):
    ../.venv/bin/python tools/icon/build_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

S = 1024
SS = 4  # supersample for clean arcs
BG = (16, 18, 22, 255)          # near-black, blue-biased like the panel
RING = (217, 119, 87, 255)      # the provider-orange accent
RING_DIM = (58, 46, 42, 255)    # unlit remainder of the ring
SECOND = (111, 120, 255, 255)   # codex blue, one quiet inner arc
DOT = (240, 236, 232, 255)      # the tap: warm off-white

img = Image.new("RGBA", (S * SS, S * SS), BG)
d = ImageDraw.Draw(img)

def ring(bbox_pad, width, start, end, fill):
    box = [bbox_pad * SS, bbox_pad * SS, (S - bbox_pad) * SS, (S - bbox_pad) * SS]
    d.arc(box, start=start, end=end, fill=fill, width=width * SS)

# Main quota ring: lit three quarters, gap at the top-right — mid-burn week.
ring(150, 74, -60, 210, RING_DIM)
ring(150, 74, -60, 140, RING)
# Inner codex whisper.
ring(300, 40, 120, 235, SECOND)
# The tap: a filled dot at the main ring's live end, slightly larger than
# the ring width so it reads as a touch, not a cap.
import math
cx = cy = S / 2
r = S / 2 - 150 - 0  # main ring radius (center of stroke)
r = (S - 2 * 150) / 2
ang = math.radians(140)
px = cx + r * math.cos(ang)
py = cy + r * math.sin(ang)
rad = 92
d.ellipse([(px - rad) * SS, (py - rad) * SS, (px + rad) * SS, (py + rad) * SS],
          fill=DOT)
rad2 = 56
d.ellipse([(px - rad2) * SS, (py - rad2) * SS, (px + rad2) * SS, (py + rad2) * SS],
          fill=RING)

out = img.resize((S, S), Image.LANCZOS).convert("RGB")
dest = Path(__file__).resolve().parents[2] / "AgentTap" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
dest.parent.mkdir(parents=True, exist_ok=True)
out.save(dest)
print(f"wrote {dest}")
