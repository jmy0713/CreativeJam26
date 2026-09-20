shader_type canvas_item;

// Flattens a sprite to one opaque colour: every pixel the art actually draws
// becomes `tint`, everything else is dropped outright. Used by the dash's
// DashGhosts, which need silhouettes of the player rather than tinted copies
// of him — modulate can only multiply, so it keeps the sprite's shading.
//
// The discard is what keeps this pixel art: no blending, no soft edge, so a
// ghost is as hard-edged as the sprite it came from. Ghosts step down a tone
// ramp to fade, they never go transparent.

uniform vec4 tint : source_color = vec4(1.0);
uniform float cutoff : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	if (texture(TEXTURE, UV).a < cutoff) {
		discard;
	}
	COLOR = vec4(tint.rgb, 1.0);
}
