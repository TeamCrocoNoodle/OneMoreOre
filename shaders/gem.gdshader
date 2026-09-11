shader_type spatial;
render_mode cull_back, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.36, 0.72, 0.75, 1.0);
uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.29, 1.0);
uniform vec4 edge_color : source_color = vec4(0.72, 0.95, 0.94, 1.0);
uniform float crystal_radius = 0.4;
uniform float hovered : hint_range(0.0, 1.0) = 0.0;
varying vec3 crystal_position;
varying vec3 crystal_normal;
varying vec3 local_view;

void vertex() {
	crystal_position = VERTEX / crystal_radius;
	crystal_normal = NORMAL;
	// A direction, rather than a camera position, also works for the game's
	// orthographic camera and the uniformly fitted, temporarily smaller gems.
	local_view = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
}

float mineral_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float cloud(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mineral_hash(cell), mineral_hash(cell + vec3(1, 0, 0)), f.x);
	float b = mix(mineral_hash(cell + vec3(0, 1, 0)), mineral_hash(cell + vec3(1, 1, 0)), f.x);
	float c = mix(mineral_hash(cell + vec3(0, 0, 1)), mineral_hash(cell + vec3(1, 0, 1)), f.x);
	float d = mix(mineral_hash(cell + vec3(0, 1, 1)), mineral_hash(cell + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

vec4 interior_cut(vec3 origin, vec3 ray) {
	// Intersect a second set of mineral planes inside the solid. Refraction
	// moves their silhouettes behind the outer facets when the stone turns.
	float nearest = 100.0;
	vec3 result = vec3(0, 0, -1);
	for (int i = 0; i < 10; i++) {
		float angle = float(i) * 2.3999632 + 0.31;
		float y = -0.84 + float(i) * 0.187;
		vec3 n = normalize(vec3(cos(angle), y * 1.28, sin(angle)));
		float extent = 0.53 + abs(n.y) * 0.24;
		float denominator = dot(n, ray);
		if (denominator > 0.0001) {
			float distance = (extent - dot(n, origin)) / denominator;
			if (distance > 0.0 && distance < nearest) {
				nearest = distance;
				result = n;
			}
		}
	}
	return vec4(result, nearest);
}

void fragment() {
	vec3 p = crystal_position;
	vec3 n = normalize(crystal_normal);
	vec3 eye = normalize(local_view);
	vec3 ray = refract(-eye, n, 0.67);
	vec4 cut = interior_cut(p * 0.53, ray);
	vec3 inner = cut.xyz;
	vec3 deeper = interior_cut(p * 0.36 + vec3(0.08, -0.03, 0.02), normalize(ray + vec3(0.12, 0.08, -0.07))).xyz;
	vec3 mineral_light = normalize(vec3(-0.48, 0.73, 0.46));
	float inner_value = dot(-inner, mineral_light) * 0.5 + 0.5;
	float deep_value = dot(-deeper, mineral_light) * 0.5 + 0.5;
	float mist = cloud(p * 3.2 + inner * 1.7);
	float absorption = smoothstep(0.42, 1.22, cut.w);
	float depth = clamp(0.24 + inner_value * 0.48 + deep_value * 0.16 - absorption * 0.24 + (mist - 0.5) * 0.30, 0.16, 0.89);
	vec3 body = mix(deep_color.rgb, base_color.rgb, depth);
	// Large polished cuts remain legible. Only actual narrow chamfers get a
	// pale edge; triangulation inside a single polygon never draws an outline.
	float bevel = UV2.y;
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.2);
	body = mix(body, edge_color.rgb * 0.73, bevel * 0.035 + rim * 0.16);
	body *= COLOR.rgb;
	vec3 reflection = reflect(-normalize(VIEW), normalize(NORMAL));
	float studio = smoothstep(0.19, 0.58, reflection.y) * (1.0 - smoothstep(0.42, 0.88, abs(reflection.x + 0.22)));
	float window = smoothstep(0.62, 0.90, dot(reflection, normalize(vec3(-0.30, 0.55, 0.78))));
	vec3 inner_reflection = reflect(ray, -inner);
	float caustic = pow(max(dot(inner_reflection, mineral_light), 0.0), 5.0);
	float inner_sheen = pow(inner_value, 3.0) * (0.055 + 0.10 * smoothstep(-0.65, 0.8, p.y));
	float polish = studio * 0.21 + window * 0.28;
	float crown_glint = smoothstep(0.62, 0.88, n.y) * smoothstep(0.40, 0.75, p.y);
	ALBEDO = mix(body, body * vec3(1.10, 1.07, 1.01), hovered);
	ROUGHNESS = 0.38;
	METALLIC = 0.0;
	EMISSION = mix(edge_color.rgb, vec3(1.0), 0.68) * polish;
	EMISSION += edge_color.rgb * (inner_sheen + caustic * 0.38 + rim * 0.08);
	EMISSION += mix(edge_color.rgb, vec3(1.0), 0.82) * crown_glint * (0.36 + facing * 0.16);
	EMISSION += base_color.rgb * (0.055 + hovered * 0.07);
}

void light() {
	float diffuse = dot(NORMAL, LIGHT);
	float band = smoothstep(0.02, 0.08, diffuse) * 0.34;
	band += smoothstep(0.35, 0.42, diffuse) * 0.38;
	band += smoothstep(0.74, 0.82, diffuse) * 0.28;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band / PI;
	float highlight = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 18.0);
	DIFFUSE_LIGHT += edge_color.rgb * LIGHT_COLOR * ATTENUATION * highlight * 0.18;
}
