shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 light_color : source_color = vec4(0.953, 0.98, 1.0, 1.0);
uniform float pulse_amount : hint_range(0.0, 2.0) = 0.0;
uniform int effect_kind = 0;
uniform float beam_growth = 1.0;
uniform float effect_progress = 0.0;
uniform vec3 camera_right = vec3(1.0, 0.0, 0.0);
uniform vec3 camera_up = vec3(0.0, 1.0, 0.0);

void vertex() {
	if (effect_kind == 4) {
		vec3 root = CUSTOM0.xyz;
		vec3 travel = CUSTOM1.xyz;
		vec3 spread = VERTEX - root - travel;
		VERTEX = root + travel * mix(0.72, 1.0, beam_growth) + spread * mix(0.65, 1.0, beam_growth);
	} else if (effect_kind == 2) {
		float travel = CUSTOM0.w + effect_progress * 0.18;
		float size = CUSTOM1.z * sin(travel * PI);
		vec2 corner = (UV * 2.0 - 1.0) * size + CUSTOM1.xy;
		VERTEX += CUSTOM0.xyz * travel + camera_right * corner.x + camera_up * corner.y;
		COLOR.a = travel < 1.0 ? 1.0 - travel * 0.6 : 0.0;
	}
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float alpha = 0.0;
	vec3 tint = light_color.rgb;
	if (effect_kind == 4) {
		// Illuminate the entire slit evenly. Keep the hot light close to its
		// line-shaped root instead of forming a bright triangular point flare.
		float edge = 1.0 - smoothstep(0.97, 1.0, across);
		float source = 1.0 - smoothstep(0.005, 0.10, UV.y);
		alpha = edge * 0.90 * pow(source, 1.5);
		tint = mix(tint, vec3(1.0), source * 0.24) * 1.30;
	} else if (effect_kind == 1) {
		// A hot core stays on the actual fracture, with colored light around it.
		float core = 1.0 - smoothstep(0.25, 0.72, across);
		alpha = 1.0 - smoothstep(0.68, 1.0, across);
		tint = mix(tint, vec3(1.0), 0.12 + core * 0.28) * 1.32;
	} else if (effect_kind == 2) {
		// Small separated diamond sparks support the large rays.
		vec2 centered = abs(UV * 2.0 - 1.0);
		float distance = centered.x + centered.y;
		float diamond = 1.0 - smoothstep(0.57, 0.70, distance);
		float halo = 1.0 - smoothstep(0.45, 1.10, distance);
		alpha = diamond * 0.84 + halo * 0.16;
		tint = mix(tint, vec3(1.0), diamond * 0.28) * 1.16;
	} else {
		// Only a narrow halo spills onto the neighboring rock surface.
		alpha = pow(max(1.0 - across, 0.0), 1.55) * 0.34;
		tint *= 1.12;
	}
	ALBEDO = tint;
	ALPHA = clamp(alpha * pulse_amount * COLOR.a, 0.0, 1.0);
}
