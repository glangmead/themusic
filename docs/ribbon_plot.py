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
theta_grid_step = 20  # ~15 visible circumferential lines
x_grid_step = 5       # ~4 visible axial lines

# Camera translated up (positive Z) toward the top of the ribbon,
# still looking along +Y. This puts the nearby ribbon surface close
# overhead and shows it receding downward into the distance.
cam = np.array([0.0, 0.0, 0.9375 * radius])
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

# Sort by depth (far first = painter's algorithm)
order = np.argsort(depths)[::-1]
quads = [quads[i] for i in order]
colors = [colors[i] for i in order]

face_colors = ['white'] * len(colors)

# --- Render ---
fig, ax = plt.subplots(figsize=(16, 10), facecolor='black')
ax.set_facecolor('black')

# Dense mesh with no edges for smooth curvature
poly = PolyCollection(quads, facecolors=face_colors, edgecolors='none', alpha=0.9)
ax.add_collection(poly)

# Overlay sparse grid lines
# Circumferential lines (constant x, varying theta)
for i in range(0, n_x, x_grid_step):
    line_px, line_py = [], []
    for j in range(n_theta):
        t = theta[j]
        x = xs[i]
        y = radius * np.cos(t)
        z = radius * np.sin(t)
        p = np.array([x, y, z])
        if p[1] - cam[1] < 0.01:
            if line_px:
                ax.plot(line_px, line_py, color='black', linewidth=0.4)
                line_px, line_py = [], []
            continue
        px, py = project(p)
        line_px.append(px)
        line_py.append(py)
    if line_px:
        ax.plot(line_px, line_py, color='black', linewidth=0.4)

# Axial lines (constant theta, varying x)
for j in range(0, n_theta, theta_grid_step):
    line_px, line_py = [], []
    for i in range(n_x):
        t = theta[j]
        x = xs[i]
        y = radius * np.cos(t)
        z = radius * np.sin(t)
        p = np.array([x, y, z])
        if p[1] - cam[1] < 0.01:
            continue
        px, py = project(p)
        line_px.append(px)
        line_py.append(py)
    if line_px:
        ax.plot(line_px, line_py, color='black', linewidth=0.4)


ax.set_xlim(0, img_w)
ax.set_ylim(img_h, 0)
ax.set_aspect('equal')
ax.axis('off')

plt.tight_layout(pad=0)
plt.savefig('/Users/glangmead/proj/themusic/.claude/worktrees/relaxed-williams/ribbon_plot.png',
            dpi=150, facecolor='black', bbox_inches='tight', pad_inches=0)
plt.savefig('/Users/glangmead/proj/themusic/.claude/worktrees/relaxed-williams/ribbon_plot.svg',
            facecolor='none', transparent=True, bbox_inches='tight', pad_inches=0)
print("Done")
