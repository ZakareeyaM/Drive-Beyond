shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// (fleet copy: repeat_enable) Body shader for the fleet cars: smooth-filtered diffuse map, paint re-colouring of the
// texels close to the model's own paint colour (src_rgb), and the shared dent / wear parameters.
global uniform float night;
global uniform float wet;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 paint1 : source_color = vec3(0.7, 0.03, 0.05);
uniform vec3 src_rgb = vec3(0.5, 0.5, 0.5);   // dominant paint colour of the texture (display space)
uniform float repaint = 1.0;
uniform float metallic_amt = 0.25;
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
	vec3 c = texture(albedo_tex, UV).rgb;       // sampler is source_color -> linear
	vec3 srcl = pow(src_rgb, vec3(2.2));
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float slum = max(dot(srcl, vec3(0.299, 0.587, 0.114)), 0.02);
	float dchrom = distance(normalize(c + vec3(0.002)), normalize(srcl + vec3(0.002)));
	float m = repaint * (1.0 - smoothstep(0.2, 0.45, dchrom)) * smoothstep(0.18, 0.4, lum / slum);
	vec3 painted = paint1 * clamp(lum / slum, 0.15, 1.4);
	c = mix(c, painted, m);
	float scratch = smoothstep(0.62, 0.9, vnoise(lpos.xz * 9.0 + lpos.y * 5.0)) * damage;
	float dirt = smoothstep(0.4, 1.0, vnoise(lpos.xz * 3.0)) * damage * 0.5;
	c = mix(c, vec3(0.42, 0.4, 0.38) * 0.4, scratch * 0.7 * m);
	c = mix(c, vec3(0.03), clamp(dentv * 2.5, 0.0, 0.85));
	c *= (1.0 - dirt);
	ALBEDO = c;
	METALLIC = metallic_amt * m * (1.0 - scratch * 0.8);
	ROUGHNESS = mix(0.75, 0.38, m) * (1.0 - 0.4 * wet);
	SPECULAR = mix(0.3, 0.6, m);
}
