class_name RockChunk
extends StaticBody3D

## hit() returns true on destruction and hides / disables this plate. Its mesh
## remains available to the caller for debris before the caller frees the node.
const STONE_SHADER := preload("res://shaders/stone.gdshader")
const GemLight := preload("res://scripts/gem_light.gd")
const GEM_COVER_HEALTH := 16.0
const MAX_CRACK_NETWORKS := 16
const MAX_CRACK_CONNECTORS := 32

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
var cover_gem: WeakRef
var cover_tier: int = 0
var is_gem_cover: bool = false
var light_node: Node3D
var latest_impact_local := Vector3.ZERO
var impact_count: int = 0
var gem_socket_center := Vector3.ZERO
var gem_socket_radius: float = 0.0
var contained_gem: WeakRef

var _material: ShaderMaterial
var _shape: CollisionShape3D
var _crack_mesh: MeshInstance3D
var _crack_material: StandardMaterial3D
var _crack_segments: Array[Dictionary] = []
var _crack_networks: Array[Dictionary] = []
var _crack_connectors: Array[Dictionary] = []
var _face_extent: float = 0.5
var _containment_planes: Array[Plane] = []
var _rng := RandomNumberGenerator.new()
var _hovered: bool = false
var _hover_amount: float = 0.0
var _flash: float = 0.0
var _impact: float = 0.0
var _impact_time: float = 0.0
var _cover_hit_count: int = 0
var _stone_seed: int = 1


func configure(data: Dictionary, p_layer_index: int) -> void:
	layer_index = p_layer_index
	base_position = data["center"]
	position = base_position
	direction = data["normal"]
	stone_color = data["color"]
	face_points = data["face_points"]
	face_center = data.get("face_center", _average_points(face_points))
	latest_impact_local = face_center
	_face_extent = 0.0
	for face_point in face_points:
		_face_extent += face_point.distance_to(face_center)
	_face_extent /= maxf(float(face_points.size()), 1.0)
	_rng.seed = data.get("seed", 1)
	_stone_seed = int(data.get("seed", 1))
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
	_configure_gem_socket(data["mesh"])
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.albedo_color = Color(0.065, 0.075, 0.095)
	_crack_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crack_material.disable_receive_shadows = true
	_crack_mesh = MeshInstance3D.new()
	_crack_mesh.material_override = _crack_material
	_crack_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.add_child(_crack_mesh)
	set_process(false)


func get_containment_planes() -> Array[Plane]:
	# Outward-facing planes from the actual rendered triangles. A point is
	# inside this conservative volume when every plane distance is <= 0.
	return _containment_planes.duplicate()


func _configure_gem_socket(mesh: ArrayMesh) -> void:
	_containment_planes.clear()
	var axis_min := INF
	var axis_max := -INF
	for surface_index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for vertex in vertices:
			axis_min = minf(axis_min, vertex.dot(direction))
			axis_max = maxf(axis_max, vertex.dot(direction))
		var index_count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, index_count - 2, 3):
			var a_index := indices[i] if not indices.is_empty() else i
			var b_index := indices[i + 1] if not indices.is_empty() else i + 1
			var c_index := indices[i + 2] if not indices.is_empty() else i + 2
			var a := vertices[a_index]
			var b := vertices[b_index]
			var c := vertices[c_index]
			var outward := (c - a).cross(b - a).normalized()
			if outward.length_squared() < 0.1:
				continue
			if a_index < normals.size() and outward.dot(normals[a_index]) < 0.0:
				outward = -outward
			var plane := Plane(outward, outward.dot(a))
			var duplicate := false
			for existing in _containment_planes:
				if existing.normal.dot(plane.normal) > 0.99999 and absf(existing.d - plane.d) < 0.00001:
					duplicate = true
					break
			if not duplicate:
				_containment_planes.append(plane)
	if _containment_planes.is_empty():
		gem_socket_radius = 0.0
		return
	# Clearance is concave along a line. A short bounded search along the
	# plate's radial axis starts near the widest region of its true thickness.
	var left := axis_min
	var right := axis_max
	for iteration in 22:
		var first := lerpf(left, right, 1.0 / 3.0)
		var second := lerpf(left, right, 2.0 / 3.0)
		if _socket_clearance(direction * first) < _socket_clearance(direction * second):
			left = first
		else:
			right = second
	gem_socket_center = direction * ((left + right) * 0.5)
	var clearance := _socket_clearance(gem_socket_center)
	var tangent := direction.cross(Vector3.UP).normalized()
	if tangent.length_squared() < 0.1:
		tangent = direction.cross(Vector3.RIGHT).normalized()
	var bitangent := direction.cross(tangent).normalized()
	var search_axes: Array[Vector3] = [direction, tangent, bitangent]
	var step := minf((axis_max - axis_min) * 0.14, _face_extent * 0.18)
	# Modest local refinement helps irregular narrow plates without a general
	# optimizer or physics queries for every one of the 322 static chunks.
	for iteration in 8:
		for sweep in 2:
			for axis in search_axes:
				var best_center := gem_socket_center
				var best_clearance := clearance
				for sign_value: float in [-1.0, 1.0]:
					var candidate := gem_socket_center + axis * step * sign_value
					var candidate_clearance := _socket_clearance(candidate)
					if candidate_clearance > best_clearance:
						best_center = candidate
						best_clearance = candidate_clearance
				gem_socket_center = best_center
				clearance = best_clearance
		step *= 0.5
	# Intersecting all oriented triangle half-spaces is conservative even at
	# the plate's concave inner cap; the result also stays inside its hull collider.
	gem_socket_radius = maxf(clearance - 0.006, 0.0)


func _socket_clearance(point: Vector3) -> float:
	var clearance := INF
	for plane in _containment_planes:
		clearance = minf(clearance, plane.d - plane.normal.dot(point))
	return clearance


func contain_gem(jewel: StaticBody3D) -> bool:
	if destroyed or contained_gem != null or gem_socket_radius <= 0.025:
		return false
	if not is_instance_valid(jewel) or jewel.is_queued_for_deletion() or not jewel.has_method("embed_in_chunk"):
		return false
	if bool(jewel.get("collected")) or bool(jewel.get("is_embedded")) or bool(jewel.get("is_emerging")):
		return false
	var bound := float(jewel.get("bound_radius"))
	if bound <= 0.0:
		return false
	var margin := maxf(0.012, gem_socket_radius * 0.04)
	var fitted_scale := minf(1.0, (gem_socket_radius - margin) / bound)
	if fitted_scale <= 0.0:
		return false
	var previous_parent: Node = jewel.get_parent()
	var previous_transform := jewel.transform
	if previous_parent == null:
		mesh_instance.add_child(jewel)
	else:
		jewel.reparent(mesh_instance, false)
	jewel.position = gem_socket_center
	jewel.scale = Vector3.ONE * fitted_scale
	contained_gem = weakref(jewel)
	if not bool(jewel.call("embed_in_chunk", self)):
		contained_gem = null
		if is_instance_valid(previous_parent):
			jewel.reparent(previous_parent, false)
		else:
			mesh_instance.remove_child(jewel)
		jewel.transform = previous_transform
		return false
	configure_gem_cover(jewel, int(jewel.get("light_tier")))
	return true


func configure_gem_cover(jewel: StaticBody3D, tier: int) -> void:
	if destroyed or not is_instance_valid(jewel) or jewel.is_queued_for_deletion():
		return
	if contained_gem != null and contained_gem.get_ref() != jewel:
		return
	var jewel_host := jewel.get("host_chunk") as WeakRef
	if bool(jewel.get("is_embedded")) and (jewel_host == null or jewel_host.get_ref() != self):
		return
	if bool(jewel.get("collected")):
		return
	# Main may discover the same final obstruction more than once. Repeating
	# its designation must never replenish a cover the player is already mining.
	if is_gem_cover and cover_gem != null and cover_gem.get_ref() == jewel:
		cover_tier = clampi(tier, 0, 5)
		return
	cover_gem = weakref(jewel)
	cover_tier = clampi(tier, 0, 5)
	is_gem_cover = true
	_cover_hit_count = 0
	var previous_damage := maxf(max_health - health, 0.0)
	max_health = maxf(max_health, GEM_COVER_HEALTH)
	health = maxf(max_health - previous_damage, 1.0)
	if not is_instance_valid(light_node):
		light_node = GemLight.new()
		light_node.name = "HiddenGemLight"
		mesh_instance.add_child(light_node)
	light_node.call("clear")
	light_node.call("configure", face_points, face_center, direction, _stone_seed)
	set_process(true)


func release_gem_cover() -> void:
	is_gem_cover = false
	cover_gem = null
	cover_tier = 0
	_cover_hit_count = 0
	if is_instance_valid(light_node):
		light_node.call("clear")
	# Existing damage remains meaningful after the hidden gem is collected.
	set_process(true)


func get_revealed_tier() -> int:
	if not is_gem_cover or _cover_hit_count == 0:
		return -1
	if _cover_hit_count <= 1 and health > 0.0:
		return 0
	var damage_taken := maxf(max_health - health, 0.0)
	var reveal_span := maxf(max_health * 0.8 - 1.0, 1.0)
	var progression := clampf((damage_taken - 1.0) / reveal_span, 0.0, 1.0)
	# At 16 HP, a red gem shows white / green / blue / yellow / purple / red
	# at hits 1 / 4 / 6 / 9 / 11 / 13. A unit hit cannot skip a color tier.
	return clampi(floori(progression * float(cover_tier)), 0, cover_tier)


func _cover_target_is_active() -> bool:
	if cover_gem == null:
		return false
	var jewel: Object = cover_gem.get_ref()
	if not is_instance_valid(jewel) or jewel.is_queued_for_deletion():
		return false
	return not bool(jewel.get("collected"))


func set_hovered(value: bool) -> void:
	if _hovered == value or destroyed:
		return
	_hovered = value
	set_process(true)


func hit(damage: float, point: Vector3) -> bool:
	if destroyed:
		return true
	if is_gem_cover and not _cover_target_is_active():
		release_gem_cover()
	health = maxf(health - damage, 0.0)
	_record_impact(point, damage)
	_redraw_cracks(1.0 - health / max_health)
	_flash = 1.0
	_impact = minf(0.085 + damage * 0.012, 0.14)
	_impact_time = 0.0
	set_process(true)
	if is_gem_cover:
		_cover_hit_count += 1
		if is_instance_valid(light_node):
			light_node.call("set_cracks", get_visible_crack_segments(), latest_impact_local)
			light_node.call("pulse", get_revealed_tier(), 1.0 - health / max_health, health <= 0.0)
	if health <= 0.0:
		destroyed = true
		visible = false
		collision_layer = 0
		_shape.set_deferred("disabled", true)
		return true
	return false


func _process(delta: float) -> void:
	if is_gem_cover and not _cover_target_is_active():
		release_gem_cover()
	_flash = move_toward(_flash, 0.0, delta * 7.8)
	_hover_amount = move_toward(_hover_amount, 1.0 if _hovered else 0.0, delta * 8.0)
	_impact_time += delta
	_impact = move_toward(_impact, 0.0, delta * 0.34)
	mesh_instance.position = -direction * sin(_impact_time * 42.0) * _impact
	_material.set_shader_parameter("hit_flash", _flash)
	_material.set_shader_parameter("hovered", _hover_amount)
	if _flash <= 0.0 and _impact <= 0.0 and is_equal_approx(_hover_amount, 1.0 if _hovered else 0.0) and not is_gem_cover:
		mesh_instance.position = Vector3.ZERO
		set_process(false)


func get_visible_crack_segments() -> Array[Dictionary]:
	# These are the same exact centerlines and half-widths used by the dark
	# ribbon mesh. The lighting effect adds only its own depth-fighting offset.
	return _crack_segments.duplicate(true)


func _clamp_to_face(point: Vector3) -> Vector3:
	var planar_offset := point - face_center
	planar_offset -= direction * planar_offset.dot(direction)
	var inside_factor := 1.0
	for i in face_points.size():
		var edge_start := face_points[i]
		var edge_end := face_points[(i + 1) % face_points.size()]
		var inward := direction.cross(edge_end - edge_start).normalized()
		var center_distance := inward.dot(face_center - edge_start)
		var point_distance := inward.dot(face_center + planar_offset - edge_start)
		var inset := minf(0.035, center_distance * 0.30)
		if point_distance < inset and center_distance > inset:
			inside_factor = minf(inside_factor, (center_distance - inset) / (center_distance - point_distance))
	return face_center + planar_offset * maxf(inside_factor, 0.0)


func _record_impact(world_point: Vector3, damage: float) -> void:
	impact_count += 1
	# The rendered stone recoils independently of its body. Project through
	# the mesh transform so both rotation and its current recoil are respected.
	latest_impact_local = _clamp_to_face(mesh_instance.to_local(world_point))
	var nearest_index := -1
	var nearest_distance := INF
	for i in _crack_networks.size():
		var origin: Vector3 = _crack_networks[i]["origin"]
		var distance := origin.distance_to(latest_impact_local)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = i
	var reuse_distance := clampf(_face_extent * 0.14, 0.055, 0.13)
	if nearest_index >= 0 and (nearest_distance <= reuse_distance or _crack_networks.size() >= MAX_CRACK_NETWORKS):
		var network: Dictionary = _crack_networks[nearest_index]
		network["hits"] = float(network["hits"]) + maxf(damage, 0.15)
		if nearest_distance > 0.0001:
			_add_crack_connector(latest_impact_local, network["origin"])
	else:
		_crack_networks.append({
			"origin": latest_impact_local,
			"hit_id": impact_count,
			"hits": maxf(damage, 1.0),
			"growth": 0.0,
			"width": 0.0,
			"segments": _build_crack_paths(latest_impact_local),
		})


func _add_crack_connector(origin: Vector3, target: Vector3) -> void:
	var sideways := direction.cross(target - origin).normalized()
	var bend := minf(origin.distance_to(target) * 0.16, 0.026)
	var points := PackedVector3Array([
		origin,
		_clamp_to_face(origin.lerp(target, 0.33) + sideways * bend),
		_clamp_to_face(origin.lerp(target, 0.67) - sideways * bend * 0.6),
		target,
	])
	_crack_connectors.append({"points": points, "hit_id": impact_count, "impact": origin, "width": 0.0})
	# Repeated almost-identical fractional hits deepen existing fractures
	# instead of accumulating an unbounded number of overlapping random fans.
	if _crack_connectors.size() > MAX_CRACK_CONNECTORS:
		_crack_connectors.pop_front()


func _build_crack_paths(origin: Vector3) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	var branch_count := 5
	var edge_offset := _rng.randi_range(0, face_points.size() - 1)
	for branch in branch_count:
		var edge_index := (edge_offset + int(float(branch) / float(branch_count) * face_points.size())) % face_points.size()
		var target := _clamp_to_face(face_points[edge_index].lerp(face_points[(edge_index + 1) % face_points.size()], _rng.randf_range(0.15, 0.70)))
		var previous := origin
		var travel := target - origin
		var sideways := direction.cross(travel).normalized()
		for step in 5:
			var progress := float(step + 1) / 5.0
			var point := origin.lerp(target, progress)
			if step < 4:
				point += sideways * _rng.randf_range(-0.075, 0.075) * sin(progress * PI)
			point = _clamp_to_face(point)
			paths.append({"a": previous, "b": point, "start": float(step) / 5.0, "end": progress, "branch": branch, "weight": 1.0})
			if step == 2:
				var branch_target := _clamp_to_face(point.lerp(face_points[(edge_index + 2) % face_points.size()], 0.43))
				var branch_middle := _clamp_to_face(point.lerp(branch_target, 0.48) + sideways * 0.032)
				paths.append({"a": point, "b": branch_middle, "start": 0.60, "end": 0.78, "branch": branch, "weight": 0.56})
				paths.append({"a": branch_middle, "b": branch_target, "start": 0.78, "end": 0.98, "branch": branch, "weight": 0.40})
			previous = point
	return paths


func _redraw_cracks(damage_ratio: float) -> void:
	_crack_segments.clear()
	for network in _crack_networks:
		var hits: float = network["hits"]
		var growth := maxf(float(network["growth"]), clampf(0.28 + minf(hits, 8.0) * 0.065 + damage_ratio * 0.54, 0.0, 1.0))
		var width := maxf(float(network["width"]), 0.0105 + damage_ratio * 0.014 + minf(maxf(hits - 1.0, 0.0), 6.0) * 0.0007)
		network["growth"] = growth
		network["width"] = width
		var paths: Array = network["segments"]
		for path: Dictionary in paths:
			var branch_growth := growth - float(int(path["branch"]) % 3) * 0.04
			var start: float = path["start"]
			if branch_growth <= start:
				continue
			var a: Vector3 = path["a"]
			var end: Vector3 = path["b"]
			var b := a.lerp(end, clampf((branch_growth - start) / (float(path["end"]) - start), 0.0, 1.0))
			var weight: float = path["weight"]
			_append_visible_crack(a, b, width * weight * (1.0 - start * 0.6), weight, int(network["hit_id"]), network["origin"])
	for connector in _crack_connectors:
		var width := maxf(float(connector["width"]), (0.0105 + damage_ratio * 0.014) * 0.78)
		connector["width"] = width
		var points: PackedVector3Array = connector["points"]
		for i in points.size() - 1:
			_append_visible_crack(points[i], points[i + 1], width, 0.78, int(connector["hit_id"]), connector["impact"])
	if _crack_segments.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in _crack_segments:
		var a: Vector3 = segment["a"] + direction * 0.006
		var b: Vector3 = segment["b"] + direction * 0.006
		var side := direction.cross(b - a).normalized() * float(segment["width"])
		for vertex: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
			surface.set_normal(direction)
			surface.add_vertex(vertex)
	_crack_mesh.mesh = surface.commit()


func _append_visible_crack(a: Vector3, b: Vector3, width: float, weight: float, hit_id: int, impact: Vector3) -> void:
	if a.distance_squared_to(b) <= 0.00000001:
		return
	_crack_segments.append({"a": a, "b": b, "width": width, "weight": weight, "hit_id": hit_id, "impact": impact})


func _average_points(points: PackedVector3Array) -> Vector3:
	var average := Vector3.ZERO
	for point in points:
		average += point
	return average / maxf(float(points.size()), 1.0)
