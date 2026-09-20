#!/usr/bin/env python3
"""Turn the painting-soldier renders into the final cutscene sprite sheet.

Like make_player_sprites.py (and sharing its pixel conversion via pixelize.py),
but a single animation for a single cutscene, so there is no per-animation
anchoring or zoom matching here -- one camera, one take. It writes:

    scenes/assets/soldier_sheet.png    192x192 frames, 11 per row
    scenes/assets/soldier_frames.tres  SpriteFrames with one "paint" animation

    python3 tools/make_soldier_sprite.py ~/Downloads/soldierPainting

Two edits happen before the pixel conversion, both on the full-res renders so
they go through the same filter and palette as everything else:

* **Black fatigues -> khaki.** The outfit is flat pure black (0,0,0), which
  would be trivial to swap -- except his hair is pure black too, and the two
  touch at the nape, so a flood fill grabs both. They get separated
  geometrically instead: the silhouette is ~50px wide through the head and
  neck and flares past 80px at the shoulders, which locates the neck line
  (`_neck_row`). Below it every black pixel is uniform; above it only the
  pixels inside the head's own width are (that is the hair) -- otherwise the
  collar on top of the shoulders stays a black wedge.
* **Square moustache.** Anchored on the eyes rather than the head box, because
  he turns as he looks up and a fixed offset would slide off his face. The two
  specular highlights in his eyes are the only bright desaturated pixels up
  there, so they are easy to find, and they give a midpoint to centre on and a
  separation to scale by. They only resolve once he is facing the camera
  (~frame 69 on); before that he is in profile or turned away, where a
  front-on moustache would be wrong anyway, so it is simply not drawn.

He is drawn at BODY_HEIGHT px tall in a FRAME px cell, feet on ANCHOR_Y, and
every frame uses ONE anchor measured across the whole take -- his drift and
step as he turns are the animation, not framing error to be corrected.
"""

from __future__ import annotations

import glob
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelize

# --- Output geometry --------------------------------------------------------

FRAME = 192
COLUMNS = 11
## He stands this tall in the cell: half the 360px screen, which is what makes
## a ~6px moustache legible. Leaves a margin for the brush and his step.
BODY_HEIGHT = 178.0
ANCHOR_Y = 186.0
FPS = 16.0

PALETTE_COLORS = 32
ALPHA_CUTOFF = 96
SHADOW_LIFT = 42.0
SATURATION = 1.2

# --- The edits --------------------------------------------------------------

KHAKI = (111, 116, 68)
## Boots, belt and hip pouches. Without a second tone the whole outfit is one
## flat green shape at sprite size -- the source has no shading to fall back on.
WEBBING = (58, 56, 38)
BOOT_FROM = 0.87        # fraction of body height where the boots start
BELT_FROM, BELT_TO = 0.50, 0.595

## Dark brown rather than black: his hair reads that way once graded, and a
## pure-black square would be the only true black on him.
MOUSTACHE = (34, 26, 22)
## Sized and placed from the eye separation.
MOUSTACHE_WIDTH = 0.55
MOUSTACHE_HEIGHT = 0.26
MOUSTACHE_DROP = 0.79


def _load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA")).astype(int)


def _neck_row(opaque: np.ndarray, top: int, bottom: int) -> int:
    """Row where the silhouette stops being head-and-neck and becomes shoulders."""
    width = opaque.sum(axis=1)
    head = np.median(width[top : top + 80])
    for row in range(top + 40, top + int((bottom - top) * 0.30)):
        if width[row] > head * 1.6:
            return row
    return top + int((bottom - top) * 0.17)


def _recolour(rgba: np.ndarray) -> np.ndarray:
    opaque = rgba[..., 3] > 128
    black = opaque & (rgba[..., :3].max(axis=2) <= 6)
    ys, _ = np.nonzero(opaque)
    top, bottom = int(ys.min()), int(ys.max())
    height = bottom - top
    rows = np.arange(rgba.shape[0])[:, None]
    cols = np.arange(rgba.shape[1])[None, :]

    neck = _neck_row(opaque, top, bottom)
    head_x = np.nonzero(opaque[top:neck].any(axis=0))[0]
    # Above the neck, black is hair only where it is within the head's width.
    hair = (rows < neck) & (cols >= head_x.min()) & (cols <= head_x.max())
    clothes = black & ~hair

    out = rgba.copy()
    out[clothes] = list(KHAKI) + [255]
    out[clothes & (rows >= top + height * BOOT_FROM)] = list(WEBBING) + [255]
    out[clothes & (rows >= top + height * BELT_FROM)
                & (rows < top + height * BELT_TO)] = list(WEBBING) + [255]
    return out


def _eyes(rgba: np.ndarray) -> tuple[float, float, float] | None:
    """Centre, line and separation of the eyes, or None if he isn't facing us."""
    alpha = rgba[..., 3]
    lum = rgba[..., :3].mean(axis=2)
    top_c = rgba[..., :3].max(axis=2)
    bottom_c = rgba[..., :3].min(axis=2)
    sat = np.where(top_c > 0, (top_c - bottom_c) / np.maximum(top_c, 1), 0.0)
    ys, _ = np.nonzero(alpha > 128)
    band = np.zeros_like(alpha, bool)
    band[int(ys.min()) : int(ys.min()) + 130, :] = True
    bright = (alpha > 128) & band & (lum > 140) & (sat < 0.18)
    if bright.sum() < 8:
        return None
    by, bx = np.nonzero(bright)
    if bx.max() - bx.min() < 8:
        return None
    left = bx < bx.mean()
    if left.sum() < 3 or (~left).sum() < 3:
        return None
    lx, rx = bx[left].mean(), bx[~left].mean()
    return (lx + rx) / 2.0, float(by.mean()), float(rx - lx)


def _add_moustache(rgba: np.ndarray) -> np.ndarray:
    eyes = _eyes(rgba)
    if eyes is None:
        return rgba
    cx, cy, sep = eyes
    half_w = sep * MOUSTACHE_WIDTH / 2.0
    half_h = sep * MOUSTACHE_HEIGHT / 2.0
    cy += sep * MOUSTACHE_DROP
    img = Image.fromarray(rgba.astype(np.uint8), "RGBA").copy()
    ImageDraw.Draw(img).rectangle(
        [cx - half_w, cy - half_h, cx + half_w, cy + half_h],
        fill=MOUSTACHE + (255,),
    )
    return np.asarray(img).astype(int)


# --- Sheet ------------------------------------------------------------------

def _kept_uids(path: str) -> tuple[str, str]:
    """Carry over the uids Godot stamped in, so re-running is safe."""
    if not os.path.exists(path):
        return "", ""
    text = open(path).read()
    res = re.search(r'\[gd_resource[^\]]*uid="([^"]+)"', text)
    tex = re.search(r'\[ext_resource[^\]]*uid="([^"]+)"', text)
    return (res.group(1) if res else ""), (tex.group(1) if tex else "")


def _write_tres(path: str, sheet_res: str, count: int) -> None:
    atlases, entries = [], []
    for i in range(count):
        col, row = i % COLUMNS, i // COLUMNS
        atlases.append(
            f'[sub_resource type="AtlasTexture" id="AtlasTexture_paint{i}"]\n'
            f'atlas = ExtResource("1_sheet")\n'
            f"region = Rect2({col * FRAME}, {row * FRAME}, {FRAME}, {FRAME})\n"
        )
        entries.append('{\n"duration": 1.0,\n'
                       f'"texture": SubResource("AtlasTexture_paint{i}")\n}}')
    res_uid, tex_uid = _kept_uids(path)
    res_attr = f' uid="{res_uid}"' if res_uid else ""
    tex_attr = f' uid="{tex_uid}"' if tex_uid else ""
    header = (
        f'[gd_resource type="SpriteFrames" load_steps={len(atlases) + 2} format=3{res_attr}]\n\n'
        f'[ext_resource type="Texture2D"{tex_attr} path="{sheet_res}" id="1_sheet"]\n\n'
    )
    body = (
        "\n".join(atlases)
        + "\n[resource]\nanimations = [{\n"
        + f'"frames": [{", ".join(entries)}],\n'
        + '"loop": 0,\n"name": &"paint",\n'
        + f'"speed": {FPS}\n}}]\n'
    )
    with open(path, "w") as f:
        f.write(header + body)


def main() -> None:
    src_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads/soldierPainting")
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_png = os.path.join(repo, "scenes/assets/soldier_sheet.png")
    out_tres = os.path.join(repo, "scenes/assets/soldier_frames.tres")

    files = sorted(glob.glob(os.path.join(src_dir, "*.png")))
    if not files:
        raise SystemExit(f"no PNGs in {src_dir}")

    # One anchor for the whole take: the lowest his boots ever reach, and the
    # centre of everything he covers. His drift between frames is animation.
    left = top = 10 ** 6
    right = bottom = -10 ** 6
    for path in files:
        alpha = _load(path)[..., 3]
        ys, xs = np.nonzero(alpha > 16)
        left, right = min(left, xs.min()), max(right, xs.max())
        top, bottom = min(top, ys.min()), max(bottom, ys.max())
    scale = BODY_HEIGHT / (bottom - top)
    src_anchor = ((left + right) / 2.0, float(bottom))
    anchor = (FRAME / 2.0, ANCHOR_Y)
    print(f"{len(files)} frames | union bbox x {left}-{right} y {top}-{bottom} "
          f"-> scale {scale:.4f} ({FRAME / scale:.0f}px window)")

    cells = []
    for i, path in enumerate(files):
        rgba = _add_moustache(_recolour(_load(path)))
        cells.append(pixelize.downscale(rgba, FRAME, scale, src_anchor, anchor,
                                        SHADOW_LIFT, SATURATION))
        if (i + 1) % 20 == 0:
            print(f"  {i + 1}/{len(files)}")

    hard = [pixelize.harden_alpha(c, ALPHA_CUTOFF) for c in cells]
    palette = pixelize.build_palette(hard, PALETTE_COLORS)
    rows = (len(hard) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (FRAME * COLUMNS, FRAME * rows), (0, 0, 0, 0))
    for i, cell in enumerate(hard):
        sheet.paste(pixelize.apply_palette(cell, palette),
                    ((i % COLUMNS) * FRAME, (i // COLUMNS) * FRAME))

    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    sheet.save(out_png)
    _write_tres(out_tres, "res://scenes/assets/soldier_sheet.png", len(hard))
    print(f"\nwrote {out_png} ({sheet.width}x{sheet.height}, {len(hard)} frames "
          f"at {FPS}fps = {len(hard) / FPS:.1f}s) and {out_tres}")


if __name__ == "__main__":
    main()
