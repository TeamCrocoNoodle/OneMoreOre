extends StaticBody3D
## Faceted mineral crystals with opaque optical depth, fitted inside their owner.

signal emerged

const Geometry = preload("res://scripts/gem_geometry.gd")
const GEM_SHADER = preload("res://shaders/gem.gdshader")

const COMMON := 0
const SPECIAL := 1
const EMERGENCE_DURATION := 0.40
const LIGHT_COLORS := [Color("f3faff"), Color("64ff86"), Color("4896ff"), Color("ffe15b"), Color("be65ff"), Color("ff4c61")]
const LIGHT_NAMES := ["white", "green", "blue", "yellow", "purple", "red"]

var grade: int = COMMON
var variant: int = 0
var light_tier: int = 0
var collected: bool = false
var is_embedded: bool = false
var is_emerging: bool = false
var host_chunk: WeakRef
var bound_radius: float = 0.38
var visual := Node3D.new()
var facets: MeshInstance3D

var _material: ShaderMaterial
var _colliders: Array[CollisionShape3D] = []
var _reveal_tween: Tween
var _emergence_start_position := Vector3.ZERO
var _emergence_target_position := Vector3.ZERO
var _emergence_start_scale := Vector3.ONE
var _emergence_start_rotation := Quaternion.IDENTITY
var _emergence_target_rotation := Quaternion.IDENTITY


func configure(new_grade: int, new_variant: int = 0) -> void:
	_stop_emergence()
	grade = SPECIAL if new_grade == SPECIAL else COMMON
	variant = posmod(new_variant, 5)
	light_tier = 5 if grade == SPECIAL else variant
	collected = false
	is_embedded = false
	host_chunk = null
	show()
	# Ready before insertion into the tree, for the caller's placement checks.
	bound_radius = 0.52 if grade == SPECIAL else 0.40
	if is_node_ready():
		_build()


func _ready() -> void:
	visual.name = "Crystal"
	add_child(visual)
	_build()


func set_hovered(hovered: bool) -> void:
	if not is_instance_valid(_material):
		return
	var highlight := hovered and not collected and not is_embedded and not is_emerging
	_material.set_shader_parameter("hovered", 1.0 if highlight else 0.0)


func begin_collection() -> bool:
	if collected or is_embedded:
		return false
	# Ownership is awarded immediately when the containing stone breaks. The
	# already-started emergence is only a visual and may finish after the award.
	if not is_emerging:
		_stop_emergence()
	collected = true
	host_chunk = null
	_set_mining_enabled(false)
	set_hovered(false)
	return true


func embed_in_chunk(host: StaticBody3D) -> bool:
	if collected or is_emerging or not is_instance_valid(host) or host == self or host.get("destroyed") == true:
		return false
	if is_embedded:
		return host_chunk != null and host_chunk.get_ref() == host
	_stop_emergence()
	host_chunk = weakref(host)
	is_embedded = true
	# The owning stone has already fitted this entire body inside its solid mesh.
	# Preserve that local transform, including its smaller fitted collider.
	hide()
	_set_mining_enabled(false)
	set_hovered(false)
	return true


func release_from_chunk(parent: Node3D, target_position: Vector3) -> bool:
	if not is_embedded or collected or host_chunk == null:
		return false
	var host := host_chunk.get_ref() as StaticBody3D
	if not is_instance_valid(host) or host.get("destroyed") != true:
		return false
	if not is_instance_valid(parent) or parent == self or is_ancestor_of(parent):
		return false
	if not is_inside_tree() or not parent.is_inside_tree() or not target_position.is_finite():
		return false
	_stop_emergence()
	# Reparent before creating the bound tween: moving between parents enters and
	# exits the tree, and the actual internal starting world transform must survive.
	if get_parent() != parent:
		reparent(parent, true)
	is_embedded = false
	host_chunk = null
	is_emerging = true
	_set_mining_enabled(false)
	show()
	_emergence_start_position = position
	_emergence_target_position = target_position
	_emergence_start_scale = scale
	_emergence_start_rotation = quaternion
	_emergence_target_rotation = _presentation_rotation(parent, target_position - position)
	_reveal_tween = create_tween()
	_reveal_tween.tween_method(_animate_emergence, 0.0, 1.0, EMERGENCE_DURATION)
	_reveal_tween.tween_callback(_finish_emergence)
	return true


func _presentation_rotation(parent: Node3D, travel: Vector3) -> Quaternion:
	# A buried crystal keeps its random pose. As it comes out, present its broad
	# cut face so a thin side cannot hide the new shape and its internal facets.
	var toward_view := travel.normalized()
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera):
		toward_view = (parent.global_basis.inverse() * camera.global_basis.z).normalized()
	var up := (parent.global_basis.inverse() * Vector3.UP).normalized()
	var right := up.cross(toward_view).normalized()
	if toward_view.length_squared() < 0.5 or right.length_squared() < 0.5:
		return quaternion
	up = toward_view.cross(right).normalized()
	return Basis(right, up, toward_view).get_rotation_quaternion() * Quaternion(Vector3.UP, -0.22) * Quaternion(Vector3.BACK, -0.06)


func _animate_emergence(progress: float) -> void:
	if not is_emerging or is_embedded:
		return
	var travel := 1.0 - pow(1.0 - progress, 3.0)
	position = _emergence_start_position.lerp(_emergence_target_position, travel)
	position += Vector3.UP * sin(progress * PI) * 0.12
	quaternion = _emergence_start_rotation.slerp(_emergence_target_rotation, smoothstep(0.0, 1.0, progress))
	scale = _emergence_start_scale.lerp(Vector3.ONE, travel) + Vector3.ONE * sin(progress * PI) * 0.045


func _finish_emergence() -> void:
	_reveal_tween = null
	if not is_emerging or is_embedded:
		return
	position = _emergence_target_position
	quaternion = _emergence_target_rotation
	scale = Vector3.ONE
	is_emerging = false
	_set_mining_enabled(not collected)
	emerged.emit()


func _stop_emergence() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
		_reveal_tween = null
	is_emerging = false


func _set_mining_enabled(enabled: bool) -> void:
	# Collision layer changes immediately; shape updates defer safely if a caller
	# is resolving a physics hit. The visible model and collider share this body.
	collision_layer = 2 if enabled else 0
	collision_mask = 0
	for collider in _colliders:
		collider.set_deferred("disabled", not enabled)


func _exit_tree() -> void:
	# No timer, external signal connection, or unbound tween survives a reset.
	_stop_emergence()


func _build() -> void:
	for child in visual.get_children():
		visual.remove_child(child)
		child.queue_free()
	for collider in _colliders:
		remove_child(collider)
		collider.queue_free()
	_colliders.clear()
	collision_layer = 0 if collected or is_embedded or is_emerging else 2
	collision_mask = 0
	var geometry: Dictionary = Geometry.build(variant, grade == SPECIAL)
	_material = ShaderMaterial.new()
	_material.shader = GEM_SHADER
	var colors := _palette()
	_material.set_shader_parameter("base_color", colors[0])
	_material.set_shader_parameter("deep_color", colors[1])
	_material.set_shader_parameter("edge_color", colors[2])
	bound_radius = geometry.bound_radius
	_material.set_shader_parameter("crystal_radius", bound_radius)
	_material.set_shader_parameter("hovered", 0.0)
	facets = MeshInstance3D.new()
	facets.name = "SpecialCrystal" if grade == SPECIAL else "CommonCrystal%d" % variant
	facets.mesh = geometry.mesh
	facets.material_override = _material
	visual.add_child(facets)
	_add_convex(geometry.collider_points)


func _palette() -> Array[Color]:
	# A colored body and darker mineral interior preserve the tier even in shade.
	# Pale tinted edges replace the old alternating white and candy-color faces.
	if grade == SPECIAL:
		return [Color("cd5666"), Color("471d38"), Color("ffd2cc")]
	match variant:
		1: return [Color("4faa85"), Color("123b3d"), Color("bef3db")]
		2: return [Color("538ec4"), Color("172b50"), Color("c1e9fa")]
		3: return [Color("d6ae57"), Color("493321"), Color("fff1b9")]
		4: return [Color("9c79c7"), Color("322349"), Color("e4d4ff")]
	return [Color("bedee0"), Color("2f5663"), Color("edfffd")]


func _add_convex(points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	shape.margin = 0.002
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.disabled = collected or is_embedded or is_emerging
	_colliders.append(collider)
	add_child(collider)
