shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(0.48, 0.50, 0.51, 1.0);
uniform float hovered : hint_range(0.0, 1.0) = 0.0;
uniform float attack_preview : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform int ore_theme = 0;
uniform float theme_detail = 1.0;
uniform vec4 ore_accent : source_color = vec4(0.65, 0.7, 0.7, 1.0);
uniform vec3 stone_origin = vec3(0.0);
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
	// Broad, matte mineral patterns travel with the rock and its facets.
	// They emit no light, keeping luminous cracks exclusive to real gems.
	vec3 q = p + stone_origin;
	float patch = grain_hash(floor(q * 2.6));
	float band = fract(q.y * 0.72 + q.x * 0.24 + q.z * 0.18);
	float tint = 0.0;
	if (ore_theme == 1) {
		tint = step(0.63, patch) * 0.38 + step(0.87, grain_hash(floor(q * 9.0))) * 0.13;
	} else if (ore_theme == 2) {
		tint = step(0.89, band) * 0.31 + step(0.96, mineral) * 0.12;
	} else if (ore_theme == 3) {
		tint = step(0.92, grain_hash(floor(q * 14.0))) * 0.55 + step(0.80, patch) * 0.18;
	} else if (ore_theme == 4) {
		tint = step(0.96, band) * 0.35;
	} else if (ore_theme == 5) {
		tint = step(0.84, band) * 0.38 + step(0.78, patch) * 0.19;
	} else if (ore_theme == 6) {
		tint = step(0.89, band) * 0.44 + step(0.81, patch) * 0.32;
	}
	stone = mix(stone, ore_accent.rgb * COLOR.rgb * 1.4, tint * theme_detail);
	stone = mix(stone, stone * vec3(1.13, 1.10, 1.01), hovered);
	stone = mix(stone, stone * vec3(1.16, 1.10, 0.94) + vec3(0.025, 0.020, 0.010), attack_preview * 0.60);
	ALBEDO = mix(stone, vec3(1.0, 0.92, 0.72), hit_flash * 0.83);
	ROUGHNESS = 1.0;
	EMISSION = vec3(1.0, 0.60, 0.22) * hit_flash * 0.24 + vec3(0.04, 0.028, 0.012) * hovered + vec3(0.012, 0.010, 0.005) * attack_preview;
}

void light() {
	float diffuse = dot(NORMAL, LIGHT);
	float band = smoothstep(0.02, 0.08, diffuse) * 0.34;
	band += smoothstep(0.35, 0.42, diffuse) * 0.38;
	band += smoothstep(0.74, 0.82, diffuse) * 0.28;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band / PI;
}
