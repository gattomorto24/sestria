shader_type canvas_item;
// Sfondo del menu: la scena 3D sfocata, tinta di notte, con aloni lenti color brace e viola e un reticolo di esagoni.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 tint_a : source_color = vec4(0.028, 0.038, 0.100, 1.0);
uniform vec4 tint_b : source_color = vec4(0.085, 0.060, 0.200, 1.0);
uniform float blur_lod = 3.5;
uniform float strength = 0.86;
uniform float grid_scale = 26.0;

float hex_distance(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

vec4 hex_cell(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	return vec4(gv, uv - gv);
}

void fragment() {
	vec3 scene = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	float t = TIME * 0.05;
	vec3 base = mix(tint_a.rgb, tint_b.rgb, clamp(UV.y * 0.85 + 0.15 * sin(t * 4.0 + UV.x * 2.6), 0.0, 1.0));
	vec3 color = mix(scene * 0.55, base, strength);
	// aloni
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 q = UV * aspect;
	float g1 = exp(-length(q - vec2(0.15 + 0.12 * sin(t * 7.0), 0.18) * aspect) * 3.2);
	float g2 = exp(-length(q - vec2(0.90 + 0.08 * cos(t * 6.0), 0.85) * aspect) * 3.0);
	color += vec3(1.0, 0.55, 0.20) * g1 * 0.11 + vec3(0.45, 0.30, 1.0) * g2 * 0.15;
	// reticolo di esagoni
	vec4 cell = hex_cell(UV * aspect * grid_scale);
	float edge = smoothstep(0.43, 0.49, hex_distance(cell.xy));
	float pulse = 0.5 + 0.5 * sin(TIME * 0.4 + length(cell.zw) * 0.35);
	color += vec3(0.35, 0.45, 0.95) * edge * (0.018 + 0.016 * pulse);
	// vignettatura
	float v = smoothstep(0.95, 0.25, length(UV - 0.5));
	color *= 0.72 + 0.28 * v;
	COLOR = vec4(color, 1.0);
}
