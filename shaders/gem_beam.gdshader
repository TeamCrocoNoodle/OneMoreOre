shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 light_color : source_color = vec4(0.953, 0.98, 1.0, 1.0);
uniform float pulse_amount : hint_range(0.0, 2.0) = 0.0;
uniform int effect_kind = 0;
uniform float beam_growth = 1.0;

void vertex() {
	vec3 root = CUSTOM0.xyz;
	VERTEX = root + CUSTOM1.xyz * mix(0.72, 1.0, beam_growth);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	// The slit masks the light into a continuous flat band. Its boundaries
	// start crisp and develop a small penumbra with distance from the opening.
	float edge = 1.0 - smoothstep(mix(0.99, 0.84, UV.y), 1.0, across);
	float reach = (1.0 - smoothstep(0.45, 1.0, UV.y)) / (1.0 + UV.y * 3.0);
	float source = 1.0 - smoothstep(0.0, 0.24, UV.y);
	vec3 saturated = light_color.rgb * light_color.rgb;
	vec3 tint = mix(saturated, light_color.rgb, 0.40);
	ALBEDO = mix(tint, vec3(1.0), source * 0.22);
	ALPHA = clamp(edge * reach * pulse_amount * COLOR.a, 0.0, 0.80);
}
