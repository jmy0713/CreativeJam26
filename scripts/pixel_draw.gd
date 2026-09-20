class_name PixelDraw
## Rules shared by the effects drawn in code as pixel art (SlashArc,
## PuffCloud).
##
## An effect built out of draw_rect only reads as pixel art if every rect lands
## on whole world pixels and nothing is ever blended. Those two are the easy
## ones to get wrong, so they live here rather than once per effect. The rest
## of the style — opaque tones only, a frame clock instead of a tween, fading
## by losing pixels — is in each effect and in section 7 of ARCHITECTURE.md.

## 4x4 ordered dither. Keyed on pixel coordinates so the pattern holds still
## from frame to frame instead of crawling.
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


## Offset that puts a whole-numbered local coordinate on a whole world pixel.
## Effects add it to every rect, so they stay crisp however fractional the
## owner's position is. Only meaningful for a node with no rotation or scale —
## a rotated one rasterises off the grid whatever you do with its origin.
static func snap(node: Node2D) -> Vector2:
	return node.global_position.round() - node.global_position


## Ordered dither threshold for a pixel, 0..1. The pixel survives while this
## is below the fraction of the shape still being kept.
static func dither(px: int, py: int) -> float:
	return BAYER[posmod(py, 4) * 4 + posmod(px, 4)] / 16.0
