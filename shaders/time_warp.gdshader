shader_type canvas_item;

// Time-warp transition, drawn full-screen over everything (HUD included).
// scripts/autoload/scene_transition.gd drives the two uniforms below.
//
//   warp_amount  0 = the game exactly as it is, 1 = pure time tunnel.
//                Going 0 -> 1 sucks the frame into a swirling vortex and
//                opens a portal; going 1 -> 0 lets whatever is underneath
//                (the next level) fly back out of it.
//   anim_time    Seconds of tunnel motion. The script speeds it up and slows
//                it down so the jump accelerates in and eases out.
//   clock_spin   Which way the clock hands turn: 1 = clockwise (heading to
//                the future), -1 = counter-clockwise (heading back).

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float warp_amount : hint_range(0.0, 1.0) = 0.0;
uniform float anim_time = 0.0;
uniform float clock_spin = 1.0;

// Tunnel palette: cyan -> violet -> gold -> cyan.
const vec3 COLOR_A = vec3(0.10, 0.75, 1.00);
const vec3 COLOR_B = vec3(0.70, 0.25, 1.00);
const vec3 COLOR_C = vec3(1.00, 0.72, 0.25);

// Samples taken along each pixel's line to the centre (the zoom blur).
const int BLUR_STEPS = 12;
// Radius of the clock face in the middle of the tunnel (1.0 = screen height).
const float CLOCK_RADIUS = 0.20;


mat2 rot(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Loops smoothly: palette(0.0) == palette(1.0).
vec3 palette(float t) {
	t = fract(t);
	vec3 c = mix(COLOR_A, COLOR_B, smoothstep(0.0, 0.34, t));
	c = mix(c, COLOR_C, smoothstep(0.34, 0.67, t));
	return mix(c, COLOR_A, smoothstep(0.67, 1.0, t));
}

// A clock hand: a soft line from the origin, `len` long, pointing along `ang`.
float hand(vec2 p, float ang, float len, float width) {
	vec2 dir = vec2(cos(ang), sin(ang));
	float along = clamp(dot(p, dir), 0.0, len);
	float d = length(p - dir * along);
	return 1.0 - smoothstep(width * 0.5, width, d);
}

// The tunnel itself. `p` is centred on the screen, y in -0.5..0.5.
vec3 time_tunnel(vec2 p, float t) {
	float r = length(p) + 1e-4;
	float turns = atan(p.y, p.x + 1e-5) / TAU; // -0.5..0.5; only ever used
	                                           // times whole numbers so the seam hides.

	// Depth grows toward the centre, so rings rush outward as t advances.
	float depth = 0.6 / (r + 0.04) + t * 1.4;

	// Walls: colour bands that corkscrew down the tunnel.
	vec3 base = palette(depth * 0.04 + turns + t * 0.04);
	float arms = 0.5 + 0.5 * sin((turns * 8.0 + depth * 0.2) * TAU);
	vec3 col = base * (0.10 + 0.55 * pow(arms, 3.0));

	// Bright rings rushing past.
	float ring = pow(1.0 - abs(2.0 * fract(depth) - 1.0), 10.0);
	col += palette(depth * 0.04 + turns + 0.5) * ring * 1.2;

	// Warp-speed streaks: thin radial lanes, each with its own speed, only
	// some of them lit, every streak a bright head with a fading tail.
	float lanes = 72.0;
	float s = turns * lanes;
	float lane_id = mod(floor(s), lanes);
	float rnd = hash21(vec2(lane_id, 3.7));
	float line = 1.0 - smoothstep(0.0, 0.16, abs(fract(s) - 0.5));
	float pos = fract(0.16 / (r + 0.04) * (0.5 + rnd) + t * (0.8 + 2.2 * rnd) + rnd * 9.0);
	float streak = line * pow(1.0 - pos, 7.0) * step(0.5, rnd);
	col += vec3(0.85, 0.95, 1.0) * streak * 1.6;

	// Light at the end of the tunnel, and darker walls toward the screen edge.
	col += mix(vec3(1.0), base, 0.4) * exp(-r * 6.0) * 0.9;
	col *= 1.0 - 0.5 * smoothstep(0.4, 1.05, r);

	// A clock face at the far end. Its hands turn clockwise going to the
	// future, counter-clockwise going back (clock_spin). Screen y points down,
	// so an angle that increases turns clockwise.
	float cr = CLOCK_RADIUS;
	float disc = 1.0 - smoothstep(cr - 0.012, cr, r);
	col = mix(col, vec3(0.02, 0.03, 0.07), disc * 0.9);

	vec3 gold = vec3(1.0, 0.86, 0.55);
	float rim = 1.0 - smoothstep(0.0, 0.010, abs(r - cr));
	float tick_dist = abs(fract(turns * 12.0 + 0.5) - 0.5);
	float tick = (1.0 - smoothstep(0.0, 0.035, tick_dist)) * step(cr - 0.035, r) * step(r, cr);
	float minute = hand(p, -1.5708 + clock_spin * t * 7.0, cr * 0.88, 0.012);
	float hour = hand(p, -1.5708 + clock_spin * t * 0.6, cr * 0.58, 0.020);
	float hub = 1.0 - smoothstep(0.012, 0.016, r);
	col += gold * (rim + tick * 0.8 + minute + hour + hub);

	return col;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 to_uv_scale = vec2(1.0 / aspect, 1.0);
	vec2 p = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float w = warp_amount;

	// 1. The game, twisted and smeared toward the centre, with the colour
	//    channels pulled apart. At w == 0 every sample lands on the pixel's
	//    own position, so this is an exact pass-through.
	float swirl = w * 7.0 * exp(-r * 3.0);
	float blur = w * 0.55;
	float split = w * 0.035;
	vec3 game = vec3(0.0);
	for (int i = 0; i < BLUR_STEPS; i++) {
		float k = float(i) / float(BLUR_STEPS - 1);
		vec2 q = rot(swirl * (0.4 + 0.6 * k)) * p * (1.0 - blur * k);
		game.r += texture(screen_texture, q * (1.0 + split) * to_uv_scale + 0.5).r;
		game.g += texture(screen_texture, q * to_uv_scale + 0.5).g;
		game.b += texture(screen_texture, q * (1.0 - split) * to_uv_scale + 0.5).b;
	}
	game /= float(BLUR_STEPS);
	game *= mix(vec3(1.0), palette(anim_time * 0.1) * 1.4, w * 0.6);
	game *= 1.0 - 0.5 * w * smoothstep(0.3, 1.0, r);

	// 2. A portal opens from the middle and grows until it covers the screen
	//    (reach > the corner distance of ~1.02 once w is near 1).
	float reach = w * 1.45;
	float portal = 1.0 - smoothstep(reach - 0.30, reach, r);
	vec3 col = mix(game, time_tunnel(p, anim_time), portal);

	// 3. A glowing shockwave riding the portal's edge.
	float d_edge = (r - (reach - 0.15)) * 9.0;
	float rim_glow = exp(-d_edge * d_edge) * smoothstep(0.0, 0.15, w);
	col += palette(anim_time * 0.35 + r * 0.5) * rim_glow * 1.6;

	COLOR = vec4(col, 1.0);
}
