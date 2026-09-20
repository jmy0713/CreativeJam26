shader_type canvas_item;

// The time tunnel, drawn on its own into a small SubViewport by
// scene_transition.gd and composited over the game by time_warp.gdshader.
//
// It has its own low-resolution viewport for two reasons. One pixel here is
// one tunnel cell, so the pixel-art grid costs nothing to keep -- there is no
// snapping to do, the viewport *is* the grid. And the expensive half of the
// effect (an atan, a hash and a fistful of sin/cos per pixel) runs on ~58,000
// pixels 12 times a second instead of the window's few million 60 times a
// second. That is most of what makes the transition cheap.
//
//   anim_time   Seconds of tunnel motion, ALREADY stepped to the frame rate by
//               the script -- which is also what decides when this is redrawn,
//               so there is nothing to quantise here.
//   clock_spin  1 = clockwise (heading to the future), -1 = counter-clockwise
//               (heading back).
//   grid        The viewport's own size, for the aspect ratio.
//
// Colour comes from a six-tone palette shaded in four flat steps, and there is
// no alpha and no glow anywhere: see section 7 of ARCHITECTURE.md.

uniform float anim_time = 0.0;
uniform float clock_spin = 1.0;
uniform vec2 grid = vec2(320.0, 180.0);

// Radial warp lanes around the tunnel.
const float LANES = 24.0;
// Radius of the clock face in the middle of the tunnel (1.0 = screen height).
const float CLOCK_RADIUS = 0.20;
// Positions the clock hands are allowed to stop on.
const float CLOCK_TICKS = 12.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Down to `steps` flat values, for anything that would otherwise ramp.
float quant(float v, float steps) {
	return floor(v * steps) / steps;
}

// Six flat tones, looping cyan -> violet -> gold -> cyan. Nothing in between:
// the whole tunnel is painted out of these and the ramp below.
vec3 palette(float x) {
	int i = int(mod(floor(x * 6.0), 6.0));
	if (i == 0) { return vec3(0.10, 0.75, 1.00); }
	if (i == 1) { return vec3(0.35, 0.42, 0.95); }
	if (i == 2) { return vec3(0.70, 0.25, 1.00); }
	if (i == 3) { return vec3(0.95, 0.35, 0.70); }
	if (i == 4) { return vec3(1.00, 0.72, 0.25); }
	return vec3(1.00, 0.90, 0.55);
}

// Four flat shades of a palette tone: the only shading the tunnel gets.
vec3 tone(vec3 base, float level) {
	float s = quant(clamp(level, 0.0, 0.999), 4.0) * (4.0 / 3.0);
	return mix(base * 0.22, mix(base, vec3(1.0), 0.5), s);
}

// A clock hand: a hard-edged line from the origin, `len` long, along `ang`.
float hand(vec2 p, float ang, float len, float width) {
	vec2 dir = vec2(cos(ang), sin(ang));
	float along = clamp(dot(p, dir), 0.0, len);
	return step(length(p - dir * along), width * 0.5);
}

// Hands tick between whole positions instead of sweeping.
float tick_angle(float a) {
	float s = TAU / CLOCK_TICKS;
	return floor(a / s) * s;
}

void fragment() {
	float aspect = grid.x / grid.y;
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float t = anim_time;

	float r = length(p) + 1e-4;
	float turns = atan(p.y, p.x + 1e-5) / TAU; // -0.5..0.5; only ever used
	                                           // times whole numbers so the seam hides.

	// Depth grows toward the centre, so rings rush outward as t advances.
	float depth = 0.6 / (r + 0.04) + t * 1.4;

	// Walls: colour bands that corkscrew down the tunnel. The four tones of
	// tone() are worth having, so `light` is scaled to land across all of
	// them: the walls ride the bottom three and the rings are the only thing
	// that reaches the top one.
	vec3 base = palette(depth * 0.04 + turns + t * 0.04);
	float light = 0.15 + 0.45 * (0.5 + 0.5 * sin((turns * 6.0 + depth * 0.2) * TAU));
	// Bright rings rushing past: a hard band rather than a falloff.
	light += step(0.72, 1.0 - abs(2.0 * fract(depth) - 1.0)) * 0.32;
	// Light at the end of the tunnel, in four rings; walls darken toward the
	// screen edge in three.
	light += (1.0 - quant(clamp(r / 0.5, 0.0, 1.0), 4.0)) * 0.30;
	light -= quant(clamp((r - 0.4) / 0.65, 0.0, 1.0), 3.0) * 0.30;

	vec3 col = tone(base, light);

	// Warp-speed streaks: whole lanes of the tunnel, each with its own speed,
	// only some of them lit, each a white head with one paler cell behind it.
	float s = turns * LANES;
	float rnd = hash21(vec2(mod(floor(s), LANES), 3.7));
	if (step(0.5, rnd) * step(abs(fract(s) - 0.5), 0.32) > 0.5) {
		float pos = fract(0.16 / (r + 0.04) * (0.5 + rnd) + t * (0.8 + 2.2 * rnd) + rnd * 9.0);
		if (pos < 0.10) {
			col = vec3(1.00, 1.00, 1.00);
		} else if (pos < 0.26) {
			col = vec3(0.60, 0.85, 1.00);
		}
	}

	// A clock face at the far end. Its hands turn clockwise going to the
	// future, counter-clockwise going back (clock_spin). Screen y points down,
	// so an angle that increases turns clockwise.
	float cr = CLOCK_RADIUS;
	vec3 gold = vec3(1.00, 0.86, 0.55);
	if (r < cr) {
		col = vec3(0.04, 0.05, 0.10);
		// Twelve ticks just inside the rim.
		if (r > cr - 0.030 && abs(fract(turns * 12.0 + 0.5) - 0.5) < 0.030) {
			col = gold;
		}
		if (hand(p, -1.5708 + tick_angle(clock_spin * t * 7.0), cr * 0.88, 0.016) > 0.5) {
			col = gold;
		}
		if (hand(p, -1.5708 + tick_angle(clock_spin * t * 0.6), cr * 0.58, 0.024) > 0.5) {
			col = gold;
		}
		if (r < 0.016) {
			col = gold;
		}
	} else if (r < cr + 0.010) {
		col = gold;
	}

	COLOR = vec4(col, 1.0);
}
