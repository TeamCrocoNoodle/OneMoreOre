class_name RockChunk
extends StaticBody3D

## hit() returns true on destruction and hides / disables this plate. Its mesh
## remains available to the caller for debris before the caller frees the node.
const STONE_SHADER := preload("res://shaders/stone.gdshader")
const GemLight := preload("res://scripts/gem_light.gd")
const Fracture := preload("res://scripts/rock_fracture.gd")
const CrackOutline := preload("res://scripts/crack_outline.gd")
const CrackWrap := preload("res://scripts/crack_wrap.gd")
const GEM_COVER_HEALTH := 16.0
const MAX_CRACK_NETWORKS := 2

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
var _fracture_cache: Dictionary = {}
var _fracture_cache_mesh: ArrayMesh
var _fracture_source_mesh: ArrayMesh
var _fracture_source_vertices := PackedVector3Array()

var _material: ShaderMaterial
var _shape: CollisionShape3D
var _crack_mesh: MeshInstance3D
var _crack_material: StandardMaterial3D
var _crack_segments: Array[Dictionary] = []
var _surface_crack_segments: Array[Dictionary] = []
var _front_fracture_segments: Array[Dictionary] = []
var _crack_anchors: Dictionary = {}
var _crack_wrap: RefCounted
var _impact_reference := Vector3.ZERO
var _crack_contours: Array[PackedVector3Array] = []
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
	_crack_wrap = CrackWrap.new()
	_crack_wrap.configure(_fracture_source_vertices, gem_socket_center)
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.albedo_color = Color.WHITE
	_crack_material.vertex_color_use_as_albedo = true
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
	if is_instance_valid(_fracture_source_mesh) and _fracture_source_mesh.changed.is_connected(_invalidate_fracture_source):
		_fracture_source_mesh.changed.disconnect(_invalidate_fracture_source)
	_invalidate_fracture_source()
	_fracture_source_mesh = mesh
	mesh.changed.connect(_invalidate_fracture_source)
	var axis_min := INF
	var axis_max := -INF
	for surface_index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		# Socket fitting already reads this geometry at spawn. Keep its exact
		# triangle order on the CPU so destruction need not fetch the mesh again.
		if indices.is_empty():
			_fracture_source_vertices.append_array(vertices)
		else:
			for index in indices:
				_fracture_source_vertices.append(vertices[index])
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


func _invalidate_fracture_source() -> void:
	# A replaced or edited mesh must fall back to reading its current geometry.
	_fracture_source_vertices.clear()
	_fracture_cache.clear()


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
	light_node.call("configure", face_points, face_center, direction, _stone_seed, gem_socket_center, true, _crack_wrap)
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
			light_node.call("set_cracks", get_surface_crack_segments(), latest_impact_local)
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
	# Structural chart used by the bounded fracture partition. The surface
	# version below follows the actual bevels, sides and rear of this solid.
	return _crack_segments.duplicate(true)


func get_surface_crack_segments() -> Array[Dictionary]:
	return _surface_crack_segments.duplicate(true)


func get_fracture_crack_segments() -> Array[Dictionary]:
	# A side-only lethal blow can break before any arm reaches the front.
	# Its original structural chart still supplies a bounded solid partition.
	if _front_fracture_segments.is_empty():
		return get_visible_crack_segments()
	var groups: Dictionary = {}
	for segment in _front_fracture_segments:
		var source_index := int(segment.get("source_index", -1))
		if not groups.has(source_index):
			groups[source_index] = []
		groups[source_index].append(segment)
	var cuts: Array[Dictionary] = []
	for source_index: int in groups:
		var pieces: Array = groups[source_index]
		if source_index >= 0 and source_index < _crack_segments.size() and _is_exact_front_source(_crack_segments[source_index], pieces):
			# At original reach, an unchanged front path is already the exact
			# structural line. Fan triangulation must not introduce rounded
			# intermediate points that turn a straight line into tiny slivers.
			cuts.append(_crack_segments[source_index].duplicate(true))
		else:
			# Side/back strikes and genuinely clipped paths retain their actual
			# transported front portions, including physical crease endpoints.
			for piece: Dictionary in pieces:
				cuts.append(piece.duplicate(true))
	return cuts


func _is_exact_front_source(source: Dictionary, pieces: Array) -> bool:
	var anchor: Dictionary = _crack_anchors.get(int(source["hit_id"]), {})
	if anchor.is_empty():
		return false
	var point: Vector3 = anchor["point"]
	var reference: Vector3 = anchor["reference"]
	if point.distance_squared_to(reference) > 0.0000000001 or absf(direction.dot(point - face_center)) > 0.00001:
		return false
	var a: Vector3 = source["a"]
	var b: Vector3 = source["b"]
	var intervals: Array[Vector2] = []
	for piece: Dictionary in pieces:
		var low := float(piece["source_t0"])
		var high := float(piece["source_t1"])
		if Vector3(piece["a"]).distance_to(a.lerp(b, low)) > 0.00003 or Vector3(piece["b"]).distance_to(a.lerp(b, high)) > 0.00003:
			return false
		intervals.append(Vector2(low, high))
	intervals.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
	var covered := 0.0
	for interval in intervals:
		if interval.x > covered + 0.00001:
			return false
		covered = maxf(covered, interval.y)
	return covered >= 0.99999


func build_fracture_fragments() -> Array[Dictionary]:
	if not destroyed:
		return []
	if _fracture_cache_mesh != mesh_instance.mesh:
		_fracture_cache.clear()
		_fracture_cache_mesh = mesh_instance.mesh
	if _fracture_cache.is_empty():
		var source := _fracture_source_vertices if mesh_instance.mesh == _fracture_source_mesh else PackedVector3Array()
		_fracture_cache = Fracture.build(mesh_instance.mesh, face_points, face_center, direction, get_fracture_crack_segments(), source)
	var fragments: Array[Dictionary] = _fracture_cache["fragments"]
	return fragments


func get_fracture_boundaries() -> Array[Dictionary]:
	if not destroyed:
		return []
	build_fracture_fragments()
	var boundaries: Array[Dictionary] = _fracture_cache["boundaries"]
	return boundaries.duplicate(true)


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
	var contact: Dictionary = _crack_wrap.get_surface_hit(mesh_instance.to_local(world_point))
	latest_impact_local = contact.get("point", _clamp_to_face(mesh_instance.to_local(world_point)))
	_impact_reference = _clamp_to_face(latest_impact_local)
	var surface_nearest := _nearest_surface_crack(latest_impact_local)
	var contact_normal: Vector3 = contact.get("normal", direction)
	var on_front := contact_normal.dot(direction) > 0.9999
	if not on_front:
		# A new side strike gets the same balanced three-arm chart as a front
		# strike. Clamping a side point to the front rim squeezes every arm
		# into one direction even though its true surface has room on both sides.
		_impact_reference = face_center
		if not surface_nearest.is_empty() and float(surface_nearest["distance"]) < 0.04:
			_impact_reference = surface_nearest["reference"]
	_crack_anchors[impact_count] = {"point": latest_impact_local, "reference": _impact_reference}
	var nearest_index := -1
	var nearest_distance := INF
	for i in _crack_networks.size():
		var origin: Vector3 = _crack_networks[i]["origin"]
		var distance := origin.distance_to(_impact_reference)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = i
	var nearest_crack := _nearest_visible_crack(_impact_reference)
	var reuse_distance := clampf(_face_extent * 0.20, 0.075, 0.16)
	var close_to_crack := not surface_nearest.is_empty() and float(surface_nearest["distance"]) <= reuse_distance
	var same_surface := on_front
	if nearest_index >= 0:
		var anchor: Dictionary = _crack_anchors.get(int(_crack_networks[nearest_index]["hit_id"]), {})
		same_surface = latest_impact_local.distance_to(anchor.get("point", latest_impact_local)) <= reuse_distance
	if nearest_index >= 0 and (close_to_crack or (same_surface and nearest_distance <= reuse_distance) or _crack_networks.size() >= MAX_CRACK_NETWORKS):
		# Deepen the struck network where possible. Hits on an added connector
		# retain that connector's own contact provenance and deepen it in place.
		var struck_id := int(surface_nearest.get("hit_id", nearest_crack.get("hit_id", -1)))
		for i in _crack_networks.size():
			if int(_crack_networks[i]["hit_id"]) == struck_id:
				nearest_index = i
				break
		var network: Dictionary = _crack_networks[nearest_index]
		network["hits"] = float(network["hits"]) + maxf(damage, 0.15)
		for connector in _crack_connectors:
			if int(connector["hit_id"]) == struck_id:
				connector["hits"] = float(connector.get("hits", 0.0)) + maxf(damage, 0.15)
		# Coverage is measured against the actual finite ribbon, including its
		# endpoint range. A nearby but uncovered contact still leaves a new mark.
		if not bool(surface_nearest.get("covered", false)):
			var target: Vector3 = nearest_crack.get("point", network["origin"])
			if target.distance_squared_to(_impact_reference) <= 0.00000001:
				# A new side/back contact can share the front chart coordinates
				# of an old crack while remaining uncovered on the actual solid.
				target = _clamp_to_face(_impact_reference.lerp(face_center, 0.30))
				if target.distance_squared_to(_impact_reference) <= 0.00000001:
					target = face_center.lerp(face_points[0], 0.22)
			_add_crack_connector(_impact_reference, target)
	else:
		_crack_networks.append({
			"origin": _impact_reference,
			"hit_id": impact_count,
			"hits": maxf(damage, 1.0),
			"growth": 0.0,
			"width": 0.0,
			"segments": _build_crack_paths(_impact_reference),
		})


func _nearest_surface_crack(point: Vector3) -> Dictionary:
	var closest: Dictionary = {}
	var distance := INF
	var covered := false
	for segment in _surface_crack_segments:
		if _point_in_crack_ribbon(point, segment):
			covered = true
		if not bool(segment.get("has_centerline", true)):
			continue
		var a: Vector3 = segment["a"]
		var edge: Vector3 = segment["b"] - a
		var t := clampf((point - a).dot(edge) / maxf(edge.length_squared(), 0.00000001), 0.0, 1.0)
		var candidate := a + edge * t
		var value := point.distance_to(candidate)
		if value < distance:
			distance = value
			var ref_a: Vector3 = segment.get("reference_a", a)
			var ref_b: Vector3 = segment.get("reference_b", segment["b"])
			closest = {"point": candidate, "distance": value, "reference": ref_a.lerp(ref_b, t), "hit_id": int(segment["hit_id"])}
	if not closest.is_empty():
		closest["covered"] = covered
	return closest


func _nearest_visible_crack(point: Vector3) -> Dictionary:
	var closest: Dictionary = {}
	var nearest_distance := INF
	var covered := false
	for segment in _crack_segments:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var edge := b - a
		var t := (point - a).dot(edge) / maxf(edge.length_squared(), 0.00000001)
		var target := a + edge * clampf(t, 0.0, 1.0)
		var distance := point.distance_to(target)
		if _point_in_crack_ribbon(point, segment):
			covered = true
		if distance < nearest_distance:
			nearest_distance = distance
			closest = {"point": target, "distance": distance, "hit_id": int(segment["hit_id"])}
	if not closest.is_empty():
		closest["covered"] = covered
	return closest


func _point_in_crack_ribbon(point: Vector3, segment: Dictionary) -> bool:
	# A miter extends beyond the centerline's endpoint, so a distance-to-line
	# test with a finite t range would add cracks on already opened corners.
	var vertices: PackedVector3Array
	if segment.has("polygon"):
		vertices = segment["polygon"]
	else:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var side_a: Vector3 = segment["side_a"]
		var side_b: Vector3 = segment["side_b"]
		vertices = PackedVector3Array([a - side_a, a + side_a, b + side_b, b - side_b])
	var normal: Vector3 = segment.get("normal", direction)
	if vertices.is_empty() or absf(normal.dot(point - vertices[0])) > 0.002:
		return false
	var positive := false
	var negative := false
	for i in vertices.size():
		var edge: Vector3 = vertices[(i + 1) % vertices.size()] - vertices[i]
		var signed_distance := normal.dot(edge.cross(point - vertices[i]))
		var tolerance := edge.length() * 0.00001
		positive = positive or signed_distance > tolerance
		negative = negative or signed_distance < -tolerance
		if positive and negative:
			return false
	return true


func _add_crack_connector(origin: Vector3, target: Vector3) -> void:
	if origin.distance_squared_to(target) <= 0.00000001:
		return
	var points := PackedVector3Array([origin, target])
	_crack_connectors.append({"points": points, "hit_id": impact_count, "impact": latest_impact_local, "width": 0.0, "hits": 1.0})
	# One shortest connection per uncovered contact, with no old lines removed.
	# The 16-hit cover therefore has at most 18 major + 14 connector segments.


func _build_crack_paths(origin: Vector3) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	var branch_count := 3
	var step_count := 3
	var edge_offset := _rng.randi_range(0, face_points.size() - 1)
	var reaches := [0.0, 0.20, 0.48, 1.0]
	var edge_fractions := [0.0, 0.50, 0.25]
	var branch_weights := [1.0, 0.84, 0.58]
	for branch in branch_count:
		# Two stronger arms form the broken main seam; a smaller third arm
		# branches off it. Keep the same bounded three-arm topology.
		var edge_index := (edge_offset + int(float(edge_fractions[branch]) * face_points.size())) % face_points.size()
		var target := _clamp_to_face(face_points[edge_index].lerp(face_points[(edge_index + 1) % face_points.size()], _rng.randf_range(0.15, 0.70)))
		var previous := origin
		var travel := target - origin
		var sideways := direction.cross(travel).normalized()
		var jog := minf(travel.length() * 0.17, _face_extent * 0.19) * (-1.0 if _rng.randf() < 0.5 else 1.0)
		var width_profile := [1.0, _rng.randf_range(1.05, 1.28), _rng.randf_range(0.70, 0.90), 0.50]
		for step in step_count:
			var progress: float = reaches[step + 1]
			var point := origin.lerp(target, progress)
			if step < step_count - 1:
				point += sideways * jog * (0.78 if step == 0 else -0.50)
			point = _clamp_to_face(point)
			paths.append({"a": previous, "b": point, "start": reaches[step], "end": progress, "branch": branch, "weight": branch_weights[branch], "profile_a": width_profile[step], "profile_b": width_profile[step + 1]})
			previous = point
	return paths


func _redraw_cracks(damage_ratio: float) -> void:
	_crack_segments.clear()
	for network in _crack_networks:
		var hits: float = network["hits"]
		var growth := maxf(float(network["growth"]), clampf(0.25 + minf(hits, 6.0) * 0.055 + damage_ratio * 0.24, 0.0, 0.82))
		var width := maxf(float(network["width"]), _crack_base_width(damage_ratio) + minf(maxf(hits - 1.0, 0.0), 6.0) * 0.0008)
		network["growth"] = growth
		network["width"] = width
		var paths: Array = network["segments"]
		for path: Dictionary in paths:
			var branch_growth := growth - float(int(path["branch"]) % 3) * 0.025
			var start: float = path["start"]
			if branch_growth <= start:
				continue
			var a: Vector3 = path["a"]
			var end: Vector3 = path["b"]
			var fraction := clampf((branch_growth - start) / (float(path["end"]) - start), 0.0, 1.0)
			var b := a.lerp(end, fraction)
			var weight: float = path["weight"]
			var end_progress := lerpf(start, float(path["end"]), fraction)
			var width_a := width * weight * float(path["profile_a"]) * sqrt(maxf(1.0 - start / branch_growth, 0.0))
			var width_b := width * weight * lerpf(float(path["profile_a"]), float(path["profile_b"]), fraction) * sqrt(maxf(1.0 - end_progress / branch_growth, 0.0))
			_append_visible_crack(a, b, width_a, width_b, weight, int(network["hit_id"]), network["origin"])
	for connector in _crack_connectors:
		var width := maxf(float(connector["width"]), (_crack_base_width(damage_ratio) + minf(float(connector.get("hits", 1.0)), 6.0) * 0.0005) * 0.64)
		connector["width"] = width
		var points: PackedVector3Array = connector["points"]
		for i in points.size() - 1:
			_append_visible_crack(points[i], points[i + 1], width * 0.16, width, 0.64, int(connector["hit_id"]), connector["impact"])
	_join_crack_edges()
	# Transport the original-sized paths onto the struck surface. Surface
	# support must not lengthen the established cracks or stretch their bends.
	_surface_crack_segments = _crack_wrap.wrap(_crack_segments, _crack_anchors, direction)
	# Keep the exact shared mesh-edge anchors in the fracture graph. Merging
	# collinear rendering patches is only a draw optimization; dropping those
	# anchors can change intersection welding in densely damaged partitions.
	_front_fracture_segments.clear()
	for segment in _surface_crack_segments:
		var normal: Vector3 = segment["normal"]
		if bool(segment.get("has_centerline", true)) and normal.dot(direction) > 0.9999 and absf(direction.dot(Vector3(segment["a"]) - face_center)) < 0.0001:
			_front_fracture_segments.append(segment)
	_surface_crack_segments = _crack_wrap.coalesce(_surface_crack_segments)
	# Fatal damage still supplies the complete final crack data to fracture and
	# light provenance. The stone is hidden immediately, so its dark ribbon mesh
	# would be uploaded and discarded before a single rendered frame could use it.
	if health <= 0.0 or _crack_segments.is_empty():
		return
	_draw_crack_surface()


func _draw_crack_surface() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_crack_contours.clear()
	if _surface_crack_segments.is_empty():
		_draw_crack_patch(surface, _crack_segments, direction)
	else:
		var patches: Dictionary = {}
		for segment in _surface_crack_segments:
			var face_id: int = segment["face_id"]
			if not patches.has(face_id):
				patches[face_id] = []
			patches[face_id].append(segment)
		for face_id: int in patches:
			var segments: Array[Dictionary] = []
			segments.assign(patches[face_id])
			_draw_crack_patch(surface, segments, segments[0]["normal"], face_id)
	_crack_mesh.mesh = surface.commit()


func _draw_crack_patch(surface: SurfaceTool, segments: Array[Dictionary], normal: Vector3, face_id: int = -1) -> void:
	var contours := CrackOutline.build(segments, normal)
	_crack_contours.append_array(contours)
	var floor_color := Color(0.055, 0.067, 0.075)
	var wall_clips: Array[Dictionary] = []
	for segment in segments:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var side_a: Vector3 = segment["side_a"]
		var side_b: Vector3 = segment["side_b"]
		# Identical opaque floor triangles form the exact ribbon union. This
		# preserves stone islands and disconnected cracks without filling holes.
		var polygon: PackedVector3Array = segment.get("polygon", PackedVector3Array([a - side_a, a + side_a, b + side_b, b - side_b]))
		var offsets: PackedVector3Array = segment.get("polygon_offsets", PackedVector3Array())
		var bounds := AABB(polygon[0], Vector3.ZERO)
		var center := _average_points(polygon)
		var planes: Array[Plane] = []
		for i in polygon.size():
			bounds = bounds.expand(polygon[i])
			var edge := polygon[(i + 1) % polygon.size()] - polygon[i]
			if edge.length_squared() < 0.0000000001:
				continue
			var inward := normal.cross(edge).normalized()
			if inward.dot(center - polygon[i]) < 0.0:
				inward = -inward
			planes.append(Plane(inward, polygon[i]))
		wall_clips.append({"segment": segment, "bounds": bounds.grow(0.00002), "planes": planes})
		for i in range(1, polygon.size() - 1):
			for corner: int in [0, i, i + 1]:
				var offset := offsets[corner] if offsets.size() == polygon.size() else normal
				surface.set_normal(normal)
				surface.set_color(floor_color)
				surface.add_vertex(polygon[corner] + offset * 0.006)
	for full_contour in contours:
		var contour := _wall_contour(full_contour, normal, face_id)
		var inner := PackedVector3Array()
		var colors := PackedColorArray()
		var seams := PackedByteArray()
		for i in contour.size():
			var next := (i + 1) % contour.size()
			seams.append(1 if face_id >= 0 and bool(_crack_wrap.is_surface_edge(contour[i], contour[next], face_id)) else 0)
		for i in contour.size():
			var point := contour[i]
			var previous := contour[(i - 1 + contour.size()) % contour.size()]
			var next := contour[(i + 1) % contour.size()]
			var before := normal.cross(point - previous).normalized()
			var after := normal.cross(next - point).normalized()
			var before_seam := seams[(i - 1 + contour.size()) % contour.size()] != 0
			var after_seam := seams[i] != 0
			var inward := (before + after).normalized()
			if before_seam and not after_seam:
				inward = after
			elif after_seam and not before_seam:
				inward = before
			# A single inner corner and color are shared by the two neighboring
			# walls, including three-way junctions and corners around stone islands.
			var clearance := _nearest_crack_center_distance(point, segments)
			var shade_direction := inward
			var inset := minf(clearance * 0.70 / maxf(inward.dot(after), 0.25), clearance * 1.45)
			if before_seam != after_seam:
				# Both facets use the same open interval at a physical crease.
				# Its 35% bank inset is the usual 70% of the half width, and
				# cannot acquire a different endpoint on the neighboring face.
				var seam_target := previous if before_seam else next
				var along := (seam_target - point).normalized()
				inset = point.distance_to(seam_target) * 0.35
				inward = along
			var candidate := point + inward * inset
			for attempt in 6:
				if inset <= 0.000001 or _point_in_crack_union(candidate, segments):
					break
				inset *= 0.5
				candidate = point + inward * inset
			if not _point_in_crack_union(candidate, segments):
				candidate = point
			inner.append(candidate)
			var tint := stone_color * (0.84 + shade_direction.dot(Vector3(-0.45, 0.80, 0.40).normalized()) * 0.23)
			tint.a = 1.0
			colors.append(tint)
		for i in contour.size():
			var next := (i + 1) % contour.size()
			# A fold is not a crack wall: the same opening continues on the
			# neighboring face. Never draw a bright crossbar across that seam.
			if seams[i] != 0:
				continue
			_add_crack_wall_triangle(surface, PackedVector3Array([contour[i], inner[i], inner[next]]), PackedColorArray([colors[i], colors[i] * 0.74, colors[next] * 0.74]), segments, wall_clips, normal)
			_add_crack_wall_triangle(surface, PackedVector3Array([contour[i], inner[next], contour[next]]), PackedColorArray([colors[i], colors[next] * 0.74, colors[next]]), segments, wall_clips, normal)


func _wall_contour(source: PackedVector3Array, normal: Vector3, face_id: int) -> PackedVector3Array:
	# Splitting one straight bank into mesh/source patches must not recalculate
	# its wall width at each artificial knot. Retain real bends and folds only.
	var contour := source.duplicate()
	var changed := true
	while changed and contour.size() > 3:
		changed = false
		for i in contour.size():
			var point := contour[i]
			if face_id >= 0 and _crack_wrap.surface_offset(point, face_id).distance_squared_to(normal) > 0.00000001:
				continue
			var previous := contour[(i - 1 + contour.size()) % contour.size()]
			var next := contour[(i + 1) % contour.size()]
			var line := next - previous
			if line.length_squared() < 0.0000000001:
				continue
			var t := (point - previous).dot(line) / line.length_squared()
			if t > 0.0 and t < 1.0 and point.distance_squared_to(previous + line * t) <= 0.000000000225:
				contour.remove_at(i)
				changed = true
				break
	return contour


func _add_crack_wall_triangle(surface: SurfaceTool, vertices: PackedVector3Array, colors: PackedColorArray, segments: Array[Dictionary], wall_clips: Array[Dictionary], normal: Vector3) -> void:
	if (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).length_squared() < 0.00000000000001:
		return
	# Shared union corners keep the wall band open through bends and Y joins.
	# Most triangles lie in one convex patch and need no clipping at all.
	var bounds := AABB(vertices[0], Vector3.ZERO).expand(vertices[1]).expand(vertices[2]).grow(0.00002)
	var candidates: Array[Dictionary] = []
	for clip in wall_clips:
		if not bounds.intersects(clip["bounds"]):
			continue
		candidates.append(clip)
		var segment: Dictionary = clip["segment"]
		if _point_in_crack_ribbon(vertices[0], segment) and _point_in_crack_ribbon(vertices[1], segment) and _point_in_crack_ribbon(vertices[2], segment):
			_emit_crack_wall_polygon(surface, vertices, colors, segments, normal)
			return
	# At reentrant joins, trim the wall to the opening instead of shrinking
	# its shared inner corner to zero. Colors travel with the original wall;
	# overlapping opaque clips therefore have the same interpolated shading.
	for clip in candidates:
		var clipped := vertices.duplicate()
		var tints := colors.duplicate()
		for plane: Plane in clip["planes"]:
			var next_vertices := PackedVector3Array()
			var next_colors := PackedColorArray()
			for j in clipped.size():
				var k := (j + 1) % clipped.size()
				var from := clipped[j]
				var to := clipped[k]
				var d_from := plane.distance_to(from)
				var d_to := plane.distance_to(to)
				var inside_from := d_from >= -0.0000001
				var inside_to := d_to >= -0.0000001
				if inside_from:
					next_vertices.append(from)
					next_colors.append(tints[j])
				if inside_from != inside_to:
					var t := clampf(d_from / (d_from - d_to), 0.0, 1.0)
					next_vertices.append(from.lerp(to, t))
					next_colors.append(tints[j].lerp(tints[k], t))
			clipped = next_vertices
			tints = next_colors
			if clipped.size() < 3:
				break
		if clipped.size() >= 3:
			_emit_crack_wall_polygon(surface, clipped, tints, segments, normal)


func _emit_crack_wall_polygon(surface: SurfaceTool, vertices: PackedVector3Array, colors: PackedColorArray, segments: Array[Dictionary], normal: Vector3) -> void:
	var lifted := PackedVector3Array()
	for point in vertices:
		lifted.append(point + _crack_surface_offset(point, segments, normal) * 0.0062)
	for i in range(1, vertices.size() - 1):
		if (vertices[i] - vertices[0]).cross(vertices[i + 1] - vertices[0]).length_squared() < 0.00000000000001:
			continue
		for corner: int in [0, i, i + 1]:
			var tint := colors[corner]
			tint.a = 1.0
			surface.set_normal(normal)
			surface.set_color(tint)
			surface.add_vertex(lifted[corner])


func _crack_surface_offset(point: Vector3, segments: Array[Dictionary], normal: Vector3) -> Vector3:
	if not segments.is_empty() and segments[0].has("face_id"):
		return _crack_wrap.surface_offset(point, int(segments[0]["face_id"]))
	for segment in segments:
		var polygon: PackedVector3Array = segment.get("polygon", PackedVector3Array())
		var offsets: PackedVector3Array = segment.get("polygon_offsets", PackedVector3Array())
		if polygon.size() != offsets.size():
			continue
		for i in polygon.size():
			var next := (i + 1) % polygon.size()
			var edge := polygon[next] - polygon[i]
			var t := clampf((point - polygon[i]).dot(edge) / maxf(edge.length_squared(), 0.00000001), 0.0, 1.0)
			if point.distance_squared_to(polygon[i] + edge * t) < 0.00000001:
				return offsets[i].lerp(offsets[next], t)
	return normal


func _nearest_crack_center_distance(point: Vector3, segments: Array[Dictionary] = []) -> float:
	var closest := INF
	var junction_distance := INF
	for segment in (_crack_segments if segments.is_empty() else segments):
		if bool(segment.get("junction", false)):
			junction_distance = minf(junction_distance, point.distance_squared_to(segment["junction_center"]))
			continue
		# Bank-only clips have a synthetic representative a/b. The actual
		# transported source axis preserves the same wall width on every facet.
		var a: Vector3 = segment.get("ribbon_a", segment["a"])
		var edge: Vector3 = Vector3(segment.get("ribbon_b", segment["b"])) - a
		var t := clampf((point - a).dot(edge) / maxf(edge.length_squared(), 0.00000001), 0.0, 1.0)
		closest = minf(closest, point.distance_squared_to(a + edge * t))
	return sqrt(junction_distance if closest == INF else closest)


func _point_in_crack_union(point: Vector3, segments: Array[Dictionary] = []) -> bool:
	for segment in (_crack_segments if segments.is_empty() else segments):
		if _point_in_crack_ribbon(point, segment):
			return true
	return false


func _crack_base_width(damage_ratio: float) -> float:
	return clampf(_face_extent * 0.038, 0.018, 0.032) + damage_ratio * 0.018


func _append_visible_crack(a: Vector3, b: Vector3, width_a: float, width_b: float, weight: float, hit_id: int, impact: Vector3) -> void:
	if a.distance_squared_to(b) <= 0.00000001:
		return
	var side := direction.cross(b - a).normalized()
	var anchor: Dictionary = _crack_anchors.get(hit_id, {})
	_crack_segments.append({"a": a, "b": b, "width": maxf(width_a, width_b), "width_a": width_a, "width_b": width_b, "side_a": side * width_a, "side_b": side * width_b, "weight": weight, "hit_id": hit_id, "impact": anchor.get("point", impact)})


func _join_crack_edges() -> void:
	var endpoints: Dictionary = {}
	for i in _crack_segments.size():
		for end_key: String in ["a", "b"]:
			var point: Vector3 = _crack_segments[i][end_key]
			var key := Vector3i(roundi(point.x * 100000.0), roundi(point.y * 100000.0), roundi(point.z * 100000.0))
			if not endpoints.has(key):
				endpoints[key] = []
			endpoints[key].append({"index": i, "end": end_key})
	for entries: Array in endpoints.values():
		if entries.size() != 2 or entries[0]["end"] == entries[1]["end"]:
			continue
		var first: Dictionary = _crack_segments[int(entries[0]["index"])]
		var second: Dictionary = _crack_segments[int(entries[1]["index"])]
		if first["hit_id"] != second["hit_id"]:
			continue
		var first_side := direction.cross(Vector3(first["b"]) - Vector3(first["a"])).normalized()
		var second_side := direction.cross(Vector3(second["b"]) - Vector3(second["a"])).normalized()
		var miter := (first_side + second_side).normalized()
		var factor := 1.0 / maxf(miter.dot(first_side), 0.65)
		for entry: Dictionary in entries:
			var segment: Dictionary = _crack_segments[int(entry["index"])]
			var end_key: String = entry["end"]
			segment["side_" + end_key] = miter * float(segment["width_" + end_key]) * factor
	# Clamp both banks symmetrically to the real face so a broad root cannot
	# float beyond the rock silhouette when the contact is close to an edge.
	for segment in _crack_segments:
		for end_key: String in ["a", "b"]:
			var point: Vector3 = segment[end_key]
			var side: Vector3 = segment["side_" + end_key]
			var fraction := 1.0
			for i in face_points.size():
				var inward := direction.cross(face_points[(i + 1) % face_points.size()] - face_points[i]).normalized()
				var projected := absf(inward.dot(side))
				if projected > 0.000001:
					fraction = minf(fraction, maxf(inward.dot(point - face_points[i]) - 0.002, 0.0) / projected)
			segment["side_" + end_key] = side * fraction
			segment["width_" + end_key] = float(segment["width_" + end_key]) * fraction
		segment["width"] = maxf(float(segment["width_a"]), float(segment["width_b"]))


func _add_crack_strip(surface: SurfaceTool, outer_a: Vector3, outer_b: Vector3, inner_a: Vector3, inner_b: Vector3, outer_color: Color, inner_color: Color) -> void:
	var vertices := [outer_a, inner_a, inner_b, outer_a, inner_b, outer_b]
	for i in 6:
		surface.set_normal(direction)
		var tint := inner_color if i in [1, 2, 4] else outer_color
		tint.a = 1.0
		surface.set_color(tint)
		surface.add_vertex(vertices[i])


func _average_points(points: PackedVector3Array) -> Vector3:
	var average := Vector3.ZERO
	for point in points:
		average += point
	return average / maxf(float(points.size()), 1.0)
