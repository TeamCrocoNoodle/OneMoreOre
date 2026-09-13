shader_type canvas_item;
render_mode unshaded;
uniform vec4 boss_tint : source_color = vec4(0.10,0.15,0.20,1.0);
uniform float boss_strength = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 p = uv - vec2(0.46, 0.43);
	p.x *= 1.35;
	float halo = exp(-dot(p, p) * 4.5);
	vec3 col = mix(vec3(0.035, 0.074, 0.105), vec3(0.19, 0.32, 0.37), halo);
	col += vec3(0.024, 0.025, 0.015) * smoothstep(0.8, 0.1, uv.y);
	float grain = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	col += (grain - 0.5) / 255.0;
	col = mix(col,boss_tint.rgb*(0.48+halo*2.0),boss_strength);
	COLOR = vec4(col, 1.0);
}
