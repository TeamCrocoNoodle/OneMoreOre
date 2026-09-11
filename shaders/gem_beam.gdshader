shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 light_color : source_color = vec4(0.953, 0.98, 1.0, 1.0);
uniform float pulse_amount : hint_range(0.0, 2.0) = 0.0;
uniform int effect_kind = 0;
uniform float beam_growth = 1.0;

void vertex() {
	vec3 root = CUSTOM0.xyz;
	vec3 travel = CUSTOM1.xyz;
	vec3 spread = VERTEX - root - travel;
	VERTEX = root + travel * mix(0.72, 1.0, beam_growth) + spread * mix(0.65, 1.0, beam_growth);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float edge = 1.0 - smoothstep(0.92, 1.0, across);
	float inner_plane = 1.0 - smoothstep(0.54, 0.67, across);
	float reach = pow(max(1.0 - UV.y, 0.0), 1.18);
	float source = 1.0 - smoothstep(0.015, 0.20, UV.y);
	// Color the broad volume without bleaching it against the gray stone.
	// The separately drawn fissure and its halo provide the additive hot light.
	vec3 saturated = light_color.rgb * light_color.rgb;
	vec3 tint = mix(saturated, light_color.rgb, 0.28);
	tint = mix(tint, vec3(1.0), source * 0.44);
	ALBEDO = tint * (0.84 + inner_plane * 0.16);
	ALPHA = clamp(edge * reach * (0.80 + source * 0.20) * pulse_amount * COLOR.a, 0.0, 0.94);
}
