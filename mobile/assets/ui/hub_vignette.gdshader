shader_type canvas_item;
// Bordi scuri come in una taverna illuminata da candele: il tavolo 3D resta visibile al centro e non viene sfocato.
uniform float strength = 0.62;
void fragment() {
	float d = length((UV - 0.5) * vec2(1.15, 1.0));
	float v = smoothstep(0.30, 0.95, d);
	COLOR = vec4(0.045, 0.02, 0.008, v * strength + 0.10);
}
