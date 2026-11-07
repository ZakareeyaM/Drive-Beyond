shader_type sky;

uniform vec3 zenith : source_color = vec3(0.1, 0.25, 0.55);
uniform vec3 horizon : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground : source_color = vec3(0.1, 0.1, 0.12);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 moon_dir = vec3(0.0, -0.5, 0.8);
uniform float moon_amt = 0.0;
uniform float stars = 0.0;
uniform float cloud_cover = 0.2;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float storm = 0.0;

float hash31(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.07; a *= 0.5; } return v; }

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h > 0.0) {
		float t = pow(h, 0.55);
		col = mix(horizon, zenith, t);
	} else {
		col = mix(horizon, ground, clamp(-h * 4.0, 0.0, 1.0));
	}
	vec3 sd = normalize(sun_dir);
	float sdot = max(dot(d, sd), 0.0);
	// glow around sun at horizon
	col += sun_color * pow(sdot, 6.0) * 0.28;
	col += sun_color * pow(sdot, 64.0) * 0.6;
	float disc = smoothstep(0.9993, 0.9997, sdot);
	col = mix(col, sun_color * 3.0, disc * step(0.0, h + 0.02));
	// moon
	vec3 md = normalize(moon_dir);
	float mdot = max(dot(d, md), 0.0);
	if (moon_amt > 0.01 && h > -0.02) {
		vec3 lp = d - md * mdot;
		float maria = vnoise(lp.xy * 38.0 + lp.z * 17.0) * 0.5 + vnoise(lp.yz * 90.0 + lp.x * 31.0) * 0.25;
		float mdisc = smoothstep(0.99895, 0.99915, mdot);
		vec3 mcol = vec3(0.92, 0.94, 1.0) * (0.85 - 0.28 * maria) * 2.2;
		col += vec3(0.5, 0.6, 0.9) * pow(mdot, 180.0) * 0.5 * moon_amt;
		col += vec3(0.4, 0.5, 0.85) * pow(mdot, 24.0) * 0.07 * moon_amt;
		col = mix(col, mcol, mdisc * moon_amt);
	}
	// stars
	if (stars > 0.01 && h > 0.0) {
		vec3 sp = floor(d * 260.0);
		float s = hash31(sp);
		float tw = step(0.9945, s) * (0.6 + 0.4 * sin(TIME * 2.0 + s * 50.0));
		col += vec3(tw) * stars * smoothstep(0.0, 0.2, h);
	}
	// clouds
	if (h > 0.01) {
		vec2 cp = d.xz / (h + 0.18) * 1.6 + vec2(TIME * 0.008, TIME * 0.004);
		float c = fbm(cp * 1.2);
		float cover = clamp(cloud_cover, 0.0, 1.0);
		float m = smoothstep(1.0 - cover, 1.0 - cover + 0.3, c);
		m *= smoothstep(0.0, 0.15, h);
		vec3 cc = cloud_color * (0.65 + 0.35 * pow(sdot, 2.0) + 0.2);
		cc = mix(cc, cc * 0.35, storm);
		col = mix(col, cc, m * (0.7 + 0.3 * storm));
	}
	COLOR = col;
}
