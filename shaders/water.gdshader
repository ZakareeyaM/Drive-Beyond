shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

global uniform float night;
global uniform float wet;

uniform vec3 deep_color : source_color = vec3(0.02, 0.17, 0.28);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.42, 0.5);
varying vec3 wpos;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.07 + TIME * 0.9) * 0.12 + sin(wpos.z * 0.09 + TIME * 0.7) * 0.1;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	float a = vnoise(p * 0.22 + vec2(t * 0.35, t * 0.2));
	float b = vnoise(p * 0.6 - vec2(t * 0.5, -t * 0.3));
	vec3 nrm = normalize(vec3((a - 0.5) * 0.6 + (b - 0.5) * 0.3, 1.0, (b - 0.5) * 0.6 - (a - 0.5) * 0.3));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float depthmix = smoothstep(0.0, 1.0, vnoise(p * 0.01) * 0.5 + 0.4);
	vec3 col = mix(shallow_color, deep_color, depthmix);
	col *= mix(1.0, 0.25, night);
	ALBEDO = col;
	ROUGHNESS = mix(0.05, 0.25, wet);
	SPECULAR = 0.9;
	METALLIC = 0.0;
	EMISSION = vec3(0.35, 0.5, 0.65) * fres * 0.5 * mix(1.0, 0.15, night);
	float foam = smoothstep(0.78, 0.9, a * b * 1.6) * 0.25;
	ALBEDO += foam;
	ALPHA = clamp(0.8 + fres * 0.2, 0.0, 1.0);
}
