shader_type spatial;
render_mode diffuse_burley;

global uniform float night;
global uniform float wet;

varying vec3 wpos;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = vnoise(wpos.xz * 0.45);
	float n2 = vnoise(wpos.xz * 2.3);
	float n3 = vnoise(wpos.xz * 9.0);
	vec3 c = COLOR.rgb * (0.82 + 0.22 * n1 + 0.1 * n2 + 0.06 * n3);
	ALBEDO = c * (1.0 - 0.3 * wet);
	ROUGHNESS = mix(0.95, 0.55, wet);
	SPECULAR = 0.2;
}
