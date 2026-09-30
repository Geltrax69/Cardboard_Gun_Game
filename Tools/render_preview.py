#!/usr/bin/env python3
"""Tiny flat-shaded software renderer for the JSON triangle dumps written by the core
tests. Used to eyeball fold kinematics without a Mac:
    python3 Tools/render_preview.py out/knife.json knife.png --yaw 30 --pitch 50
"""
import json, math, sys, argparse
import numpy as np
from PIL import Image, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('dst')
ap.add_argument('--yaw', type=float, default=0); ap.add_argument('--pitch', type=float, default=80)
ap.add_argument('--size', type=int, default=900); ap.add_argument('--fov', type=float, default=30)
ap.add_argument('--bg', default='#0E6762')
a = ap.parse_args()

tris = json.load(open(a.src))
pts = np.array([p for t in tris for p in t[0]], dtype=float)
center = (pts.min(0) + pts.max(0)) / 2
radius = np.linalg.norm(pts.max(0) - pts.min(0)) / 2
yaw, pitch = math.radians(a.yaw), math.radians(a.pitch)
dist = radius / math.tan(math.radians(a.fov) / 2) * 1.08
eye = center + dist * np.array([math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw)])
fwd = center - eye; fwd /= np.linalg.norm(fwd)
right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
up = np.cross(right, fwd)
f = 1 / math.tan(math.radians(a.fov) / 2)
S = a.size
light = np.array([-0.45, 0.85, -0.3]); light /= np.linalg.norm(light)

def hex2rgb(h): h = h.lstrip('#'); return np.array([int(h[i:i+2], 16) for i in (0, 2, 4)], dtype=float)

zbuf = np.full((S, S), np.inf)
img = np.zeros((S, S, 3)); img[:] = hex2rgb(a.bg)
for (tri, color) in tris:
    P = np.array(tri, dtype=float)
    n = np.cross(P[1] - P[0], P[2] - P[0]); ln = np.linalg.norm(n)
    if ln < 1e-12: continue
    n /= ln
    if np.dot(n, eye - P.mean(0)) < 0: continue  # back-face cull
    rel = P - eye
    z = rel @ fwd
    if (z <= 0.1).any(): continue
    sx = S / 2 + (rel @ right) / z * f * S / 2
    sy = S / 2 - (rel @ up) / z * f * S / 2
    shade = 0.62 + 0.38 * max(0.0, float(np.dot(n, light)))
    if color == '#0D2730': shade = 1.0
    c = np.clip(hex2rgb(color) * shade, 0, 255)
    x0, x1 = int(max(0, np.floor(sx.min()))), int(min(S - 1, np.ceil(sx.max())))
    y0, y1 = int(max(0, np.floor(sy.min()))), int(min(S - 1, np.ceil(sy.max())))
    if x1 < x0 or y1 < y0: continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax, bx, cx), (ay, by, cy) = sx, sy
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-9: continue
    w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
    w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
    w2 = 1 - w0 - w1
    inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
    depth = 1 / (w0 / z[0] + w1 / z[1] + w2 / z[2])
    if color == '#0D2730': depth = depth - 0.01
    sub = zbuf[y0:y1 + 1, x0:x1 + 1]
    m = inside & (depth < sub)
    sub[m] = depth[m]
    img[y0:y1 + 1, x0:x1 + 1][m] = c
Image.fromarray(img.astype(np.uint8)).save(a.dst)
print('wrote', a.dst)
