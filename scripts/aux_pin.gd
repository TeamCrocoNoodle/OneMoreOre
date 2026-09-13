extends StaticBody3D
const Visual = preload("res://scripts/aux_tool_visual.gd")
var driven := 0
var anchor: WeakRef
var model: Node3D
var origin := Vector3.ZERO
var surface_normal := Vector3.BACK

func _ready() -> void:
	name = "SplittingPin"
	collision_layer = 1
	collision_mask = 0
	model = Visual.new()
	model.build("pin")
	model.scale = Vector3.ONE*0.45
	add_child(model)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.19
	cap.height = 0.50
	shape.shape = cap
	shape.position.y = 0.21
	add_child(shape)
	set_meta("splitting_pin",true)

func drive() -> int:
	driven += 1
	position = origin-surface_normal*driven*0.105
	return driven

func set_hovered(_hovered: bool) -> void:
	pass
