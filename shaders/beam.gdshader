shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled;

uniform vec3 beam_color : source_color = vec3(1.0, 0.1, 0.1);
uniform float strength = 0.6;

void fragment() {
	float a = (1.0 - UV.y);
	a = a * a;
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0);
	ALBEDO = beam_color * a * strength * pulse;
}
