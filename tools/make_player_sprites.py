#!/usr/bin/env python3
"""Turn the high-res player renders into one pixel-art sprite sheet + SpriteFrames.

The source renders (1280x720 RGBA, one folder of PNGs per animation) are NOT in
this repo -- they live wherever the artist exported them. Point this at that
folder and it writes:

    scenes/assets/player_sheet.png    64x64 frames, one animation per row
    scenes/assets/player_frames.tres  SpriteFrames referencing that sheet
    scenes/assets/echo_sheet.png      the same frames, colours inverted
    scenes/assets/echo_frames.tres    SpriteFrames referencing that one

    python3 tools/make_player_sprites.py ~/Downloads/spriteSheets

Why it is more than a resize:

* The renders are NOT framed consistently -- `thrust` sits ~200px left of
  `idle`, `upAttack` ~27px lower. Every animation is re-anchored onto a shared
  ground line and body centre so the character doesn't jump when the game
  switches animation. The anchors are measured from the dark armour/boots
  (`_measure`), which is the only landmark the sword and cape don't disturb.
* They were not rendered at one camera distance either: the character is only
  ~65% as tall in `slash` and `upAttack` as in `idle`. Each animation gets its
  own zoom correction (`_zoom`) so the character is one size on screen.
* Downscaling 18x with a plain resize leaves anti-aliased mush. The pixel
  conversion itself -- premultiply, box filter, sharpen, grade, hard alpha,
  shared palette -- lives in tools/pixelize.py, shared with the cutscene
  soldier so the two can't drift into different looks.

Frames are picked evenly out of each source folder -- the renders run 9-60
frames, far more than reads at this size. Tweak ANIMATIONS to taste.

The echo (the clone a recall leaves behind) wears the player's frames as a
photographic negative. That is baked here rather than done with an invert
shader at runtime: a shader that fails to compile silently renders the sprite
normally, and a baked sheet also leaves enemy.gd's modulate hit flash working
on the echo exactly like on any other sprite enemy. Both sheets come out of
this one script, so they cannot drift apart.
"""

from __future__ import annotations

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from PIL import Image

import pixelize

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

## A row needs this many dark pixels to count as the body's bottom. The boots
## are chunky (50+ px across even in the zoomed-out renders); the sword's dark
## grip and guard are a thin diagonal. Without the test, the blade sweeping
## past the feet in `slash` reads as the floor 118px too low, and the whole
## animation floats ~9px up once its zoom is applied.
MIN_FOOT_RUN = 12

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
    # The jump render is one long arc: anticipation crouch, launch, tuck,
    # descent, touchdown, settle. `jump` takes the push-off and the tuck (the
    # crouch is already over by the time the player leaves the ground) and
    # `fall` takes the descent only -- it must NOT end on the landing frames,
    # or a long drop would hold a standing pose in mid-air.
    dict(name="jump", src="jump", count=6, span=(3, 9), fps=18.0, loop=False, anchor="first"),
    dict(name="fall", src="jump", count=4, span=(9, 12), fps=12.0, loop=False, anchor="first"),
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

## Overrides for the measured zoom correction, keyed by animation name.
## 1.0 = the source render is already at idle's camera distance; 1.5 = the
## character is two thirds the size there and gets blown up to match.
ZOOM: dict[str, float] = {}


# --- Measuring --------------------------------------------------------------

def _load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.int16)


def _measure(rgba: np.ndarray) -> tuple[float, float] | None:
    """Ground line and leg centre of one render, in source pixels.

    Keys off dark, unsaturated pixels: the armour, boots and gloves. The hood
    and cape are red and the shirt is white, so neither can drag the anchor
    around -- but the blade's grip and guard are dark too, which is what
    MIN_FOOT_RUN filters out.
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
    wide = np.nonzero(dark.sum(axis=1) >= MIN_FOOT_RUN)[0]
    if len(wide) == 0:
        return None
    feet_y = float(wide.max())
    ys, xs = np.nonzero(dark)
    legs = (ys > feet_y - 180) & (ys <= feet_y)  # boots and shins, not the torso
    if legs.sum() < 50:
        return None
    return feet_y, float(xs[legs].mean())


def _armour_area(rgba: np.ndarray) -> float:
    """How many dark armour pixels this render spends on the character.

    Area scales with the square of the camera's zoom, and the armour covers
    limbs and torso alike, so the median over an animation barely moves with
    the pose -- unlike the silhouette's height, which every crouch and cape
    flare throws off. This is what tells `slash` (rendered small) apart from
    `thrust` (rendered at idle's distance).
    """
    alpha = rgba[..., 3]
    rgb = rgba[..., :3]
    lum = rgb.mean(axis=2)
    top = rgb.max(axis=2)
    bottom = rgb.min(axis=2)
    sat = np.where(top > 0, (top - bottom) / np.maximum(top, 1), 0.0)
    return float(((alpha > 128) & (lum < 95) & (sat < 0.5)).sum())


def _folder(src_dir: str, spec: dict) -> list[str]:
    files = sorted(glob.glob(os.path.join(src_dir, spec["src"], "*.png")))
    if not files:
        raise SystemExit(f"no PNGs in {os.path.join(src_dir, spec['src'])}")
    return files


def _frame_paths(files: list[str], spec: dict) -> list[str]:
    first, last = spec["span"] or (0, len(files) - 1)
    last = min(last, len(files) - 1)
    window = files[first : last + 1]
    count = min(spec["count"], len(window))
    if count == 1:
        return [window[0]]
    step = (len(window) - 1) / (count - 1)
    return [window[round(i * step)] for i in range(count)]


# --- Conversion -------------------------------------------------------------

def _anchor(files: list[str], mode: str, idle_area: float) -> tuple[float, float, float]:
    """Ground line, body centre and zoom for one animation, in source pixels.

    Measured over the WHOLE render folder, never just the frames that get kept:
    `fall` is a slice of the jump render that never touches the ground, so its
    own frames have no floor to sit on. The folder does, and both slices of a
    render must land on the same line anyway.
    """
    marks, areas = [], []
    for path in files:
        rgba = _load(path)
        mark = _measure(rgba)
        if mark:
            marks.append(mark)
            areas.append(_armour_area(rgba))
    ground = max(m[0] for m in marks)
    center = marks[0][1] if mode == "first" else sum(m[1] for m in marks) / len(marks)
    return ground, center, float(np.sqrt(idle_area / np.median(areas)))


def _to_frame(rgba: np.ndarray, scale: float, src_anchor: tuple[float, float],
              nudge: tuple[float, float]) -> Image.Image:
    """Crop around the anchor and box-filter down to one FRAME x FRAME cell."""
    anchor = (ANCHOR_X + nudge[0], ANCHOR_Y + nudge[1])
    return pixelize.downscale(rgba, FRAME, scale, src_anchor, anchor,
                              SHADOW_LIFT, SATURATION)


def _harden_alpha(img: Image.Image) -> Image.Image:
    return pixelize.harden_alpha(img, ALPHA_CUTOFF)


def _build_palette(frames: list[Image.Image]) -> Image.Image:
    return pixelize.build_palette(frames, PALETTE_COLORS)


def _apply_palette(img: Image.Image, palette: Image.Image) -> Image.Image:
    return pixelize.apply_palette(img, palette)


# --- SpriteFrames -----------------------------------------------------------

def _kept_uids(path: str) -> tuple[str, str]:
    """The resource and texture uids already in `path`, if it exists.

    Godot stamps a uid into every resource it imports, and other scenes
    reference this SpriteFrames by that uid. Regenerating the file without it
    silently breaks those references, so an existing one is carried over.
    """
    if not os.path.exists(path):
        return "", ""
    text = open(path).read()
    res = re.search(r'\[gd_resource[^\]]*uid="([^"]+)"', text)
    tex = re.search(r'\[ext_resource[^\]]*uid="([^"]+)"', text)
    return (res.group(1) if res else ""), (tex.group(1) if tex else "")


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
    res_uid, tex_uid = _kept_uids(path)
    res_attr = f' uid="{res_uid}"' if res_uid else ""
    tex_attr = f' uid="{tex_uid}"' if tex_uid else ""
    header = (
        f"[gd_resource type=\"SpriteFrames\" load_steps={len(atlases) + 2} format=3{res_attr}]\n\n"
        f"[ext_resource type=\"Texture2D\"{tex_attr} path=\"{sheet_res}\" id=\"1_sheet\"]\n\n"
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
    echo_png = os.path.join(repo, "scenes/assets/echo_sheet.png")
    echo_tres = os.path.join(repo, "scenes/assets/echo_frames.tres")

    # Ground line and leg centre of the idle stance: everything aligns to this.
    idle_paths = sorted(glob.glob(os.path.join(src_dir, "idle", "*.png")))
    idle = [m for m in (_measure(_load(p)) for p in idle_paths) if m]
    idle_area = float(np.median([_armour_area(_load(p)) for p in idle_paths[::4]]))
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
        files = _folder(src_dir, spec)
        # Vertical: the lowest the boots reach anywhere in the render is its
        # floor. Horizontal: mean leg position, or frame 0 for animations that
        # travel across the frame.
        anim_ground, anim_center, measured_zoom = _anchor(files, spec["anchor"], idle_area)
        src_anchor = (anim_center, anim_ground)
        nudge = NUDGE.get(spec["name"], (0.0, 0.0))
        zoom = ZOOM.get(spec["name"], measured_zoom)
        paths = _frame_paths(files, spec)
        print(f"  {spec['name']:18s} {len(paths)} frames  dx={center_x - anim_center:+7.1f} "
              f"dy={ground_y - anim_ground:+6.1f} src px  zoom={zoom:.2f}")
        raw.append([_to_frame(_load(p), scale * zoom, src_anchor, nudge) for p in paths])
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

    # Same frames, negated. Alpha is left alone so the silhouette is identical.
    negative = np.asarray(sheet).copy()
    negative[..., :3] = 255 - negative[..., :3]
    Image.fromarray(negative, "RGBA").save(echo_png)
    _write_tres(echo_tres, "res://scenes/assets/echo_sheet.png", rows)

    print(f"\nwrote {out_png} ({sheet.width}x{sheet.height}) and {out_tres}")
    print(f"wrote {echo_png} (inverted) and {echo_tres}")


if __name__ == "__main__":
    main()
