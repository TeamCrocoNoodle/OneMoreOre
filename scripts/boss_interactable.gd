extends StaticBody3D
## The three physical defusal wires share ordinary mouse/touch/controller rays.
var materials: Array[ShaderMaterial] = []
var cut := false
func set_hovered(value: bool) -> void:
	for material in materials: material.set_shader_parameter("glow",0.35 if value else 0.10)

func sever() -> void:
	cut = true
	collision_layer = 0
	hide()
