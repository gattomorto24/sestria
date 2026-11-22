shader_type canvas_item;
render_mode blend_add;
// Due fiaccole agli angoli superiori: un alone caldo che sfarfalla piano.
uniform vec4 warm : source_color = vec4(1.0, 0.55, 0.18, 1.0);
float flicker(float t, float seed) {
	return 0.78 + 0.12 * sin(t * 7.3 + seed) + 0.07 * sin(t * 13.1 + seed * 2.3) + 0.05 * sin(t * 23.0 + seed * 5.1);
}
void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 p = UV * aspect;
	float a = exp(-length(p - vec2(0.02, 0.04) * aspect) * 3.6) * flicker(TIME, 1.0);
	float b = exp(-length(p - vec2(0.98, 0.04) * aspect) * 3.6) * flicker(TIME, 4.0);
	COLOR = vec4(warm.rgb * (a + b) * 0.20, 1.0);
}
