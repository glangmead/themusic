import numpy as np
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.colors import Normalize
from matplotlib import cm

# --- Cylinder geometry ---
# Axis along X (horizontal). Viewer at origin, looking along +Y.
# Wall curves up/down (Z) and wraps left/right (via angle).
radius = 4.0
width = 0.4  # ribbon width along X axis

# Dense mesh for smooth curvature, sparse grid for visible lines
n_theta = 300
n_x = 20
theta = np.linspace(0, 2 * np.pi, n_theta)
xs = np.linspace(-width / 2, width / 2, n_x)

# Sparse grid line intervals (every Nth mesh line is visible)
theta_grid_step = 10  # ~30 visible axial (cross-ribbon) lines
x_grid_step = 2        # ~10 visible lengthwise (along-ribbon) lines

# Camera translated up (positive Z) toward the top of the ribbon,
# still looking along +Y. This puts the nearby ribbon surface close
# overhead and shows it receding downward into the distance.
cam = np.array([0.0, 0.0, -0.9375 * radius])
fov_h = 160  # degrees horizontal
fov_v = 120  # degrees vertical
img_w, img_h = 1600, 1000

# Project a 3D point to screen (spherical projection for wide FOV)
def project(p):
    d = p - cam
    # azimuth (horizontal angle from +Y axis, in XY plane)
    az = np.arctan2(d[0], d[1])  # left-right
    # elevation (vertical angle from XY plane)
    el = np.arctan2(d[2], np.sqrt(d[0]**2 + d[1]**2))  # up-down
    # Map to pixel coordinates
    px = (az / np.radians(fov_h / 2) * 0.5 + 0.5) * img_w
    py = (0.5 - el / np.radians(fov_v / 2) * 0.5) * img_h
    return px, py

# Build quad mesh on the cylinder and project each quad
quads = []
colors = []
depths = []

for i in range(n_x - 1):
    for j in range(n_theta - 1):
        # Four corners of the quad
        corners_3d = []
        for di, dj in [(0, 0), (1, 0), (1, 1), (0, 1)]:
            t = theta[j + dj]
            x = xs[i + di]
            y = radius * np.cos(t)
            z = radius * np.sin(t)
            corners_3d.append(np.array([x, y, z]))

        # Only render quads in front of camera (y > 0 for at least some corners)
        ys = [c[1] for c in corners_3d]
        if max(ys) < 0.05:
            continue

        # Project to 2D
        corners_2d = []
        valid = True
        for c in corners_3d:
            if c[1] < 0.01:
                valid = False
                break
            px, py = project(c)
            corners_2d.append([px, py])
        if not valid:
            continue

        quads.append(corners_2d)
        # Color by theta (angle around cylinder)
        avg_theta = (theta[j] + theta[j + 1]) / 2
        colors.append(avg_theta)
        # Depth = average distance
        avg_depth = np.mean([np.linalg.norm(c - cam) for c in corners_3d])
        depths.append(avg_depth)

# --- Fog / atmospheric attenuation ---
# Exponential falloff: brightness = exp(-fog_density * distance)
fog_density = 0.08
depths = np.array(depths)
min_depth = depths.min()
fog = np.exp(-fog_density * (depths - min_depth))  # 1.0 at nearest, fading toward 0

# Sort by depth (far first = painter's algorithm)
order = np.argsort(depths)[::-1]
quads = [quads[i] for i in order]
fog = fog[order]

# Base ribbon color (grass green)
ribbon_color = np.array([0.35, 0.75, 0.25])

# Face color: ribbon_color * fog, fading toward black
face_colors = [(*(ribbon_color * f),) for f in fog]

# --- Render ---
fig, ax = plt.subplots(figsize=(16, 10), facecolor='black')
ax.set_facecolor('black')

# Edge colors match faces to fill SVG anti-aliasing seams
poly = PolyCollection(quads, facecolors=face_colors, edgecolors=face_colors,
                      linewidths=0.3, antialiaseds=False, alpha=1.0)
ax.add_collection(poly)

# Grid line parameters
grid_base_color = np.array([0.15, 0.35, 0.1])  # dark green grid lines
grid_fog_strength = 0.3  # how much fog lightens the lines (0=none, 1=full)
grid_lw_near = 0.8    # linewidth at closest point
grid_lw_far = 0.01     # linewidth at farthest point

# Overlay sparse grid lines with per-segment fog (color + width)
from matplotlib.collections import LineCollection

def grid_fog_factor(p3d):
    """Return fog factor 0..1 (1=near, 0=far) for a 3D point."""
    d = np.linalg.norm(p3d - cam)
    return np.exp(-fog_density * (d - min_depth))

def draw_fogged_line(pts_2d, pts_3d):
    """Draw a polyline as individually colored and sized segments."""
    if len(pts_2d) < 2:
        return
    segments = []
    seg_colors = []
    seg_widths = []
    for k in range(len(pts_2d) - 1):
        segments.append([pts_2d[k], pts_2d[k + 1]])
        mid_3d = 0.5 * (pts_3d[k] + pts_3d[k + 1])
        f = grid_fog_factor(mid_3d)
        # Color: blend grid toward ribbon color as distance increases
        c = grid_base_color + grid_fog_strength * ribbon_color * (1.0 - f)
        seg_colors.append(tuple(np.clip(c, 0, 1)))
        # Width: interpolate between near and far
        w = grid_lw_far + (grid_lw_near - grid_lw_far) * f
        seg_widths.append(w)
    lc = LineCollection(segments, colors=seg_colors, linewidths=seg_widths)
    ax.add_collection(lc)

# Lengthwise lines (constant x, varying theta)
for i in range(0, n_x, x_grid_step):
    pts_2d, pts_3d = [], []
    for j in range(n_theta):
        t = theta[j]
        x = xs[i]
        y = radius * np.cos(t)
        z = radius * np.sin(t)
        p = np.array([x, y, z])
        if p[1] - cam[1] < 0.01:
            draw_fogged_line(pts_2d, pts_3d)
            pts_2d, pts_3d = [], []
            continue
        px, py = project(p)
        pts_2d.append([px, py])
        pts_3d.append(p)
    draw_fogged_line(pts_2d, pts_3d)

# Cross-ribbon lines (constant theta, varying x)
for j in range(0, n_theta, theta_grid_step):
    pts_2d, pts_3d = [], []
    for i in range(n_x):
        t = theta[j]
        x = xs[i]
        y = radius * np.cos(t)
        z = radius * np.sin(t)
        p = np.array([x, y, z])
        if p[1] - cam[1] < 0.01:
            continue
        px, py = project(p)
        pts_2d.append([px, py])
        pts_3d.append(p)
    draw_fogged_line(pts_2d, pts_3d)


ax.set_xlim(0, img_w)
ax.set_ylim(img_h, 0)
ax.set_aspect('equal')
ax.axis('off')

plt.tight_layout(pad=0)
plt.savefig('/Users/glangmead/proj/themusic/docs/ribbon_plot.png',
            dpi=150, facecolor='black', bbox_inches='tight', pad_inches=0)
plt.savefig('/Users/glangmead/proj/themusic/docs/ribbon_plot.svg',
            facecolor='none', transparent=True, bbox_inches='tight', pad_inches=0)
print("Done")
