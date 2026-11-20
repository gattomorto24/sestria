shader_type spatial;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.);
uniform vec2 tiling = vec2(1.15, .23);
uniform vec2 grain_offset = vec2(0.);
uniform float relief = .021;
uniform bool fabric = false;

varying vec3 local_point;
varying vec3 local_normal;

void vertex() {
	local_point = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec2 uv = local_point.xz;
	if (abs(local_normal.x) > .86 && !fabric) {
		uv.x = local_point.y + .24;
	}
	if (abs(local_normal.z) > .86) {
		uv.y = local_point.y - .31;
	}
	uv = uv * tiling + grain_offset;
	vec2 surface = texture(surface_map, uv).rg;
	vec3 finish = texture(albedo_map, uv).rgb;
	ALBEDO = finish * tint.rgb;
	ROUGHNESS = surface.g;
	SPECULAR = fabric ? .25 : .38;

	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 cross_x = cross(dy, NORMAL);
	vec3 cross_y = cross(NORMAL, dx);
	float determinant = dot(dx, cross_x);
	vec3 gradient = dFdx(surface.r) * cross_x + dFdy(surface.r) * cross_y;
	NORMAL = normalize(max(abs(determinant), 0.000001) * NORMAL - sign(determinant) * gradient * relief);
}
