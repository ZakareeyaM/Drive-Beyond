shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
// Cheap calm-ocean look for the main menu: two octaves of value noise for the ripples, a sky-reflection fresnel and
// a soft sun glint.  No reflections/refraction/vertex displacement; one flat quad.  The far water blends into the
// horizon colour analytically (no scene fog needed) so there is never a visible seam at the horizon.

uniform vec3 deep_color : source_color = vec3(0.20, 0.33, 0.43);
uniform vec3 shallow_color : source_color = vec3(0.28, 0.43, 0.53);
uniform vec3 horizon_color : source_color = vec3(0.63, 0.73, 0.84);
uniform vec3 sky_color : source_color = vec3(0.45, 0.62, 0.85);
uniform vec3 sun_dir = vec3(-0.35, 0.28, -0.9);
uniform float haze_distance = 1100.0;

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
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - wpos;
	float dist = length(to_cam);
	vec3 v = to_cam / dist;
	// ripples fade out with distance so the far water stays smooth (and no shimmering/aliasing)
	float near_w = 1.0 - smoothstep(60.0, 700.0, dist);
	vec2 p = wpos.xz;
	float t = TIME;
	float a = vnoise(p * 0.35 + vec2(t * 0.25, t * 0.12));
	float b = vnoise(p * 2.6 - vec2(t * 0.35, -t * 0.2));
	float c = vnoise(p * 0.05 + vec2(t * 0.02, 0.0));
	float ripple = (a * 0.6 + b * 0.4);
	vec3 col = mix(deep_color, shallow_color, c * 0.6 + ripple * 0.15);
	// light patches like wind-ruffled water
	float patch = smoothstep(0.55, 0.8, b * a * 1.5) * 0.10 * near_w;
	col += vec3(patch);
	// sky reflection grows towards the horizon (fresnel)
	float fres = pow(1.0 - clamp(v.y, 0.0, 1.0), 3.0);
	col = mix(col, mix(sky_color, horizon_color, fres), clamp(fres * 0.6, 0.0, 1.0));
	// sun glint
	vec3 r = reflect(-v, normalize(vec3((a - 0.5) * 0.25 * near_w, 1.0, (b - 0.5) * 0.25 * near_w)));
	float glint = pow(max(dot(r, normalize(sun_dir)), 0.0), 90.0) * 0.5;
	col += vec3(1.0, 0.95, 0.85) * glint;
	// distance haze into the horizon colour
	float haze = smoothstep(haze_distance * 0.25, haze_distance, dist);
	col = mix(col, horizon_color, haze);
	ALBEDO = col;
}
