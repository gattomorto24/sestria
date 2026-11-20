shader_type spatial;

uniform vec4 low : source_color = vec4(.13,.055,.026,1.);
uniform vec4 high : source_color = vec4(.47,.26,.11,1.);
uniform int material_kind = 0;
uniform float scale_factor = 1.0;
uniform float metal = 0.0;
uniform float rough = 0.76;
varying vec3 local_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(31.591, 113.97, 88.41))) * 43758.54);
}
float noise3(vec3 p) {
	vec3 f = fract(p);
	vec3 i = floor(p);
	f = f * f * (3. - 2. * f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),
		mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),
		mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() {
	local_pos = VERTEX;
}
void fragment() {
	vec3 p = local_pos * scale_factor;
	float fleck = noise3(p * 90.);
	float grain = noise3(p*6.);
	float relief = grain;
	if (material_kind == 0) {
		vec3 stripe = vec3(p.x*42.,p.y*28.,p.z*2.1);
		float warp = noise3(p*vec3(3.,5.,.9))*3.2;
		float fiber = noise3(stripe + warp);
		float pores = noise3(stripe * vec3(2.4,2.2,1.));
		grain = .34*fiber + .27*pores + .28*noise3(stripe*.27) + .11*fleck;
		grain -= smoothstep(.55,.8,pores)*.25;
		relief = fiber*.65 + pores*.35;
	}
	if (material_kind == 1) {
		vec2 g = p.xz*133.;
		vec2 weave_filter = 1. - smoothstep(vec2(.17),vec2(.62),fwidth(g));
		float warp = sin(g.x*6.283)*cos(g.y*3.1415);
		float weft = sin(g.y*6.283)*cos(g.x*3.1415);
		relief = .5+.24*(warp*weave_filter.x+weft*weave_filter.y);
		grain = .48 + (relief-.5)*.32 + (noise3(p*3.)-.5)*.34 + fleck*.1;
	}
	if (material_kind == 2) {
		grain = .53 + (grain-.5)*.7 + (fleck-.5)*.2;
		relief = fleck*.28+grain*.72;
	}
	ALBEDO = mix(low.rgb,high.rgb,clamp(grain,0.,1.));
	ROUGHNESS = clamp(rough + (fleck-.5)*.2,.12,1.);
	METALLIC = metal;
	vec3 perturb = normalize(vec3(-dFdx(relief)*.32,-dFdy(relief)*.32,1.));
	NORMAL_MAP = .5 + perturb*.5;
	NORMAL_MAP_DEPTH = .3;
}
