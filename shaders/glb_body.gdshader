shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Body shader for imported GLB cars: keeps the model's own (nearest-filtered) texture,
// optionally re-paints the "body red" texels with the player's paint colour,
// and supports the same dent / wear parameters as car_paint.gdshader.

global uniform float night;
global uniform float wet;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform vec3 paint1 : source_color = vec3(0.7, 0.03, 0.05);
uniform float repaint = 0.0;
uniform float metallic_amt = 0.3;
uniform float damage = 0.0;
uniform vec4 dents[4];
uniform float dent_radius = 0.9;

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
	vec4 t = texture(albedo_tex, UV);
	if (t.a < 0.5) { discard; }
	vec3 c = t.rgb;
	float is_paint = repaint * step(0.15, c.r) * step(c.g, 0.12) * step(c.b, 0.12);
	c = mix(c, paint1 * clamp(c.r / 0.5, 0.4, 1.3), is_paint);
	float scratch = smoothstep(0.62, 0.9, vnoise(lpos.xz * 9.0 + lpos.y * 5.0)) * damage;
	float dirt = smoothstep(0.4, 1.0, vnoise(lpos.xz * 3.0)) * damage * 0.5;
	c = mix(c, vec3(0.42, 0.4, 0.38), scratch * 0.7 * is_paint);
	c = mix(c, vec3(0.05, 0.04, 0.035), clamp(dentv * 2.5, 0.0, 0.85));
	c *= (1.0 - dirt);
	ALBEDO = c;
	METALLIC = metallic_amt * is_paint * (1.0 - scratch * 0.8);
	ROUGHNESS = mix(0.7, 0.4, is_paint) * (1.0 - 0.4 * wet);
	SPECULAR = mix(0.25, 0.6, is_paint);
}
