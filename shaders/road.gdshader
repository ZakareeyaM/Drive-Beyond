shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

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
	float lanes = COLOR.r * 4.0;
	float kind = COLOR.g;           // 0 asphalt, 0.5 dirt, 1 race track
	float wm = COLOR.b * 32.0;      // road width in metres
	float fade = COLOR.a;           // markings fade near junctions
	float x = (UV.x - 0.5) * wm;
	float s = UV.y;
	float grain = vnoise(wpos.xz * 1.7) * 0.5 + vnoise(wpos.xz * 6.0) * 0.5;
	vec3 base = vec3(0.075, 0.078, 0.085) * (0.8 + 0.5 * grain);
	// worn tyre tracks darker
	float track = smoothstep(0.9, 0.0, abs(abs(x) - wm * 0.18) * 0.7);
	base *= 1.0 - 0.15 * track;
	float rough = 0.88;
	if (kind > 0.2 && kind < 0.8) {
		base = mix(vec3(0.45, 0.32, 0.2), vec3(0.55, 0.42, 0.28), grain);
		base *= 1.0 - 0.25 * smoothstep(wm * 0.12, 0.0, abs(abs(x) - wm * 0.2));
		rough = 0.95;
	} else {
		float m = 0.0;
		vec3 mc = vec3(0.9);
		float el = abs(abs(x) - (wm * 0.5 - 0.5));
		if (el < 0.07) { m = 1.0; }
		if (kind > 0.8) {
			float stripe = step(0.5, fract(s / 3.0));
			if (abs(x) > wm * 0.5 - 1.0) { m = 1.0; mc = mix(vec3(0.85, 0.1, 0.08), vec3(0.95), stripe); }
			float grid = step(0.5, fract(s / 140.0)) * 0.0;
		} else {
			float cl = abs(abs(x) - 0.14);
			if (cl < 0.055) { m = 1.0; mc = vec3(0.95, 0.75, 0.1); }
			if (lanes > 1.5) {
				float ld = abs(abs(x) - wm * 0.25);
				if (ld < 0.06 && fract(s / 9.0) < 0.5) { m = 1.0; mc = vec3(0.92); }
			}
		}
		base = mix(base, mc, m * fade * (0.55 + 0.45 * grain));
	}
	float w = wet;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec2 cell = floor(wpos.xz / 22.0);
	float hh = hash21(cell);
	vec3 neon = hh < 0.33 ? vec3(1.0, 0.1, 0.6) : (hh < 0.66 ? vec3(0.1, 0.8, 1.0) : vec3(1.0, 0.55, 0.15));
	float streak = vnoise(vec2(wpos.x * 0.09, wpos.z * 0.09)) * vnoise(wpos.xz * 0.02);
	vec3 skyc = mix(vec3(0.55, 0.65, 0.8), vec3(0.04, 0.05, 0.1), night);
	vec3 refl = mix(skyc, neon * (0.3 + streak * 1.4), night * 0.85);
	float puddle = smoothstep(0.35, 0.65, vnoise(wpos.xz * 0.35));
	float wetm = w * (0.55 + 0.45 * puddle);
	ALBEDO = base * (1.0 - 0.45 * wetm);
	ROUGHNESS = mix(rough, 0.1, wetm);
	SPECULAR = mix(0.4, 0.9, wetm);
	METALLIC = 0.0;
	EMISSION = refl * wetm * (0.04 + fres * 0.9) * (0.6 + 0.4 * night);
}
