extends SceneTree
## Independent surface coverage, crack provenance and debris lifecycle checks.

const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const Gem = preload("res://scripts/gem.gd")
const Effects = preload("res://scripts/mining_effects.gd")
const Fracture = preload("res://scripts/rock_fracture.gd")
const EPS := 0.0003

var fixture := Node3D.new()
var checks := 0
var failures: Array[String] = []
var sample_fragments: Array[Dictionary] = []
var sample_chunk: Chunk


func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
		push_error("FRACTURE_TEST_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.add_child(fixture)
	var outer := Geometry.build_layer(4.9, 0, 12873, 100, 0.86)
	var data: Dictionary = outer[0]
	var ordinary := _make_chunk(data, 0)
	var strike := 0
	while not ordinary.destroyed:
		ordinary.hit(1.0, ordinary.mesh_instance.to_global(_impact(ordinary, strike)))
		strike += 1
	_validate_partition(ordinary, "ordinary multi-hit")

	var fatal_a := _make_chunk(data, 0)
	fatal_a.hit(fatal_a.health + 20.0, fatal_a.mesh_instance.to_global(_impact(fatal_a, 0)))
	var pieces_a := _validate_partition(fatal_a, "single fatal off-center A")
	var fatal_b := _make_chunk(data, 0)
	fatal_b.hit(fatal_b.health + 20.0, fatal_b.mesh_instance.to_global(_impact(fatal_b, 1)))
	var pieces_b := _validate_partition(fatal_b, "single fatal off-center B")
	_check(_signature(pieces_a) != _signature(pieces_b), "Moving the actual fatal impact changes the resulting fracture partition")

	var cover := _make_chunk(data, 0)
	var jewel := Gem.new()
	jewel.configure(Gem.ANCIENT, 0)
	fixture.add_child(jewel)
	_check(cover.contain_gem(jewel), "The fracture cover fixture contains a real owned gem")
	for i in range(16):
		cover.hit(1.0, cover.mesh_instance.to_global(_impact(cover, i)))
	sample_chunk = cover
	sample_fragments = _validate_partition(cover, "16-hit gem owner")
	_check(jewel.is_embedded and not jewel.visible and jewel.collision_layer == 0, "Building owner debris cannot itself release or collect the embedded gem")

	var dense := _make_chunk(data, 0)
	for i in range(128):
		var edge := i % dense.face_points.size()
		var point: Vector3 = dense.face_center.lerp(dense.face_points[edge], 0.26 + float(i % 5) * 0.065)
		dense.hit(0.002, dense.mesh_instance.to_global(point))
	dense.hit(dense.health, dense.mesh_instance.to_global(_impact(dense, 2)))
	_validate_partition(dense, "129-hit dense fractional damage")

	# Small/deep plates and different broad outlines exercise thin geometry.
	var inner := Geometry.build_layer(1.0, 5, 61477, 14, 0.86)
	for index in [0, 4, 9]:
		var small := _make_chunk(inner[index], 5)
		small.hit(small.health, small.mesh_instance.to_global(_impact(small, index)))
		_validate_partition(small, "inner plate %d" % index)
	for index in [24, 57, 86]:
		var broad := _make_chunk(outer[index], 0)
		for i in range(3):
			broad.hit(0.25, broad.mesh_instance.to_global(_impact(broad, i)))
		broad.hit(broad.health, broad.mesh_instance.to_global(_impact(broad, 3)))
		_validate_partition(broad, "outer outline %d" % index)
	await _validate_effects()
	fixture.queue_free()
	await _frames(3)
	print("FRACTURE_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_chunk(data: Dictionary, layer: int) -> Chunk:
	var chunk := Chunk.new()
	fixture.add_child(chunk)
	chunk.configure(data, layer)
	chunk.set_process(false)
	return chunk


func _impact(chunk: Chunk, index: int) -> Vector3:
	var edge := int(float(posmod(index, 3)) * float(chunk.face_points.size()) / 3.0)
	var midpoint: Vector3 = (chunk.face_points[edge] + chunk.face_points[(edge + 1) % chunk.face_points.size()]) * 0.5
	return chunk.face_center.lerp(midpoint, 0.52)


func _validate_partition(chunk: Chunk, label: String) -> Array[Dictionary]:
	var before := chunk.get_fracture_crack_segments().duplicate(true)
	var before_rays: Array = chunk.light_node.get("_rays").duplicate(true) if is_instance_valid(chunk.light_node) else []
	var before_pulses: int = chunk.light_node.pulse_count if is_instance_valid(chunk.light_node) else 0
	var started := Time.get_ticks_usec()
	var fragments: Array[Dictionary] = chunk.build_fracture_fragments()
	print("FRACTURE_CASE ", label, " pieces=", fragments.size(), " cracks=", before.size(), " build_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	_check(chunk.destroyed and fragments.size() >= 2 and fragments.size() <= 18, label + ": destruction produces multiple bounded fragments")
	_check(chunk.get_fracture_crack_segments() == before, label + ": fracture generation preserves the accumulated visible front cuts")
	if is_instance_valid(chunk.light_node):
		_check(chunk.light_node.get("_rays") == before_rays and chunk.light_node.pulse_count == before_pulses, label + ": generating debris leaves the fatal light geometry and pulse unchanged")
	if fragments.size() < 2:
		return fragments
	var normal := chunk.direction.normalized()
	var tangent := (chunk.face_points[1] - chunk.face_points[0]).normalized()
	var bitangent := normal.cross(tangent).normalized()
	var face := _project(chunk.face_points, chunk.face_center, tangent, bitangent)
	var face_area := _area(face)
	var polygons: Array[PackedVector2Array] = []
	var sum_area := 0.0
	var all_inside := true
	var finite_and_planar := true
	var area_metadata := true
	var largest_area := 0.0
	var boundaries: Array[Dictionary] = chunk.get_fracture_boundaries()
	var all_edges_supported := true
	for fragment in fragments:
		var polygon: PackedVector3Array = fragment.polygon
		var projected := _project(polygon, chunk.face_center, tangent, bitangent)
		polygons.append(projected)
		var measured := _area(projected)
		sum_area += measured
		largest_area = maxf(largest_area, measured)
		area_metadata = area_metadata and measured > 0.0000001 and absf(measured - float(fragment.area)) < maxf(0.0001, measured * 0.002)
		for i in range(polygon.size()):
			finite_and_planar = finite_and_planar and polygon[i].is_finite() and absf(normal.dot(polygon[i] - chunk.face_center)) < EPS
			all_inside = all_inside and (Geometry2D.is_point_in_polygon(projected[i], face) or _polygon_distance(projected[i], face) < EPS)
			all_edges_supported = all_edges_supported and _edge_covered(polygon[i], polygon[(i + 1) % polygon.size()], boundaries)
		_validate_mesh(chunk, fragment, label)
	_check(finite_and_planar and all_inside, label + ": every fragment polygon is finite and remains on the original stone face")
	_check(area_metadata, label + ": reported areas match independent polygon measurements")
	_check(absf(sum_area - face_area) < maxf(0.0002, face_area * 0.001), label + ": fragment areas exactly cover the original face")
	_check(largest_area < face_area * 0.94, label + ": the result does not disguise the original whole plate as one fragment")
	var overlap := 0.0
	for i in range(polygons.size()):
		for j in range(i + 1, polygons.size()):
			for intersection in Geometry2D.intersect_polygons(polygons[i], polygons[j]):
				overlap += _area(intersection)
	_check(overlap < maxf(0.00005, face_area * 0.0005), label + ": distinct fragment polygons do not overlap")
	_check(_sample_coverage(face, polygons), label + ": independent face samples encounter exactly one fragment with no gaps")
	_check(not boundaries.is_empty() and all_edges_supported, label + ": every final polygon edge follows a recorded crack, extension or original perimeter")
	var valid_sources := true
	var actual_crack_edges := 0
	var invalid_boundaries: Array[Dictionary] = []
	for boundary in boundaries:
		var kind: String = boundary.kind
		var valid_boundary := false
		if kind == "crack":
			valid_boundary = _edge_covered(boundary.a, boundary.b, before)
			actual_crack_edges += 1
		elif kind == "extension":
			valid_boundary = _justified_extension(boundary, before)
		elif kind == "boundary":
			valid_boundary = _edge_on_perimeter(boundary.a, boundary.b, chunk.face_points)
		valid_sources = valid_sources and valid_boundary
		if not valid_boundary and invalid_boundaries.size() < 3:
			invalid_boundaries.append(boundary)
	if not invalid_boundaries.is_empty():
		print("FRACTURE_UNSUPPORTED ", label, " ", invalid_boundaries)
	_check(valid_sources and actual_crack_edges > 0, label + ": boundary provenance resolves to real visible cracks or collinear free-tip extensions")
	_validate_morphology(chunk, fragments, label)
	var repeated: Array[Dictionary] = Fracture.build(chunk.mesh_instance.mesh, chunk.face_points, chunk.face_center, chunk.direction, before).fragments
	_check(_same_geometry(fragments, repeated), label + ": fresh generation reproduces the same complete fragment geometry deterministically")
	return fragments


func _validate_mesh(chunk: Chunk, fragment: Dictionary, label: String) -> void:
	var mesh: Mesh = fragment.mesh
	var center: Vector3 = fragment.center
	var valid := mesh != null and mesh != chunk.mesh_instance.mesh and center.is_finite()
	var solid := true
	var edges: Dictionary = {}
	var front_area := 0.0
	var front_plane := chunk.direction.dot(chunk.face_center)
	var deepest := 0.0
	var original_depth := 0.0
	var face_epsilon := maxf(0.000001, sqrt(float(fragment.area)) * 0.000001)
	for point in chunk.mesh_instance.mesh.get_faces():
		original_depth = maxf(original_depth, front_plane - chunk.direction.dot(point))
	if not valid:
		_check(false, label + ": fragment has a unique valid mesh")
		return
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		valid = valid and count >= 3 and count % 3 == 0 and normals.size() == vertices.size()
		for i in range(0, count, 3):
			var triangle: Array[Vector3] = []
			var triangle_normals: Array[Vector3] = []
			for j in range(3):
				var index: int = indices[i + j] if not indices.is_empty() else i + j
				var point: Vector3 = vertices[index] + center
				var normal: Vector3 = normals[index]
				valid = valid and point.is_finite() and normal.is_finite() and absf(normal.length() - 1.0) < 0.001
				var depth := front_plane - chunk.direction.dot(point)
				solid = solid and depth >= -EPS and depth <= original_depth + EPS
				deepest = maxf(deepest, depth)
				triangle.append(point)
				triangle_normals.append(normal)
			var cross := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
			valid = valid and cross.length() > 0.00000001
			for normal in triangle_normals:
				valid = valid and cross.dot(normal) < 0.000000001
			var on_front := true
			for point in triangle:
				on_front = on_front and absf(chunk.direction.dot(point) - front_plane) < face_epsilon
			if on_front:
				front_area += cross.length() * 0.5
			for j in range(3):
				var key := _edge_key(triangle[j], triangle[(j + 1) % 3])
				edges[key] = int(edges.get(key, 0)) + 1
	var closed := true
	for count in edges.values():
		closed = closed and int(count) == 2
	_check(valid, label + ": fragment triangles are finite, nondegenerate and have unit outward normals with correct winding")
	_check(solid and deepest > sqrt(float(fragment.area)) * 0.001 and closed, label + ": fragment is a closed solid with positive scale-relative thickness inside the original stone depth")
	_check(absf(front_area - float(fragment.area)) < maxf(0.0002, float(fragment.area) * 0.003), label + ": reconstructed front triangles cover their exact fracture polygon")


func _validate_morphology(chunk: Chunk, fragments: Array[Dictionary], label: String) -> void:
	var normal := chunk.direction.normalized()
	var tangent := (chunk.face_points[1] - chunk.face_points[0]).normalized()
	var bitangent := normal.cross(tangent).normalized()
	var original_depth := 0.0
	for point in chunk.mesh_instance.mesh.get_faces():
		original_depth = maxf(original_depth, normal.dot(chunk.face_center - point))
	var compact := true
	var substantial := true
	var tapered := true
	var angled := true
	var max_width_ratio := 0.0
	var max_area_ratio := 0.0
	var max_section_ratio := 0.0
	for fragment in fragments:
		var polygon: PackedVector3Array = fragment.polygon
		var projected := _project(polygon, chunk.face_center, tangent, bitangent)
		var width := _minimum_width(projected)
		var area_scale := sqrt(_area(projected))
		var center: Vector3 = fragment.center
		var triangles: PackedVector3Array = fragment.mesh.get_faces()
		var depth := 0.0
		var oblique_rear := false
		var angled_sides := 0
		for point in triangles:
			depth = maxf(depth, normal.dot(chunk.face_center - point - center))
		for i in range(0, triangles.size(), 3):
			var cross := (triangles[i + 1] - triangles[i]).cross(triangles[i + 2] - triangles[i])
			if cross.length_squared() <= 0.0000000000001:
				continue
			# Godot's outward face normal is opposite its clockwise cross product.
			var face_normal := -cross.normalized()
			var alignment := face_normal.dot(normal)
			oblique_rear = oblique_rear or (alignment < -0.1 and face_normal.cross(normal).length() > 0.03)
			if absf(alignment) > 0.1 and absf(alignment) < 0.98:
				angled_sides += 1
		var width_ratio := depth / maxf(width, 0.0000001)
		var area_ratio := depth / maxf(area_scale, 0.0000001)
		max_width_ratio = maxf(max_width_ratio, width_ratio)
		max_area_ratio = maxf(max_area_ratio, area_ratio)
		compact = compact and width_ratio < 1.0 and area_ratio < 0.9
		substantial = substantial and depth > minf(minf(width, area_scale), original_depth) * 0.03
		var front_hull := Geometry2D.convex_hull(projected)
		var section := _mesh_section(triangles, center, chunk.face_center, normal, tangent, bitangent, depth * 0.65)
		var section_ratio := _area(Geometry2D.convex_hull(section)) / maxf(_area(front_hull), 0.0000001) if section.size() >= 3 else 0.0
		max_section_ratio = maxf(max_section_ratio, section_ratio)
		tapered = tapered and section.size() >= 3 and section_ratio > 0.01 and section_ratio < 0.9
		angled = angled and oblique_rear and angled_sides >= 2
	print("FRAGMENT_MORPHOLOGY ", label, " max_depth/width=", max_width_ratio, " max_depth/sqrt_area=", max_area_ratio, " max_rear_section_ratio=", max_section_ratio)
	_check(compact and substantial, label + ": actual fragment thickness scales with its footprint, forming solid chips rather than long columns or zero-thickness flakes")
	_check(tapered, label + ": actual deep mesh sections taper substantially below the front footprint")
	_check(angled, label + ": each piece has slanted sides and an irregular angled underside instead of a parallel translated back face")


func _minimum_width(polygon: PackedVector2Array) -> float:
	var hull := Geometry2D.convex_hull(polygon)
	var width := INF
	for i in range(hull.size()):
		var edge := hull[(i + 1) % hull.size()] - hull[i]
		if edge.length_squared() < 0.000000000001:
			continue
		var axis := Vector2(-edge.y, edge.x).normalized()
		var low := INF
		var high := -INF
		for point in hull:
			low = minf(low, axis.dot(point))
			high = maxf(high, axis.dot(point))
		width = minf(width, high - low)
	return width


func _mesh_section(triangles: PackedVector3Array, center: Vector3, origin: Vector3, normal: Vector3, tangent: Vector3, bitangent: Vector3, depth: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, triangles.size(), 3):
		for j in range(3):
			var a := triangles[i + j] + center
			var b := triangles[i + (j + 1) % 3] + center
			var da := normal.dot(origin - a) - depth
			var db := normal.dot(origin - b) - depth
			if absf(da) < 0.0000001:
				points.append(Vector2((a - origin).dot(tangent), (a - origin).dot(bitangent)))
			if da * db < 0.0:
				var point := a.lerp(b, da / (da - db))
				points.append(Vector2((point - origin).dot(tangent), (point - origin).dot(bitangent)))
	return points


func _same_geometry(first: Array[Dictionary], second: Array[Dictionary]) -> bool:
	if first.size() != second.size():
		return false
	for i in range(first.size()):
		if first[i].center != second[i].center or first[i].polygon != second[i].polygon or first[i].area != second[i].area:
			return false
		var a: Mesh = first[i].mesh
		var b: Mesh = second[i].mesh
		if a.get_faces() != b.get_faces() or a.get_surface_count() != b.get_surface_count():
			return false
		for surface_index in range(a.get_surface_count()):
			if a.surface_get_arrays(surface_index)[Mesh.ARRAY_NORMAL] != b.surface_get_arrays(surface_index)[Mesh.ARRAY_NORMAL]:
				return false
	return true


func _validate_effects() -> void:
	if sample_fragments.size() < 2:
		_check(false, "Effects require a valid multiple-fragment fixture")
		return
	var transformed := Node3D.new()
	fixture.add_child(transformed)
	transformed.position = Vector3(2.1, 3.7, -1.4)
	transformed.rotation = Vector3(0.32, -0.67, 0.26)
	transformed.scale = Vector3(1.13, 0.92, 1.04)
	var effects := Effects.new()
	transformed.add_child(effects)
	effects.position = Vector3(-0.8, 0.3, 0.4)
	effects.rotation = Vector3(-0.2, 0.15, 0.42)
	effects.set_process(false)
	var placement := Transform3D(Basis.from_euler(Vector3(-0.27, 0.61, 0.19)).scaled(Vector3(1.21, 0.84, 1.08)), Vector3(-1.3, 2.8, 0.7))
	placement.origin -= placement.basis * sample_chunk.direction * 0.081
	var outward := (placement.basis.inverse().transposed() * sample_chunk.direction).normalized()
	var impact := placement * sample_chunk.latest_impact_local
	var source_material: ShaderMaterial = sample_chunk.mesh_instance.material_override
	source_material.set_shader_parameter("hit_flash", 0.8)
	source_material.set_shader_parameter("hovered", 0.7)
	effects.shed_fragments(sample_fragments, source_material, placement, outward, impact)
	_check(effects.loose_chunks.size() == sample_fragments.size(), "A fracture spawns exactly its generated pieces, with no whole-plate substitute")
	var positioned := true
	var unique_meshes: Array[Mesh] = []
	var initial_positions: Array[Vector3] = []
	var references: Array[WeakRef] = []
	var velocities: Array[Vector3] = []
	var lifetimes: Array[float] = []
	var materials_settled := true
	for entry in effects.loose_chunks:
		var node: MeshInstance3D = entry.node
		var material: ShaderMaterial = node.material_override
		materials_settled = materials_settled and material != source_material and is_zero_approx(float(material.get_shader_parameter("hit_flash"))) and is_zero_approx(float(material.get_shader_parameter("hovered")))
		var source_index := -1
		for i in range(sample_fragments.size()):
			if node.mesh == sample_fragments[i].mesh:
				source_index = i
		_check(source_index >= 0 and not unique_meshes.has(node.mesh) and node.mesh != sample_chunk.mesh_instance.mesh, "Every loose piece uses a distinct generated mesh")
		unique_meshes.append(node.mesh)
		if source_index >= 0:
			var source: Dictionary = sample_fragments[source_index]
			for vertex in node.mesh.get_faces():
				positioned = positioned and node.to_global(vertex).distance_to(placement * (vertex + Vector3(source.center))) < 0.001
		initial_positions.append(node.global_position)
		references.append(weakref(node))
		velocities.append(entry.velocity)
		lifetimes.append(entry.life)
	_check(positioned, "Rotated, nonuniformly scaled and recoiling stone fragments start exactly on the original mesh in world space")
	_check(materials_settled and is_equal_approx(float(source_material.get_shader_parameter("hit_flash")), 0.8) and is_equal_approx(float(source_material.get_shader_parameter("hovered")), 0.7), "Debris sheds permanent hit and hover flashes without mutating the original stone material")
	_check(lifetimes.all(func(life: float): return life > 0.2 and life < 2.0), "All emitted pieces have short, finite visual lifetimes")
	_check(_vectors_differ(velocities, 0.15), "Fragments begin with distinct outward trajectories")
	effects._process(0.12)
	var displacements: Array[Vector3] = []
	var valid_motion := true
	for i in range(effects.loose_chunks.size()):
		var node: MeshInstance3D = effects.loose_chunks[i].node
		var displacement := node.global_position - initial_positions[i]
		displacements.append(displacement)
		valid_motion = valid_motion and displacement.is_finite() and displacement.length() > 0.02 and displacement.dot(outward) > 0.0
	_check(valid_motion and _vectors_differ(displacements, 0.02), "Separate pieces visibly diverge outward instead of moving as one plate, even under transformed effect parents")
	for i in range(30):
		effects._process(0.1)
	_check(effects.loose_chunks.is_empty(), "Every debris piece expires after its finite visual lifetime")
	var inactive := true
	for reference in references:
		var node: Node3D = reference.get_ref()
		inactive = inactive and (node == null or not node.visible)
	_check(inactive, "Expired fragment nodes are either freed or hidden for bounded reuse")
	for i in range(12):
		effects.shed_fragments(sample_fragments, sample_chunk.mesh_instance.material_override, placement, outward, impact)
	_check(effects.loose_chunks.size() <= Effects.FRAGMENT_CAPACITY and effects.loose_chunks.size() > sample_fragments.size(), "Rapid repeated breaks retain multiple batches while respecting the global debris budget")
	var mesh_nodes := 0
	for child in effects.get_children():
		if child is MeshInstance3D and not child.is_queued_for_deletion():
			mesh_nodes += 1
			references.append(weakref(child))
	_check(mesh_nodes <= Effects.FRAGMENT_CAPACITY, "Active and pooled debris together stay within the allocation budget")
	effects.clear_fragments()
	_check(effects.loose_chunks.is_empty(), "Reset immediately clears the active fragment list")
	await _frames(3)
	var cleared := true
	for reference in references:
		cleared = cleared and reference.get_ref() == null
	_check(cleared, "Reset frees every active and pooled fragment node")


func _project(points: PackedVector3Array, origin: Vector3, tangent: Vector3, bitangent: Vector3) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(Vector2((point - origin).dot(tangent), (point - origin).dot(bitangent)))
	return result


func _area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in range(polygon.size()):
		twice_area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice_area) * 0.5


func _polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var distance := INF
	for i in range(polygon.size()):
		var a := polygon[i]
		var travel := polygon[(i + 1) % polygon.size()] - a
		var t := clampf((point - a).dot(travel) / maxf(travel.length_squared(), 0.000000001), 0.0, 1.0)
		distance = minf(distance, point.distance_to(a + travel * t))
	return distance


func _sample_coverage(face: PackedVector2Array, polygons: Array[PackedVector2Array]) -> bool:
	var bounds := Rect2(face[0], Vector2.ZERO)
	for point in face:
		bounds = bounds.expand(point)
	var checked := 0
	for x in range(31):
		for y in range(29):
			var point := bounds.position + bounds.size * Vector2((x + 0.37) / 31.0, (y + 0.61) / 29.0)
			if not Geometry2D.is_point_in_polygon(point, face) or _polygon_distance(point, face) < EPS:
				continue
			var near_edge := false
			var owners := 0
			for polygon in polygons:
				near_edge = near_edge or _polygon_distance(point, polygon) < EPS
				if Geometry2D.is_point_in_polygon(point, polygon):
					owners += 1
			if not near_edge:
				checked += 1
				if owners != 1:
					return false
	return checked > 100


func _edge_covered(a: Vector3, b: Vector3, sources: Array[Dictionary]) -> bool:
	var length := a.distance_to(b)
	if length <= EPS:
		return true
	var direction := (b - a) / length
	var intervals: Array[Vector2] = []
	for source in sources:
		var start: Vector3 = source.a
		var end: Vector3 = source.b
		# Test the short snapped output edge against its long unsnapped source.
		# Extrapolating the short edge instead magnifies harmless rounding noise.
		var source_direction := (end - start).normalized()
		if source_direction.length_squared() < 0.5 or source_direction.cross(a - start).length() > EPS or source_direction.cross(b - start).length() > EPS:
			continue
		var ta := direction.dot(start - a)
		var tb := direction.dot(end - a)
		var low := maxf(minf(ta, tb), 0.0)
		var high := minf(maxf(ta, tb), length)
		if high > low:
			intervals.append(Vector2(low, high))
	intervals.sort_custom(func(left: Vector2, right: Vector2): return left.x < right.x)
	var covered_to := 0.0
	for interval in intervals:
		if interval.x > covered_to + EPS:
			return false
		covered_to = maxf(covered_to, interval.y)
	return covered_to >= length - EPS


func _edge_on_perimeter(a: Vector3, b: Vector3, polygon: PackedVector3Array) -> bool:
	var edges: Array[Dictionary] = []
	for i in range(polygon.size()):
		edges.append({"a": polygon[i], "b": polygon[(i + 1) % polygon.size()]})
	return _edge_covered(a, b, edges)


func _justified_extension(extension: Dictionary, segments: Array[Dictionary]) -> bool:
	var a: Vector3 = extension.a
	var b: Vector3 = extension.b
	for i in range(segments.size()):
		var source: Dictionary = segments[i]
		var start: Vector3 = source.a
		var end: Vector3 = source.b
		var direction := (end - start).normalized()
		if direction.cross(a - start).length() > EPS or direction.cross(b - start).length() > EPS:
			continue
		for endpoint in [start, end]:
			var outward := (start - end).normalized() if endpoint == start else direction
			if outward.dot(a - endpoint) < -EPS or outward.dot(b - endpoint) < -EPS:
				continue
			var free_tip := true
			for j in range(segments.size()):
				# Topological contact needs a tighter tolerance than the relaxed
				# transformed-mesh measurement above; nearby cracks remain distinct.
				if i != j and _point_segment_distance(endpoint, segments[j].a, segments[j].b) < 0.00002:
					free_tip = false
					break
			if free_tip:
				return true
	return false


func _point_segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var travel := b - a
	return point.distance_to(a + travel * clampf((point - a).dot(travel) / maxf(travel.length_squared(), 0.000000001), 0.0, 1.0))


func _edge_key(a: Vector3, b: Vector3) -> String:
	var first := str(Vector3i(roundi(a.x * 100000.0), roundi(a.y * 100000.0), roundi(a.z * 100000.0)))
	var second := str(Vector3i(roundi(b.x * 100000.0), roundi(b.y * 100000.0), roundi(b.z * 100000.0)))
	return first + ":" + second if first < second else second + ":" + first


func _signature(fragments: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for fragment in fragments:
		var vertices: Array[String] = []
		for point in fragment.polygon:
			vertices.append(str(Vector3(point).snapped(Vector3.ONE * 0.0001)))
		vertices.sort()
		result.append("/".join(vertices))
	result.sort()
	return result


func _vectors_differ(vectors: Array[Vector3], tolerance: float) -> bool:
	for i in range(vectors.size()):
		for j in range(i + 1, vectors.size()):
			if vectors[i].distance_to(vectors[j]) > tolerance:
				return true
	return false


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("FRACTURE_CHECK_FAILED: " + description)
