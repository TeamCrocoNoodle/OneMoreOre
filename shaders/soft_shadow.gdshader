shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

void fragment() {
	float r = length((UV - 0.5) * 2.0);
	ALBEDO = vec3(0.012, 0.03, 0.045);
	ALPHA = pow(max(0.0, 1.0 - r * r), 2.4) * 0.55;
}
