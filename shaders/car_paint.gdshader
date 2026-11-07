shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float night;
global uniform float wet;

uniform vec3 paint1 : source_color = vec3(0.7, 0.05, 0.05);
uniform vec3 paint2 : source_color = vec3(0.05, 0.05, 0.06);
uniform float metallic_amt = 0.55;
uniform float damage = 0.0;                 // 0..1 overall wear
uniform vec4 dents[4];                      // xyz local pos, w strength
uniform float dent_radius = 0.9;
uniform float two_tone = 0.0;
uniform float roof_y = 1.2;
uniform float body_top = 0.9;

varying vec3 lpos;
varying float dentv;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lpos = VERTEX;
	float dsum = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 dn = dents[i];
		if (dn.w > 0.001) {
			float d = distance(VERTEX, dn.xyz);
			float f = smoothstep(dent_radius, 0.0, d) * dn.w;
			vec3 dir = normalize(dn.xyz - VERTEX + vec3(0.0001));
			dir.y *= 0.4;
			VERTEX += dir * f * 0.22;
			VERTEX.y -= f * 0.03;
			dsum += f;
		}
	}
	dentv = dsum;
}

void fragment() {
	vec3 c = paint1;
	if (two_tone > 0.5 && lpos.y > body_top - 0.02) c = paint2;
	float scratch = smoothstep(0.62, 0.9, vnoise(lpos.xz * 9.0 + lpos.y * 5.0)) * damage;
	float dirt = smoothstep(0.4, 1.0, vnoise(lpos.xz * 3.0)) * damage * 0.5;
	c = mix(c, vec3(0.42, 0.4, 0.38), scratch * 0.85);
	c = mix(c, vec3(0.05, 0.04, 0.035), clamp(dentv * 2.5, 0.0, 0.85));
	c *= (1.0 - dirt);
	ALBEDO = c;
	METALLIC = metallic_amt * (1.0 - scratch * 0.8);
	ROUGHNESS = mix(0.22, 0.55, damage * 0.6) * (1.0 - 0.5 * wet);
	SPECULAR = 0.7;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = mix(vec3(0.5, 0.6, 0.75), vec3(0.15, 0.05, 0.3), night) * rim * 0.12 * metallic_amt;
}
