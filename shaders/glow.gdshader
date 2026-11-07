shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

global uniform float night;
uniform vec3 tint : source_color = vec3(1.0, 0.8, 0.5);
uniform float strength = 0.55;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	a = a * a;
	ALBEDO = tint * a * strength * night * COLOR.r;
}
