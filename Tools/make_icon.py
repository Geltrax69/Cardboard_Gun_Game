#!/usr/bin/env python3
"""Draws the Cardboard Lab app icon (1024x1024, opaque) in the game's palette."""
import math, sys
from PIL import Image, ImageDraw

S = 1024
TABLE, MAT, CARD, CARD_L, CARD_D, INK, RED, BLUE, MINT, YELLOW = (
    '#083739', '#0E6762', '#E2A652', '#F3C274', '#B17330', '#0D2730', '#F46359', '#67C2E2', '#97E1BE', '#FADC70')
img = Image.new('RGB', (S, S), MAT)
d = ImageDraw.Draw(img)
# Mat grid
for i in range(0, S, 64):
    w = 5 if (i // 64) % 5 == 0 else 2
    d.line([(i, 0), (i, S)], fill='#2E8A80', width=w)
    d.line([(0, i), (S, i)], fill='#2E8A80', width=w)

def rot(pts, a, cx, cy):
    c, s = math.cos(a), math.sin(a)
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts]

a = -math.radians(35)
cx, cy = 512, 540
# Knife silhouette (blade + handle) in local coords, x along the knife.
blade = [(-430, 0), (-250, -95), (60, -95), (60, 95), (-250, 95)]
handle = [(60, -80), (400, -80), (430, -50), (430, 50), (400, 80), (60, 80)]
guard = [(40, -118), (110, -118), (110, 118), (40, 118)]
shadow = lambda pts: [(x + 22, y + 26) for x, y in pts]
for poly in (blade, handle, guard):
    d.polygon(shadow(rot(poly, a, cx, cy)), fill='#0A4E4B')
# Blade: two bevel halves
d.polygon(rot([(-430, 0), (-250, -95), (60, -95), (60, 0)], a, cx, cy), fill=CARD_L)
d.polygon(rot([(-430, 0), (60, 0), (60, 95), (-250, 95)], a, cx, cy), fill=CARD)
d.polygon(rot(handle, a, cx, cy), fill=CARD)
d.polygon(rot([(60, 30), (430, 30), (430, 50), (400, 80), (60, 80)], a, cx, cy), fill=CARD_D)
d.polygon(rot(guard, a, cx, cy), fill=CARD_D)
for poly in (blade, handle, guard):
    d.line(rot(poly + [poly[0]], a, cx, cy), fill=INK, width=14, joint='curve')
# Lanyard hole
hx, hy = rot([(340, 0)], a, cx, cy)[0]
d.ellipse([hx - 30, hy - 30, hx + 30, hy + 30], fill=MAT, outline=INK, width=10)
# Red cut line along blade edge, blue dashed crease on the ridge.
d.line(rot([(-400, 22), (-240, 118), (40, 118)], a, cx, cy), fill=RED, width=18, joint='curve')
x = -380
while x < 30:
    d.line(rot([(x, 0), (x + 34, 0)], a, cx, cy), fill=BLUE, width=14)
    x += 62
img.save(sys.argv[1] if len(sys.argv) > 1 else 'AppIcon.png')
