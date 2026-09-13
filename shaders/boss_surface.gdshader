shader_type spatial;
render_mode specular_disabled;
uniform vec4 tint : source_color = vec4(0.4,0.5,0.6,1.0);
uniform float glow = 0.0;
void fragment() {
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.85;
	EMISSION = tint.rgb * glow;
}
void light() {
	float d = dot(NORMAL,LIGHT);
	float step_light = smoothstep(0.01,0.07,d)*0.34 + smoothstep(0.34,0.41,d)*0.38 + smoothstep(0.72,0.80,d)*0.28;
	DIFFUSE_LIGHT += ALBEDO*LIGHT_COLOR*ATTENUATION*step_light/PI;
}
