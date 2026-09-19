#!/usr/bin/env python3
"""Turn the high-res player renders into one pixel-art sprite sheet + SpriteFrames.

The source renders (1280x720 RGBA, one folder of PNGs per animation) are NOT in
this repo -- they live wherever the artist exported them. Point this at that
folder and it writes:

    scenes/assets/player_sheet.png    64x64 frames, one animation per row
    scenes/assets/player_frames.tres  SpriteFrames referencing that sheet

    python3 tools/make_player_sprites.py ~/Downloads/spriteSheets

Why it is more than a resize:

* The renders are NOT framed consistently -- `thrust` sits ~200px left of
  `idle`, `upAttack` ~27px lower. Every animation is re-anchored onto a shared
  ground line and body centre so the character doesn't jump when the game
  switches animation. The anchors are measured from the dark armour/boots
  (`_measure`), which is the only landmark the sword and cape don't disturb.
* Downscaling 18x with a plain resize leaves anti-aliased mush. Frames are
  premultiplied before the box filter (no dark halo from transparent black),
  re-sharpened, alpha-thresholded to hard edges, and mapped onto one shared
  palette so every animation uses the same colours.

Frames are picked evenly out of each source folder -- the renders run 9-60
frames, far more than reads at this size. Tweak ANIMATIONS to taste.
"""

from __future__ import annotations

import glob
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

# --- Output geometry --------------------------------------------------------

FRAME = 64
## The character stands this tall in the frame: one 32px tile, ~1.3x the
## player's 12x24 collision box.
BODY_HEIGHT = 32.0
## Where the character's feet and centre land inside the frame. The anchor sits
## left of centre because the sprite faces right and the sword needs the room;
## player.gd offsets the node so this pixel is the node origin, which keeps
## flipping (scale.x = -1) mirroring around the character instead of the frame.
ANCHOR_X = 26.0
ANCHOR_Y = 46.0

PALETTE_COLORS = 32
ALPHA_CUTOFF = 96
## The renders are lit dark: at 32px the armour and boots crush to black and
## the legs vanish against a dark level. Colours are squeezed into
## [SHADOW_LIFT, 255] and saturated a little so the silhouette holds up.
SHADOW_LIFT = 42.0
SATURATION = 1.2

# --- Animations -------------------------------------------------------------
# name:    animation name in the SpriteFrames (what player.gd asks for)
# src:     source folder
# count:   frames kept, picked evenly across `span`
# span:    (first, last) source frame index, inclusive; None = the whole folder
# fps:     playback speed. player.gd drives frames from tick stamps, but it
#          reads the speed back out of the resource so it lives in one place.
# loop:    loops forever vs plays once and holds the last frame
# anchor:  "mean" averages the leg position over every frame (stances that stay
#          put or cycle); "first" uses frame 0 (lunges that travel).
ANIMATIONS = [
    dict(name="idle", src="idle", count=8, span=None, fps=8.0, loop=True, anchor="mean"),
    dict(name="run", src="runCycle", count=8, span=None, fps=16.0, loop=True, anchor="mean"),
    dict(name="jump", src="jump", count=6, span=(0, 10), fps=18.0, loop=False, anchor="first"),
    dict(name="fall", src="jump", count=4, span=(11, 18), fps=10.0, loop=False, anchor="first"),
    dict(name="dash", src="dash", count=5, span=None, fps=36.0, loop=False, anchor="first"),
    dict(name="slash", src="slash", count=7, span=None, fps=24.0, loop=False, anchor="mean"),
    dict(name="thrust", src="thrust", count=7, span=None, fps=24.0, loop=False, anchor="mean"),
    dict(name="air_slash", src="jumpThrust", count=7, span=None, fps=24.0, loop=False, anchor="mean"),
    dict(name="dash_slash", src="dashSlash", count=7, span=None, fps=24.0, loop=False, anchor="first"),
    dict(name="dash_thrust", src="dashAttack", count=7, span=None, fps=24.0, loop=False, anchor="first"),
    dict(name="up_slash", src="upAttack", count=7, span=None, fps=24.0, loop=False, anchor="mean"),
    dict(name="air_up_slash", src="jumpUpAttack", count=7, span=None, fps=24.0, loop=False, anchor="mean"),
    dict(name="down_slash", src="jumpSlashDown", count=7, span=None, fps=24.0, loop=False, anchor="mean"),
    dict(name="parry", src="parry", count=7, span=None, fps=20.0, loop=False, anchor="mean"),
]

## Hand tweaks in FINAL pixels, applied after the automatic anchoring.
## Positive x moves the character right in frame, positive y moves it down.
NUDGE: dict[str, tuple[float, float]] = {}


# --- Measuring --------------------------------------------------------------

def _load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.int16)


def _measure(rgba: np.ndarray) -> tuple[float, float] | None:
    """Ground line and leg centre of one render, in source pixels.

    Keys off dark, unsaturated pixels: the armour, boots and gloves. The sword
    is bright, the hood and cape are red, the shirt is white -- none of them
    survive the mask, so a flourish of the blade can't drag the anchor around.
    """
    alpha = rgba[..., 3]
    rgb = rgba[..., :3]
    lum = rgb.mean(axis=2)
    top = rgb.max(axis=2)
    bottom = rgb.min(axis=2)
    sat = np.where(top > 0, (top - bottom) / np.maximum(top, 1), 0.0)
    dark = (alpha > 128) & (lum < 95) & (sat < 0.5)
    if dark.sum() < 200:
        return None
    ys, xs = np.nonzero(dark)
    feet_y = float(ys.max())
    legs = ys > feet_y - 180  # boots and shins, not the torso
    return feet_y, float(xs[legs].mean())


def _frame_paths(src_dir: str, spec: dict) -> list[str]:
    files = sorted(glob.glob(os.path.join(src_dir, spec["src"], "*.png")))
    if not files:
        raise SystemExit(f"no PNGs in {os.path.join(src_dir, spec['src'])}")
    first, last = spec["span"] or (0, len(files) - 1)
    last = min(last, len(files) - 1)
    window = files[first : last + 1]
    count = min(spec["count"], len(window))
    if count == 1:
        return [window[0]]
    step = (len(window) - 1) / (count - 1)
    return [window[round(i * step)] for i in range(count)]


# --- Conversion -------------------------------------------------------------

def _to_frame(rgba: np.ndarray, scale: float, src_anchor: tuple[float, float],
              nudge: tuple[float, float]) -> Image.Image:
    """Crop around the anchor and box-filter down to one FRAME x FRAME cell."""
    window = FRAME / scale
    src_x, src_y = src_anchor
    x0 = src_x - (ANCHOR_X + nudge[0]) / scale
    y0 = src_y - (ANCHOR_Y + nudge[1]) / scale

    # Premultiply so the filter never averages in transparent black.
    rgb = rgba[..., :3].astype(np.float32)
    alpha = rgba[..., 3].astype(np.float32) / 255.0
    premul = np.dstack([rgb * alpha[..., None], alpha * 255.0]).astype(np.uint8)

    canvas = Image.new("RGBA", (round(window), round(window)), (0, 0, 0, 0))
    canvas.paste(Image.fromarray(premul, "RGBA"), (round(-x0), round(-y0)))
    small = np.asarray(canvas.resize((FRAME, FRAME), Image.BOX)).astype(np.float32)

    a = small[..., 3:4] / 255.0
    rgb = np.zeros_like(small[..., :3])
    np.divide(small[..., :3], np.maximum(a, 1e-4), out=rgb, where=a > 0)
    out = np.dstack([np.clip(rgb, 0, 255), small[..., 3]]).astype(np.uint8)
    img = Image.fromarray(_grade(out), "RGBA")
    # 18x reduction is soft; put the edges back before quantising.
    img = img.filter(ImageFilter.UnsharpMask(radius=1.4, percent=90, threshold=2))
    return img


def _grade(rgba: np.ndarray) -> np.ndarray:
    """Lift the shadows and push the saturation so the sprite reads at 32px."""
    rgb = rgba[..., :3].astype(np.float32)
    grey = rgb.mean(axis=2, keepdims=True)
    rgb = grey + (rgb - grey) * SATURATION
    rgb = SHADOW_LIFT + rgb * (255.0 - SHADOW_LIFT) / 255.0
    return np.dstack([np.clip(rgb, 0, 255), rgba[..., 3]]).astype(np.uint8)


def _harden_alpha(img: Image.Image) -> Image.Image:
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r, g, b, a.point(lambda v: 255 if v >= ALPHA_CUTOFF else 0)))


def _build_palette(frames: list[Image.Image]) -> Image.Image:
    """One adaptive palette shared by every animation, from opaque pixels only."""
    pixels = []
    for img in frames:
        arr = np.asarray(img)
        opaque = arr[arr[..., 3] > 0][:, :3]
        if len(opaque):
            pixels.append(opaque)
    stacked = np.concatenate(pixels)
    strip = Image.fromarray(stacked.reshape(-1, 1, 3).astype(np.uint8), "RGB")
    return strip.quantize(colors=PALETTE_COLORS, method=Image.MEDIANCUT)


def _apply_palette(img: Image.Image, palette: Image.Image) -> Image.Image:
    alpha = img.getchannel("A")
    flat = img.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
    out = flat.convert("RGB").convert("RGBA")
    out.putalpha(alpha)
    return out


# --- SpriteFrames -----------------------------------------------------------

def _write_tres(path: str, sheet_res: str, rows: list[tuple[dict, int]]) -> None:
    atlases, animations = [], []
    for spec, frames in rows:
        row = len(animations)
        entries = []
        for col in range(frames):
            ident = f"{spec['name']}_{col}"
            atlases.append(
                f'[sub_resource type="AtlasTexture" id="AtlasTexture_{ident}"]\n'
                f'atlas = ExtResource("1_sheet")\n'
                f"region = Rect2({col * FRAME}, {row * FRAME}, {FRAME}, {FRAME})\n"
            )
            entries.append(
                '{\n"duration": 1.0,\n'
                f'"texture": SubResource("AtlasTexture_{ident}")\n}}'
            )
        animations.append(
            "{\n"
            f'"frames": [{", ".join(entries)}],\n'
            f'"loop": {1 if spec["loop"] else 0},\n'
            f'"name": &"{spec["name"]}",\n'
            f'"speed": {spec["fps"]}\n'
            "}"
        )
    header = (
        f"[gd_resource type=\"SpriteFrames\" load_steps={len(atlases) + 2} format=3]\n\n"
        f"[ext_resource type=\"Texture2D\" path=\"{sheet_res}\" id=\"1_sheet\"]\n\n"
    )
    body = "\n".join(atlases) + "\n[resource]\nanimations = [" + ", ".join(animations) + "]\n"
    with open(path, "w") as f:
        f.write(header + body)


# --- Main -------------------------------------------------------------------

def main() -> None:
    src_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads/spriteSheets")
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_png = os.path.join(repo, "scenes/assets/player_sheet.png")
    out_tres = os.path.join(repo, "scenes/assets/player_frames.tres")

    # Ground line and leg centre of the idle stance: everything aligns to this.
    idle = [_measure(_load(p)) for p in sorted(glob.glob(os.path.join(src_dir, "idle", "*.png")))]
    idle = [m for m in idle if m]
    ground_y = max(m[0] for m in idle)
    center_x = sum(m[1] for m in idle) / len(idle)
    body_px = ground_y - min(
        np.nonzero(_load(p)[..., 3] > 16)[0].min()
        for p in sorted(glob.glob(os.path.join(src_dir, "idle", "*.png")))[:1]
    )
    scale = BODY_HEIGHT / body_px
    print(f"idle: ground_y={ground_y:.0f} center_x={center_x:.0f} body={body_px:.0f}px "
          f"-> scale {scale:.5f} (window {FRAME / scale:.0f}px)")

    rows, raw = [], []
    for spec in ANIMATIONS:
        paths = _frame_paths(src_dir, spec)
        loaded = [_load(p) for p in paths]
        marks = [m for m in (_measure(r) for r in loaded) if m]
        # Vertical: the lowest the boots ever reach is this animation's floor.
        # Horizontal: mean leg position, or frame 0 for animations that travel.
        anim_ground = max(m[0] for m in marks)
        anim_center = marks[0][1] if spec["anchor"] == "first" else sum(m[1] for m in marks) / len(marks)
        src_anchor = (anim_center, anim_ground)
        nudge = NUDGE.get(spec["name"], (0.0, 0.0))
        print(f"  {spec['name']:18s} {len(paths)} frames  dx={center_x - anim_center:+7.1f} "
              f"dy={ground_y - anim_ground:+6.1f} src px")
        raw.append([_to_frame(r, scale, src_anchor, nudge) for r in loaded])
        rows.append((spec, len(paths)))

    flat = [_harden_alpha(img) for row in raw for img in row]
    palette = _build_palette(flat)
    sheet = Image.new("RGBA", (FRAME * max(len(r) for r in raw), FRAME * len(raw)), (0, 0, 0, 0))
    i = 0
    for r, row in enumerate(raw):
        for c in range(len(row)):
            sheet.paste(_apply_palette(flat[i], palette), (c * FRAME, r * FRAME))
            i += 1

    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    sheet.save(out_png)
    _write_tres(out_tres, "res://scenes/assets/player_sheet.png", rows)
    print(f"\nwrote {out_png} ({sheet.width}x{sheet.height}) and {out_tres}")


if __name__ == "__main__":
    main()
