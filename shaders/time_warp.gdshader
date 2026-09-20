shader_type canvas_item;

// The level-transition composite, drawn full-screen over everything (HUD
// included). This is the only half of the effect that runs at the window's own
// resolution, so it is kept to a texture read or three: the tunnel itself is
// drawn small in time_tunnel.gdshader and handed over as `tunnel_texture`.
// scripts/autoload/scene_transition.gd drives the uniforms below.
//
//   warp_amount     0 = the game exactly as it is, 1 = pure time tunnel.
//                   Going 0 -> 1 sucks the frame into a swirling vortex and
//                   opens a portal; going 1 -> 0 lets whatever is underneath
//                   (the next level) fly back out of it.
//   tunnel_texture  The tunnel, one texel per cell of `tunnel_grid`.
//   tunnel_grid     Cells across and down the screen. The script sets it to
//                   half the game's resolution, so the tunnel is twice as
//                   chunky as the sprites.
//
// The pixel-art rules in section 7 of ARCHITECTURE.md apply here as much as
// they do to the tunnel: coordinates are snapped to a grid before the maths
// runs, the warp grows in WARP_STEPS jumps rather than sliding, the old level
// flattens onto a handful of tones as it goes, and the portal's edge is cut
// with a 4x4 ordered dither (the same matrix as PixelDraw.BAYER) instead of
// being cross-faded. The only mix() left takes a factor that is exactly 0 or 1.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D tunnel_texture : repeat_disable, filter_nearest;
uniform float warp_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 tunnel_grid = vec2(320.0, 180.0);

// Steps the warp grows and collapses in.
const float WARP_STEPS = 16.0;
// Warp needed before the old level drops from its own resolution onto the
// tunnel's coarser one. One hard jump, so it reads as the level digitising.
const float RES_DROP = 0.12;
// Copies of the old level smeared toward the centre as it is pulled in.
const int GHOSTS = 3;
// Where the tunnel is sampled for the colour the dying level is tinted with:
// above the clock face, so it picks up a wall rather than the dark dial.
const vec2 TINT_AT = vec2(0.5, 0.15);


mat2 rot(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Centre of the grid cell a UV falls in: the snap that keeps the smear made of
// whole pixels instead of turning into a gradient.
vec2 cell_uv(vec2 uv, vec2 grid) {
	return (floor(uv * grid) + 0.5) / grid;
}

float quant(float v, float steps) {
	return floor(v * steps) / steps;
}

vec3 posterize(vec3 c, float levels) {
	return floor(min(c, vec3(0.999)) * levels) / (levels - 1.0);
}

// 2x2 ordered dither, the base case the 4x4 one is built out of.
float bayer2(float a, float b) {
	return mix(a, 2.0 + b, abs(a - b));
}

// 4x4 ordered dither, 0..1, keyed on the cell so the pattern holds still
// between frames instead of crawling. Same matrix as PixelDraw.BAYER.
float bayer4(vec2 cell) {
	vec2 p = mod(floor(cell), 4.0);
	vec2 hi = floor(p * 0.5);
	vec2 lo = mod(p, 2.0);
	return (4.0 * bayer2(lo.x, lo.y) + bayer2(hi.x, hi.y)) / 16.0;
}

void fragment() {
	// The warp grows in whole steps, and sits at exactly 0 for the first few
	// frames so the level is handed through untouched before it digitises.
	float w = quant(warp_amount, WARP_STEPS);
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	vec2 cell = floor(SCREEN_UV * tunnel_grid);
	float r = length((cell_uv(SCREEN_UV, tunnel_grid) - 0.5) * vec2(aspect, 1.0));

	// A portal opens from the middle and grows until it covers the screen
	// (reach > the corner distance of ~1.02 once w is near 1). Its edge is a
	// dither, so the tunnel eats the level a cell at a time.
	float edge = clamp((w * 1.45 - r) / 0.22, 0.0, 1.0);
	if (edge > bayer4(cell)) {
		// Inside the portal there is nothing to composite, and for most of the
		// transition that is the whole screen: one texture read and done.
		COLOR = vec4(texture(tunnel_texture, SCREEN_UV).rgb, 1.0);
	} else {
		// Outside it, the game -- twisted and dragged toward the centre.
		// Ghosts are kept rather than averaged, so the smear stays made of the
		// level's own colours. At w == 0 every ghost lands on the pixel's own
		// position, so this is an exact pass-through.
		//
		// The level keeps its own resolution until the warp takes hold, then
		// drops onto the tunnel's coarser grid in one jump.
		vec2 game_grid = tunnel_grid * mix(2.0, 1.0, step(RES_DROP, w));
		vec2 pg = (cell_uv(SCREEN_UV, game_grid) - 0.5) * vec2(aspect, 1.0);
		float rg = length(pg);
		vec2 to_uv_scale = vec2(1.0 / aspect, 1.0);

		float swirl = w * 7.0 * exp(-rg * 3.0);
		float squeeze = w * 0.55;
		vec3 game = vec3(0.0);
		for (int i = 0; i < GHOSTS; i++) {
			float k = float(i) / float(GHOSTS - 1);
			vec2 q = rot(swirl * (0.4 + 0.6 * k)) * pg * (1.0 - squeeze * k);
			game = max(game, texture(screen_texture, cell_uv(q * to_uv_scale + 0.5, game_grid)).rgb);
		}

		// Tinted with the tunnel's own colour and flattened in four steps as
		// it goes: by the time the portal reaches it, it is down to the same
		// handful of tones as the tunnel it is about to be replaced by.
		float fade = quant(clamp(w * 3.0, 0.0, 1.0), 4.0);
		game *= mix(vec3(1.0), texture(tunnel_texture, TINT_AT).rgb * 1.5 + 0.15, fade * 0.7);
		game *= 1.0 - quant(clamp((rg - 0.3) / 0.7, 0.0, 1.0), 3.0) * 0.5 * w;
		COLOR = vec4(posterize(game, mix(32.0, 6.0, fade)), 1.0);
	}
}
