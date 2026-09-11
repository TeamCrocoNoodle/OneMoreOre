shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 light_color : source_color = vec4(0.953, 0.98, 1.0, 1.0);
uniform float pulse_amount : hint_range(0.0, 2.0) = 0.0;
uniform float age = 0.0;
uniform int effect_kind = 0;

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float edge = 1.0 - smoothstep(0.12, 1.0, across);
	float core = 1.0 - smoothstep(0.0, 0.24, across);
	float alpha = 0.0;
	vec3 tint = light_color.rgb;
	if (effect_kind == 0) {
		// Soft-sided tapered shafts, with a clean bright spine: no bloom required.
		float along = mix(1.0, 0.76, UV.y);
		float tip = 1.0 - smoothstep(0.62, 1.0, UV.y);
		float traveling = 0.91 + 0.09 * sin(UV.y * 15.0 - age * 11.0);
		alpha = (edge * 0.61 + core * 0.25) * along * tip * traveling;
		tint = mix(tint, vec3(1.0), core * 0.08 * (1.0 - UV.y));
		tint *= 1.28;
	} else if (effect_kind == 1) {
		// The luminous fissure stays crisp against the dark stone around it.
		alpha = mix(0.62, 1.0, core) * (1.0 - smoothstep(0.70, 1.0, across));
		tint = mix(tint, vec3(1.0), 0.035 + core * 0.10) * 1.18;
	} else {
		vec2 centered = abs(UV * 2.0 - 1.0);
		float diamond = 1.0 - smoothstep(0.35, 1.0, centered.x + centered.y);
		float cross_shape = max(pow(1.0 - centered.x, 10.0), pow(1.0 - centered.y, 10.0));
		alpha = max(diamond * 0.8, cross_shape * 0.6) * (1.0 - max(centered.x, centered.y));
		tint = mix(tint, vec3(1.0), 0.16);
	}
	ALBEDO = tint;
	ALPHA = clamp(alpha * pulse_amount * COLOR.a, 0.0, 1.0);
}
