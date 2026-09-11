extends SceneTree
## The polished crystal model must remain a solid, selectable game object.

const Gem = preload("res://scripts/gem.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")

var fixture := Node3D.new()
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()
	create_timer(25.0).timeout.connect(func():
		push_error("GEM_MODEL_TEST_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.add_child(fixture)
	var jewels: Array[Gem] = []
	for tier in range(6):
		jewels.append(_make_gem(tier, Vector3(tier * 2.0, 0.0, 0.0)))
	await _frames(3)
	for tier in range(jewels.size()):
		_validate_model(jewels[tier], "tier %d" % tier)
		_check(jewels[tier].light_tier == tier and jewels[tier].grade == (Gem.SPECIAL if tier == 5 else Gem.COMMON), "All six model choices retain the existing common/special and light-tier meaning")
	await _validate_independent_instances(jewels)
	await _validate_reconfigure()
	await _validate_lifecycle()
	fixture.queue_free()
	await _frames(4)
	print("GEM_MODEL_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_gem(tier: int, position: Vector3) -> Gem:
	var jewel := Gem.new()
	jewel.configure(Gem.SPECIAL if tier == 5 else Gem.COMMON, tier)
	jewel.position = position
	fixture.add_child(jewel)
	return jewel


func _validate_model(jewel: Gem, label: String) -> void:
	_check(jewel.facets != null and jewel.facets.mesh != null and jewel.facets.mesh.get_surface_count() > 0, label + ": the game exposes actual crystal geometry")
	if jewel.facets == null or jewel.facets.mesh == null:
		return
	var mesh: Mesh = jewel.facets.mesh
	var edge_counts: Dictionary = {}
	var adjacency: Dictionary = {}
	var valid_triangles := true
	var outward_faces := true
	var measured_radius := 0.0
	var points := PackedVector3Array()
	var local_bounds := AABB(Vector3.ZERO, Vector3.ZERO)
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		valid_triangles = valid_triangles and count >= 3 and count % 3 == 0 and normals.size() == vertices.size()
		for vertex in vertices:
			var body_point := jewel.to_local(jewel.facets.to_global(vertex))
			points.append(body_point)
			measured_radius = maxf(measured_radius, body_point.length())
			local_bounds = local_bounds.expand(body_point)
		for offset in range(0, count, 3):
			var triangle: Array[Vector3] = []
			var triangle_normals: Array[Vector3] = []
			for corner in range(3):
				var index: int = indices[offset + corner] if not indices.is_empty() else offset + corner
				triangle.append(vertices[index])
				triangle_normals.append(normals[index])
			var cross := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
			valid_triangles = valid_triangles and cross.is_finite() and cross.length_squared() > 0.00000000000001
			for corner in range(3):
				var point := triangle[corner]
				var normal := triangle_normals[corner]
				valid_triangles = valid_triangles and point.is_finite() and normal.is_finite() and absf(normal.length() - 1.0) < 0.001 and cross.normalized().dot(normal) < -0.995
				outward_faces = outward_faces and normal.dot((triangle[0] + triangle[1] + triangle[2]) / 3.0) > -0.00001
				var a := _point_key(point)
				var b := _point_key(triangle[(corner + 1) % 3])
				var edge := a + ":" + b if a < b else b + ":" + a
				edge_counts[edge] = int(edge_counts.get(edge, 0)) + 1
				if not adjacency.has(a):
					adjacency[a] = []
				if not adjacency.has(b):
					adjacency[b] = []
				adjacency[a].append(b)
				adjacency[b].append(a)
	var closed := true
	var open_edges: Array = []
	for count in edge_counts.values():
		closed = closed and int(count) == 2
	if not closed:
		for edge in edge_counts:
			if edge_counts[edge] != 2 and open_edges.size() < 10:
				open_edges.append([edge, edge_counts[edge]])
		print("GEM_OPEN_EDGES ", label, " ", open_edges, " connected=", _connected(adjacency))
	_check(valid_triangles and outward_faces, label + ": every facet is finite, nondegenerate, outward facing and correctly wound for back-face culling")
	_check(closed and _connected(adjacency), label + ": the crystal is one closed connected solid without detached satellite geometry or open seams")
	_check(points.size() > 0 and measured_radius <= jewel.bound_radius + 0.0001 and absf(measured_radius - jewel.bound_radius) < 0.0001, label + ": the declared bound measures the complete actual model")
	_check(jewel.bound_radius > 0.0 and jewel.bound_radius <= (0.5201 if jewel.grade == Gem.SPECIAL else 0.4001), label + ": full-size crystal fits the established gameplay and showcase size budget")
	_check(local_bounds.size.y > maxf(local_bounds.size.x, local_bounds.size.z) * 1.1, label + ": the new crystal retains an elongated upright silhouette")
	var colliders: Array = jewel.get("_colliders")
	var valid_colliders := not colliders.is_empty()
	for collider in colliders:
		valid_colliders = valid_colliders and collider is CollisionShape3D and collider.shape is ConvexPolygonShape3D and collider.get_parent() == jewel and not collider.disabled
	_check(valid_colliders and _count_nodes(jewel, "CollisionShape3D") == colliders.size(), label + ": the active convex selection shapes belong to this gem with no stale colliders")
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = 2
	var hulls := _collider_hulls(jewel, colliders)
	var exact_containment := true
	var contained := true
	var failed_points: Array = []
	for point in points:
		# Exact boundary containment uses tetrahedra from the actual collider.
		# Physics queries run 0.1% inward: its point solver rejects some exact
		# hull vertices even when they are literally collider input points.
		exact_containment = exact_containment and _inside_hulls(point, hulls)
		query.position = jewel.to_global(point * 0.999)
		var hits := fixture.get_world_3d().direct_space_state.intersect_point(query, 16)
		var found := false
		for hit in hits:
			found = found or hit.collider == jewel
		contained = contained and found
		if not found and failed_points.size() < 3:
			var nearest := INF
			for collider in colliders:
				for hull_point in collider.shape.points:
					nearest = minf(nearest, point.distance_to(hull_point))
			var inward_results: Array[bool] = []
			for factor in [0.999, 0.99, 0.95, 0.8]:
				query.position = jewel.to_global(point * factor)
				inward_results.append(not fixture.get_world_3d().direct_space_state.intersect_point(query, 16).is_empty())
			failed_points.append({"point": point, "nearest_collider_vertex": nearest, "inward": inward_results})
	if not contained:
		print("GEM_HULL_MISSES ", label, " ", failed_points)
	_check(exact_containment, label + ": the actual collider's convex volume contains every exact visible model vertex")
	_check(contained, label + ": physics queries recognize the crystal immediately inside every visible boundary vertex")
	var ray := PhysicsRayQueryParameters3D.create(jewel.global_position + Vector3.BACK * 2.0, jewel.global_position, 2)
	var selection := fixture.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not selection.is_empty() and selection.collider == jewel, label + ": aiming at the gem origin selects the real collectible body")
	_validate_material(jewel, label)


func _validate_material(jewel: Gem, label: String) -> void:
	var material: Material = jewel.facets.material_override
	_check(material is ShaderMaterial, label + ": the crystal uses its dedicated faceted material")
	if not material is ShaderMaterial:
		return
	var code: String = material.shader.code
	var comments := RegEx.new()
	comments.compile("(?s)/\\*.*?\\*/|//[^\\n]*")
	code = comments.sub(code, "", true)
	var overrides := RegEx.new()
	overrides.compile("\\b(ALPHA|ALPHA_SCISSOR_THRESHOLD|ALPHA_HASH_SCALE|DEPTH)\\s*[+*/-]?=")
	_check(overrides.search(code) == null and not code.contains("depth_test_disabled") and not code.contains("depth_draw_always") and not code.contains("depth_prepass_alpha"), label + ": internal reflections retain opaque depth-tested rendering without alpha or depth overrides")
	_check(code.contains("cull_back"), label + ": opaque crystal faces use back-face culling")
	jewel.set_hovered(true)
	_check(is_equal_approx(_hover(jewel), 1.0), label + ": an exposed collectible accepts its hover highlight")
	jewel.set_hovered(false)
	_check(is_zero_approx(_hover(jewel)), label + ": leaving an exposed gem clears its hover highlight")


func _validate_independent_instances(originals: Array[Gem]) -> void:
	for tier in range(6):
		var original := originals[tier]
		var another := _make_gem(tier, Vector3(tier * 2.0, 3.0, 0.0))
		await _frames(2)
		_check(original.facets.mesh.get_faces() == another.facets.mesh.get_faces() and original.bound_radius == another.bound_radius, "Separately created copies of a gem variant reproduce exactly the same model and size")
		var original_colliders: Array = original.get("_colliders")
		var other_colliders: Array = another.get("_colliders")
		var separate := original_colliders.size() == other_colliders.size()
		for i in range(mini(original_colliders.size(), other_colliders.size())):
			separate = separate and original_colliders[i] != other_colliders[i] and original_colliders[i].shape != other_colliders[i].shape
		_check(separate and original.facets.material_override != another.facets.material_override, "Independent gems own independent material and collider state")
		original.set_hovered(true)
		_check(is_equal_approx(_hover(original), 1.0) and is_zero_approx(_hover(another)), "Highlighting one gem cannot highlight another instance of the same variant")
		original.set_hovered(false)
		another.queue_free()
	await _frames(3)


func _validate_reconfigure() -> void:
	var jewel := _make_gem(0, Vector3(-3.0, 0.0, 0.0))
	await _frames(2)
	for tier in [5, 2, 4, 1, 0, 3]:
		var old_nodes: Array[WeakRef] = [weakref(jewel.facets)]
		for collider in jewel.get("_colliders"):
			old_nodes.append(weakref(collider))
		jewel.configure(Gem.SPECIAL if tier == 5 else Gem.COMMON, tier)
		await _frames(3)
		var freed := true
		for previous in old_nodes:
			freed = freed and previous.get_ref() == null
		_check(freed and _count_nodes(jewel, "MeshInstance3D") == 1 and _count_nodes(jewel, "CollisionShape3D") == jewel.get("_colliders").size(), "Reconfiguring an existing gem removes every old visual and collision shape")
		_check(jewel.light_tier == tier and not jewel.collected and not jewel.is_embedded and not jewel.is_emerging, "Reconfiguration restores the requested free gem state and tier")
		_validate_model(jewel, "reconfigured tier %d" % tier)
	jewel.queue_free()
	await _frames(2)


func _validate_lifecycle() -> void:
	var host := Chunk.new()
	fixture.add_child(host)
	host.configure(Geometry.build_layer(2.6, 0, 4821)[0], 0)
	host.position += Vector3(0.0, 7.0, 0.0)
	var jewel := _make_gem(5, Vector3(0.0, 7.0, 0.0))
	_check(host.contain_gem(jewel), "The polished model can be fitted into a real owning stone")
	jewel.set_hovered(true)
	_check(jewel.is_embedded and not jewel.visible and jewel.collision_layer == 0 and is_zero_approx(_hover(jewel)), "Embedding hides the model and suppresses selection and hover material state")
	_check(not jewel.begin_collection() and not jewel.release_from_chunk(fixture, Vector3.ZERO), "A living owner prevents both premature collection and release")
	host.hit(host.health, host.mesh_instance.to_global(host.face_center))
	var before := jewel.global_transform
	_check(jewel.release_from_chunk(fixture, Vector3(0.0, 7.0, 2.0)), "Destroying the owner permits outward emergence")
	_check(jewel.global_transform.is_equal_approx(before), "Beginning emergence preserves the fitted model's exact world placement")
	jewel.set_hovered(true)
	_check(jewel.is_emerging and jewel.visible and jewel.collision_layer == 0 and is_zero_approx(_hover(jewel)), "Emerging crystal remains unselectable and without hover highlight")
	var active_tween: Tween = jewel.get("_reveal_tween")
	_check(jewel.begin_collection() and jewel.collected and jewel.is_emerging and jewel.get("_reveal_tween") == active_tween, "The gem is awarded immediately while its existing emergence tween continues")
	_check(not jewel.begin_collection() and jewel.collision_layer == 0, "A second collection request during emergence cannot award or reactivate the gem")
	host.queue_free()
	await _frames(2)
	_check(is_instance_valid(jewel) and jewel.get_parent() == fixture and jewel.is_emerging and jewel.collected, "The already awarded emerging model survives deletion of its former owning stone")
	await create_timer(0.48).timeout
	await _frames(2)
	_check(not jewel.is_emerging and not jewel.is_embedded and jewel.scale.is_equal_approx(Vector3.ONE) and jewel.position.distance_to(Vector3(0.0, 7.0, 2.0)) < 0.0001, "Immediate collection allows the emergence tween to reach its full-size endpoint")
	var disabled_colliders := true
	for collider in jewel.get("_colliders"):
		disabled_colliders = disabled_colliders and collider.disabled
	_check(jewel.collected and jewel.collision_layer == 0 and disabled_colliders, "Completing emergence never re-enables collision for an already awarded gem")
	jewel.set_hovered(true)
	_check(not jewel.begin_collection() and is_zero_approx(_hover(jewel)), "A completed reward cannot be highlighted or collected again")
	jewel.queue_free()
	await _frames(2)


func _hover(jewel: Gem) -> float:
	var material := jewel.facets.material_override as ShaderMaterial
	return float(material.get_shader_parameter("hovered")) if material != null else -1.0


func _collider_hulls(jewel: Gem, colliders: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for collider in colliders:
		var points := PackedVector3Array()
		for vertex in collider.shape.points:
			points.append(jewel.to_local(collider.to_global(vertex)))
		# Delaunay tetrahedra fill the convex hull independently of the model's
		# face generation, so this also checks facet-center vertices on its skin.
		var indices := Geometry3D.tetrahedralize_delaunay(points)
		var tetrahedra: Array = []
		for i in range(0, indices.size(), 4):
			var vertices := [points[indices[i]], points[indices[i + 1]], points[indices[i + 2]], points[indices[i + 3]]]
			var planes: Array[Plane] = []
			for face in [[0, 1, 2, 3], [0, 3, 1, 2], [0, 2, 3, 1], [1, 3, 2, 0]]:
				var plane := Plane(vertices[face[0]], vertices[face[1]], vertices[face[2]])
				if plane.distance_to(vertices[face[3]]) > 0.0:
					plane = Plane(-plane.normal, -plane.d)
				planes.append(plane)
			tetrahedra.append(planes)
		result.append({"points": points, "tetrahedra": tetrahedra})
	return result


func _inside_hulls(point: Vector3, hulls: Array[Dictionary]) -> bool:
	for hull in hulls:
		for vertex in hull.points:
			if point.distance_to(vertex) < 0.000002:
				return true
		for tetrahedron in hull.tetrahedra:
			var inside := true
			for plane in tetrahedron:
				inside = inside and plane.distance_to(point) <= 0.000003
			if inside:
				return true
	return false


func _point_key(point: Vector3) -> String:
	return str(Vector3i(roundi(point.x * 1000000.0), roundi(point.y * 1000000.0), roundi(point.z * 1000000.0)))


func _connected(adjacency: Dictionary) -> bool:
	if adjacency.is_empty():
		return false
	var pending: Array = [adjacency.keys()[0]]
	var seen: Dictionary = {}
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if seen.has(current):
			continue
		seen[current] = true
		for neighbor in adjacency[current]:
			if not seen.has(neighbor):
				pending.append(neighbor)
	return seen.size() == adjacency.size()


func _count_nodes(node: Node, type_name: String) -> int:
	var result := 1 if node.is_class(type_name) else 0
	for child in node.get_children():
		result += _count_nodes(child, type_name)
	return result


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("GEM_MODEL_CHECK_FAILED: " + description)
