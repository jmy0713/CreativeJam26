shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 screen = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(mix(screen, vec3(1.0) - screen, intensity), 1.0);
}