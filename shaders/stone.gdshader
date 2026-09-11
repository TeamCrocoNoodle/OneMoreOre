shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(0.48, 0.50, 0.51, 1.0);
uniform float hovered : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
varying vec3 stone_position;

void vertex() {
	stone_position = VERTEX;
}

float grain_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	// Quiet irregular mineral flecks, without visible waves or repeated stripes.
	vec3 p = stone_position;
	float grain = grain_hash(floor(p * 165.0));
	float mineral = grain_hash(floor(p * 42.0 + vec3(14.0, 3.0, 8.0)));
	float texture_value = 0.985 + (grain - 0.5) * 0.025 + (mineral - 0.5) * 0.018;
	vec3 stone = base_color.rgb * COLOR.rgb * (1.4 * texture_value);
	stone = mix(stone, stone * vec3(1.13, 1.10, 1.01), hovered);
	ALBEDO = mix(stone, vec3(1.0, 0.92, 0.72), hit_flash * 0.83);
	ROUGHNESS = 1.0;
	EMISSION = vec3(1.0, 0.60, 0.22) * hit_flash * 0.24 + vec3(0.04, 0.028, 0.012) * hovered;
}

void light() {
	float diffuse = dot(NORMAL, LIGHT);
	float band = smoothstep(0.02, 0.08, diffuse) * 0.34;
	band += smoothstep(0.35, 0.42, diffuse) * 0.38;
	band += smoothstep(0.74, 0.82, diffuse) * 0.28;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band / PI;
}
