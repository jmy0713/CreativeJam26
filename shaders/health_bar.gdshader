shader_type canvas_item;

// Pixel health bar. Draws one cell of the health bar atlas, and blends
// between two cells with an ordered dither so a hit crumbles the old stage
// into the new one pixel by pixel instead of snapping.
//
// Three layers, back to front:
//   1. frame_from  — the stage the bar is leaving.
//   2. frame_to    — the stage it is arriving at. `dissolve` wipes 1 over 2.
//   3. the trail   — pixels frame_ghost had that frame_to doesn't, painted in
//                    ghost_color and wiped away by `ghost_dissolve` a beat
//                    later. Red that survives the hit is never touched.
//
// `atlas` is the whole sheet; UV spans the node, which shows a single cell.
// Frames read left to right, top to bottom, fullest first. A frame index at
// or past frame_count is empty, which is how death is drawn.
//
// `frame_pixels` is the size of one cell, which health_bar.gd derives from the
// atlas at runtime — it only sets the dither's resolution, so a wrong value
// coarsens the effect rather than breaking the layout.

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec2 grid = vec2(4.0, 2.0);
uniform vec2 frame_pixels = vec2(64.0, 32.0);
uniform int frame_count : hint_range(1, 32) = 5;

uniform int frame_from : hint_range(0, 32) = 0;
uniform int frame_to : hint_range(0, 32) = 0;
uniform float dissolve : hint_range(0.0, 1.0) = 1.0;

uniform int frame_ghost : hint_range(0, 32) = 0;
uniform float ghost_dissolve : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ghost_color : source_color = vec4(0.12, 0.13, 0.14, 1.0);
// How much darker the trail draws where the sprite's own outline was, so it
// still reads as a bar rather than a flat slab.
uniform float ghost_outline_darken : hint_range(0.0, 1.0) = 0.45;

// 0 = a pure ordered Bayer stipple, 1 = pure per-pixel noise.
uniform float dither_noise : hint_range(0.0, 1.0) = 0.35;
// Width of the dithered band that travels along the bar, in fractions of the
// bar's length. 0 makes every pixel flip at once; ~0.5 reads as draining.
uniform float edge_softness : hint_range(0.0, 2.0) = 0.55;
// +1 = the wipe runs right to left (losing health), -1 = left to right.
uniform float sweep_dir = 1.0;

vec4 sample_frame(int frame, vec2 cell_uv) {
	if (frame >= frame_count || frame < 0) {
		return vec4(0.0);
	}
	int cols = int(grid.x);
	vec2 cell = vec2(float(frame % cols), float(frame / cols));
	// Stay half a texel inside the cell so nearest filtering can't pull in a
	// neighbouring frame at the seams.
	vec2 inset = clamp(cell_uv, 0.5 / frame_pixels, 1.0 - 0.5 / frame_pixels);
	return texture(atlas, (cell + inset) / grid);
}


// The 2x2 Bayer cell [[0, 2], [3, 1]], then the standard recursive step up to
// 4x4: coarse position picks the high bits, fine position the low ones.
float bayer2(float a, float b) {
	return a * 2.0 + b * 3.0 - a * b * 4.0;
}


float bayer4(vec2 p) {
	vec2 lo = mod(p, 2.0);
	vec2 hi = mod(floor(p * 0.5), 2.0);
	return (4.0 * bayer2(lo.x, lo.y) + bayer2(hi.x, hi.y) + 0.5) / 16.0;
}


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


// Per-pixel flip point, stable for the life of the bar: where along the wipe
// this pixel gives up. Position sets the wavefront, dither ragged-edges it.
float flip_point(vec2 cell_uv) {
	vec2 pix = floor(cell_uv * frame_pixels);
	float dith = mix(bayer4(pix), hash12(pix), dither_noise);
	float along = sweep_dir > 0.0 ? (1.0 - cell_uv.x) : cell_uv.x;
	return along + (dith - 0.5) * edge_softness;
}


// Remap 0..1 progress so it clears the full spread of flip points, i.e. the
// wipe is guaranteed empty at 0 and complete at 1.
float wavefront(float progress) {
	float spread = edge_softness + 0.01;
	return progress * (1.0 + spread) - spread * 0.5;
}


void fragment() {
	vec2 cell_uv = UV;
	float flip = flip_point(cell_uv);

	vec4 from_col = sample_frame(frame_from, cell_uv);
	vec4 to_col = sample_frame(frame_to, cell_uv);
	vec4 col = flip < wavefront(dissolve) ? to_col : from_col;

	// Trail: only where the bar is showing nothing right now, and only where
	// it has actually lost ground since the trail started.
	if (col.a < 0.5) {
		vec4 lost = sample_frame(frame_ghost, cell_uv);
		if (lost.a > 0.5 && to_col.a < 0.5 && flip > wavefront(ghost_dissolve)) {
			float lum = dot(lost.rgb, vec3(0.299, 0.587, 0.114));
			float shade = smoothstep(0.08, 0.32, lum);
			vec3 trail_rgb = mix(ghost_color.rgb * (1.0 - ghost_outline_darken), ghost_color.rgb, shade);
			col = vec4(trail_rgb, ghost_color.a * lost.a);
		}
	}

	// Assign outright: COLOR arrives pre-multiplied by a plain full-texture
	// sample, which is not the cell we want.
	COLOR = col * tint;
}
