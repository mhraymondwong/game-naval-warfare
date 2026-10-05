shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.035, 0.16, 0.34, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.16, 0.48, 0.58, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.90, 0.92, 1.0);

varying float crest;
varying vec3 world_pos;

float sea_h(vec2 xz) {
	float h = 0.0;
	h += sin(dot(xz, vec2(0.0085, 0.0035)) + TIME * 0.75) * 5.5;
	h += sin(dot(xz, vec2(-0.0045, 0.0105)) + TIME * 1.05) * 3.2;
	h += sin(dot(xz, vec2(0.016, -0.012)) + TIME * 1.45) * 1.4;
	return h;
}

float ripple(vec2 xz) {
	float r = 0.0;
	r += sin(xz.x * 0.09 + TIME * 1.55);
	r += sin(xz.y * 0.12 - TIME * 1.2);
	r += sin(dot(xz, vec2(0.17, 0.11)) + TIME * 2.05) * 0.65;
	r += sin(dot(xz, vec2(-0.21, 0.16)) - TIME * 1.75) * 0.4;
	return r;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = sea_h(world.xz);
	VERTEX.y += h;
	float e = 20.0;
	float hx = sea_h(world.xz + vec2(e, 0.0));
	float hz = sea_h(world.xz + vec2(0.0, e));
	NORMAL = normalize(vec3(-(hx - h) / e, 1.0, -(hz - h) / e));
	crest = h;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float e2 = 1.5;
	float h0 = ripple(world_pos.xz);
	float hx = ripple(world_pos.xz + vec2(e2, 0.0));
	float hz = ripple(world_pos.xz + vec2(0.0, e2));
	vec3 nworld = normalize(vec3(-(hx - h0) / e2 * 2.4, 1.0, -(hz - h0) / e2 * 2.4));
	NORMAL = normalize(mat3(VIEW_MATRIX) * nworld);
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndotv, 2.8);
	float band = clamp(h0 * 0.22 + 0.5, 0.0, 1.0);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, clamp(fres * 0.72 + band * 0.34, 0.0, 1.0));
	float foam = smoothstep(3.2, 7.2, crest);
	col = mix(col, foam_color.rgb, foam * 0.5);
	ALBEDO = col;
	ROUGHNESS = mix(0.10, 0.46, fres);
	METALLIC = 0.02;
}
