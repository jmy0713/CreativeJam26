"""Shared pixel-art conversion: high-res render in, one sprite cell out.

Both make_player_sprites.py and make_soldier_sprite.py run renders through
this, so the two can't drift into looking like they came from different games.
Everything here is a pure function over one frame; the callers own the framing,
the anchors and the sheet layout, which is where the two jobs actually differ.

The steps exist for these reasons:

* **Premultiply before the filter.** Transparent pixels in these renders are
  transparent *black*. Box-filtering straight RGBA averages that black into
  every edge and leaves a dark halo; premultiplying and dividing back out
  after keeps edges the colour they should be.
* **Unsharp after.** An 18x reduction is mush without it.
* **Grade.** The renders are lit dark. At sprite size the darks crush together
  and the silhouette stops reading against a dark level, so colours get
  squeezed into [shadow_lift, 255] and saturated a little.
* **Hard alpha.** Pixel art has no soft edges; anything under the cutoff is
  cut away entirely rather than left as a fringe.
* **One shared palette.** Quantising each frame on its own gives every frame
  slightly different colours, which flickers once they play in sequence.
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageFilter


def downscale(rgba: np.ndarray, frame: int, scale: float,
              src_anchor: tuple[float, float], anchor: tuple[float, float],
              shadow_lift: float, saturation: float) -> Image.Image:
    """Crop `rgba` around `src_anchor` and box-filter it into one `frame` cell.

    `src_anchor` is the pixel in the render that should land on `anchor` in the
    output cell -- for a platformer sprite, the character's feet. `scale` is
    output pixels per source pixel.
    """
    window = frame / scale
    x0 = src_anchor[0] - anchor[0] / scale
    y0 = src_anchor[1] - anchor[1] / scale

    rgb = rgba[..., :3].astype(np.float32)
    alpha = rgba[..., 3].astype(np.float32) / 255.0
    premul = np.dstack([rgb * alpha[..., None], alpha * 255.0]).astype(np.uint8)

    canvas = Image.new("RGBA", (round(window), round(window)), (0, 0, 0, 0))
    canvas.paste(Image.fromarray(premul, "RGBA"), (round(-x0), round(-y0)))
    small = np.asarray(canvas.resize((frame, frame), Image.BOX)).astype(np.float32)

    a = small[..., 3:4] / 255.0
    straight = np.zeros_like(small[..., :3])
    np.divide(small[..., :3], np.maximum(a, 1e-4), out=straight, where=a > 0)
    out = np.dstack([np.clip(straight, 0, 255), small[..., 3]]).astype(np.uint8)
    img = Image.fromarray(grade(out, shadow_lift, saturation), "RGBA")
    return img.filter(ImageFilter.UnsharpMask(radius=1.4, percent=90, threshold=2))


def grade(rgba: np.ndarray, shadow_lift: float, saturation: float) -> np.ndarray:
    """Lift the shadows and push the saturation so the sprite reads small."""
    rgb = rgba[..., :3].astype(np.float32)
    grey = rgb.mean(axis=2, keepdims=True)
    rgb = grey + (rgb - grey) * saturation
    rgb = shadow_lift + rgb * (255.0 - shadow_lift) / 255.0
    return np.dstack([np.clip(rgb, 0, 255), rgba[..., 3]]).astype(np.uint8)


def harden_alpha(img: Image.Image, cutoff: int) -> Image.Image:
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r, g, b, a.point(lambda v: 255 if v >= cutoff else 0)))


def build_palette(frames: list[Image.Image], colors: int) -> Image.Image:
    """One adaptive palette shared by every frame, from opaque pixels only."""
    pixels = []
    for img in frames:
        arr = np.asarray(img)
        opaque = arr[arr[..., 3] > 0][:, :3]
        if len(opaque):
            pixels.append(opaque)
    stacked = np.concatenate(pixels)
    strip = Image.fromarray(stacked.reshape(-1, 1, 3).astype(np.uint8), "RGB")
    return strip.quantize(colors=colors, method=Image.MEDIANCUT)


def apply_palette(img: Image.Image, palette: Image.Image) -> Image.Image:
    alpha = img.getchannel("A")
    flat = img.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
    out = flat.convert("RGB").convert("RGBA")
    out.putalpha(alpha)
    return out
