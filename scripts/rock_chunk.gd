class_name RockChunk
extends StaticBody3D

## hit() returns true on destruction and hides / disables this plate. Its mesh
## remains available to the caller for debris before the caller frees the node.
const STONE_SHADER := preload("res://shaders/stone.gdshader")

var health: float = 3.0
var max_health: float = 3.0
var layer_index: int = 0
var mesh_instance: MeshInstance3D
var base_position := Vector3.ZERO
var direction := Vector3.UP
var stone_color := Color.GRAY
var face_points := PackedVector3Array()
var face_center := Vector3.ZERO
var destroyed: bool = false

var _material: ShaderMaterial
var _shape: CollisionShape3D
var _crack_mesh: MeshInstance3D
var _crack_material: StandardMaterial3D
var _crack_segments: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _hovered: bool = false
var _hover_amount: float = 0.0
var _flash: float = 0.0
var _impact: float = 0.0
var _impact_time: float = 0.0


func configure(data: Dictionary, p_layer_index: int) -> void:
	layer_index = p_layer_index
	base_position = data["center"]
	position = base_position
	direction = data["normal"]
	stone_color = data["color"]
	face_points = data["face_points"]
	face_center = data.get("face_center", _average_points(face_points))
	_rng.seed = data.get("seed", 1)
	# Larger rocks contain hundreds of pieces: depth adds modest resistance
	# while every individual plate still breaks in a short, satisfying burst.
	var toughness := 3.0 if layer_index >= 2 else 2.0
	if _rng.randi_range(0, 4) == 0:
		toughness += 1.0
	max_health = clampf(float(data.get("health", toughness)), 2.0, 4.0)
	health = max_health
	collision_layer = 1
	collision_mask = 0
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = data["mesh"]
	_material = ShaderMaterial.new()
	_material.shader = STONE_SHADER
	_material.set_shader_parameter("base_color", stone_color)
	mesh_instance.material_override = _material
	add_child(mesh_instance)
	_shape = CollisionShape3D.new()
	_shape.shape = data["collision"]
	add_child(_shape)
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.albedo_color = Color(0.065, 0.075, 0.095)
	_crack_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crack_material.disable_receive_shadows = true
	_crack_mesh = MeshInstance3D.new()
	_crack_mesh.material_override = _crack_material
	_crack_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.add_child(_crack_mesh)
	_build_crack_paths()
	set_process(false)


func set_hovered(value: bool) -> void:
	if _hovered == value or destroyed:
		return
	_hovered = value
	set_process(true)


func hit(damage: float, point: Vector3) -> bool:
	if destroyed:
		return true
	health = maxf(health - damage, 0.0)
	_flash = 1.0
	_impact = minf(0.085 + damage * 0.012, 0.14)
	_impact_time = 0.0
	set_process(true)
	if health <= 0.0:
		destroyed = true
		visible = false
		collision_layer = 0
		_shape.set_deferred("disabled", true)
		return true
	# The branching network always grows from the first actual strike point.
	if _crack_mesh.mesh == null:
		var local_point := to_local(point)
		var planar_offset := local_point - face_center
		planar_offset -= direction * planar_offset.dot(direction)
		# Clamp a bevel strike just inside the face, while preserving the actual
		# impact location when the player strikes toward a plate's edges.
		var inside_factor := 1.0
		for i in face_points.size():
			var edge_start := face_points[i]
			var edge_end := face_points[(i + 1) % face_points.size()]
			var inward := direction.cross(edge_end - edge_start).normalized()
			var center_distance := inward.dot(face_center - edge_start)
			var point_distance := inward.dot(face_center + planar_offset - edge_start)
			if point_distance < 0.045 and center_distance > 0.045:
				inside_factor = minf(inside_factor, (center_distance - 0.045) / (center_distance - point_distance))
		_build_crack_paths(face_center + planar_offset * maxf(inside_factor, 0.0))
	_redraw_cracks(1.0 - health / max_health)
	return false


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 7.8)
	_hover_amount = move_toward(_hover_amount, 1.0 if _hovered else 0.0, delta * 8.0)
	_impact_time += delta
	_impact = move_toward(_impact, 0.0, delta * 0.34)
	mesh_instance.position = -direction * sin(_impact_time * 42.0) * _impact
	_material.set_shader_parameter("hit_flash", _flash)
	_material.set_shader_parameter("hovered", _hover_amount)
	if _flash <= 0.0 and _impact <= 0.0 and is_equal_approx(_hover_amount, 1.0 if _hovered else 0.0):
		mesh_instance.position = Vector3.ZERO
		set_process(false)


func _build_crack_paths(origin: Vector3 = Vector3.INF) -> void:
	_crack_segments.clear()
	if origin == Vector3.INF:
		origin = face_center
	var branch_count := 5
	for branch in branch_count:
		var edge_index := int(float(branch) / float(branch_count) * face_points.size()) % face_points.size()
		var target := face_points[edge_index].lerp(face_points[(edge_index + 1) % face_points.size()], _rng.randf_range(0.15, 0.70))
		var previous := origin
		var travel := target - origin
		var sideways := direction.cross(travel).normalized()
		for step in 5:
			var progress := float(step + 1) / 5.0
			var point := origin.lerp(target, progress)
			if step < 4:
				point += sideways * _rng.randf_range(-0.075, 0.075) * sin(progress * PI)
			_crack_segments.append({"a": previous, "b": point, "start": float(step) / 5.0, "end": progress, "branch": branch, "weight": 1.0})
			if step == 2:
				var branch_target := point.lerp(face_points[(edge_index + 2) % face_points.size()], 0.43)
				var branch_middle := point.lerp(branch_target, 0.48) + sideways * 0.032
				_crack_segments.append({"a": point, "b": branch_middle, "start": 0.57, "end": 0.74, "branch": branch, "weight": 0.56})
				_crack_segments.append({"a": branch_middle, "b": branch_target, "start": 0.74, "end": 0.96, "branch": branch, "weight": 0.40})
			previous = point


func _redraw_cracks(damage_ratio: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var growth := clampf(damage_ratio * 1.18 + 0.08, 0.0, 1.0)
	var width := lerpf(0.006, 0.022, damage_ratio)
	for segment in _crack_segments:
		var branch_growth := growth - float(int(segment["branch"]) % 3) * 0.055
		var start: float = segment["start"]
		if branch_growth <= start:
			continue
		var a: Vector3 = segment["a"] + direction * 0.006
		var end: Vector3 = segment["b"] + direction * 0.006
		var b := a.lerp(end, clampf((branch_growth - start) / (float(segment["end"]) - start), 0.0, 1.0))
		var side := direction.cross(b - a).normalized() * width * float(segment["weight"]) * (1.0 - start * 0.6)
		for vertex: Vector3 in [a - side, a + side, b + side * 0.67, a - side, b + side * 0.67, b - side * 0.67]:
			surface.set_normal(direction)
			surface.add_vertex(vertex)
	_crack_mesh.mesh = surface.commit()


func _average_points(points: PackedVector3Array) -> Vector3:
	var average := Vector3.ZERO
	for point in points:
		average += point
	return average / maxf(float(points.size()), 1.0)
