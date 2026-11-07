shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float night;
global uniform float wet;

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 cust;
varying vec3 tint;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cust = INSTANCE_CUSTOM;
	tint = COLOR.rgb;
}

void fragment() {
	vec3 base = tint;
	float lit = cust.x;
	float winflag = cust.y;
	float seed = cust.z;
	vec3 n = wnorm;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (abs(n.y) > 0.6) {
		base *= 0.55;
	} else {
		vec2 uv = abs(n.x) > abs(n.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		float side = abs(n.x) > abs(n.z) ? sign(n.x) : sign(n.z) + 3.0;
		vec2 g = vec2(uv.x / 3.1, uv.y / 3.7);
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float inwin = step(0.14, f.x) * step(f.x, 0.86) * step(0.2, f.y) * step(f.y, 0.78) * step(1.2, uv.y) * step(0.5, winflag);
		if (inwin > 0.5) {
			float r = hash21(cell + vec2(seed * 3.1 + side * 7.0, seed));
			float on = step(r, lit * night);
			vec3 wc = mix(vec3(1.0, 0.82, 0.5), vec3(0.65, 0.85, 1.0), step(0.7, hash21(cell + 11.0 + seed)));
			if (hash21(cell + 40.0 + seed) > 0.93) wc = vec3(1.0, 0.25, 0.7);
			vec3 glass = mix(vec3(0.08, 0.12, 0.17), vec3(0.2, 0.28, 0.35), hash21(cell + seed));
			base = mix(glass, wc * 0.4, on);
			emit = wc * on * 1.6;
			rough = 0.15;
			metal = 0.5 * (1.0 - on);
		} else {
			float band = step(0.93, f.y) * 0.12;
			base *= (1.0 - band);
		}
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
