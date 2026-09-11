extends SceneTree
## Independent integration checks against the actual rendered solid triangles.
## The wrap helper is deliberately never used as a geometric oracle.
const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const Gem = preload("res://scripts/gem.gd")
const EPS := 0.00035

var checks := 0
var failures: Array[String] = []
var fixture := Node3D.new()
var reported_points := {}


func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
		push_error("ALL_FACE_VALIDATION_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.add_child(fixture)
	fixture.process_mode = Node.PROCESS_MODE_DISABLED
	var data: Dictionary = Geometry.build_layer(4.9, 0, 12873, 100, 0.86)[0]
	for kind: String in ["front", "side", "rear"]:
		var chunk := _make_cover(data)
		var triangles := _triangles(chunk.mesh_instance.mesh)
		var sites := _sites(triangles, chunk.direction)
		_check(sites.has(kind), kind + ": actual rendered target triangle exists")
		if not sites.has(kind):
			continue
		var target: Vector3 = sites[kind].point
		_check(chunk.get_surface_crack_segments().is_empty(), kind + ": intact stone has no surface cracks")
		_check(not chunk.light_node.visible and chunk.light_node.get("_rays").is_empty(), kind + ": no prestrike light")
		chunk.rotation = Vector3(0.32, -0.61, 0.21)
		chunk.scale = Vector3(1.17, 0.81, 1.29)
		chunk.mesh_instance.position = Vector3(0.021, -0.034, 0.018)
		var old_starts := PackedVector3Array()
		for hit_index in 15:
			var world_target := chunk.mesh_instance.to_global(target)
			chunk.hit(1.0, world_target)
			var label := "%s hit %d" % [kind, hit_index + 1]
			_check(chunk.latest_impact_local.distance_to(target) < EPS, label + ": actual contact survives rotation, scale and recoil")
			var anchor: Dictionary = chunk.get("_crack_anchors")[chunk.impact_count]
			_check(Vector3(anchor.point).distance_to(target) < EPS, label + ": anchor stores the actual contacted surface")
			var segments := chunk.get_surface_crack_segments()
			_validate_surface(segments, triangles, label)
			_check(_distance_to_lines(target, segments) < EPS, label + ": a visible centerline reaches the struck point")
			var pinned := true
			for point in old_starts:
				pinned = pinned and _distance_to_lines(point, segments) < EPS
			_check(pinned, label + ": established bends and seam crossings stay pinned as damage grows")
			old_starts = _line_starts(segments)
			_validate_light(chunk, segments, label)
			_validate_unstretched_size(chunk, label)
			chunk._process(0.023)
		var final_segments := chunk.get_surface_crack_segments()
		var marked_face := false
		for segment in final_segments:
			var alignment := Vector3(segment.normal).dot(chunk.direction)
			marked_face = marked_face or (alignment > 0.95 if kind == "front" else (alignment < -0.75 if kind == "rear" else absf(alignment) < 0.75))
		_check(marked_face, kind + ": repeated damage remains attached to the actual struck face")
		_validate_connections(final_segments, kind)
		_validate_idle_and_fatal(chunk, target, kind)
		chunk.free()
	# Repeated existing contacts must deepen the same bounded networks.
	var repeated := _make_cover(data)
	var repeated_sites := _sites(_triangles(repeated.mesh_instance.mesh), repeated.direction)
	var kinds := ["front", "side", "rear"]
	for hit_index in 48:
		var target: Vector3 = repeated_sites[kinds[hit_index % 3]].point
		repeated.hit(0.02, repeated.mesh_instance.to_global(target))
	_check(repeated.get("_crack_networks").size() <= Chunk.MAX_CRACK_NETWORKS, "48 alternating contacts retain the two-network budget")
	_check(repeated.get("_crack_connectors").size() <= 4, "Repeated covered contacts do not accumulate new connector paths")
	_validate_surface(repeated.get_surface_crack_segments(), _triangles(repeated.mesh_instance.mesh), "48 alternating contacts")
	repeated.free()
	_validate_moved_contact_sequence(data)
	_validate_edge_origin(data)
	fixture.queue_free()
	await process_frame
	print("ALL_FACE_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_cover(data: Dictionary) -> Chunk:
	var chunk := Chunk.new()
	fixture.add_child(chunk)
	chunk.configure(data, 0)
	var jewel := Gem.new()
	jewel.configure(Gem.SPECIAL, 0)
	fixture.add_child(jewel)
	_check(chunk.contain_gem(jewel), "Fixture embeds a real gem in the actual solid")
	return chunk


func _validate_moved_contact_sequence(data: Dictionary) -> void:
	var chunk := _make_cover(data)
	chunk.position += Vector3(1.4, -0.7, 0.9)
	chunk.rotation = Vector3(-0.27, 0.48, -0.19)
	chunk.scale = Vector3(0.79, 1.31, 1.08)
	var triangles := _triangles(chunk.mesh_instance.mesh)
	var previous: Array[Dictionary] = []
	var highest_networks := 0
	for kind: String in ["front", "side", "rear", "front", "side", "rear", "front", "rear", "side"]:
		var target := _uncovered_face_point(chunk, triangles, kind)
		_check(target.is_finite(), kind + ": moving-contact fixture finds actual uncovered stone")
		if not target.is_finite():
			chunk.free()
			return
		chunk.mesh_instance.position = Vector3(0.017, -0.031, 0.024) * (1.0 if chunk.impact_count % 2 == 0 else -1.0)
		chunk.hit(0.2, chunk.mesh_instance.to_global(target))
		var current := chunk.get_surface_crack_segments()
		var label := "moving %s hit %d" % [kind, chunk.impact_count]
		_check(chunk.latest_impact_local.distance_to(target) < EPS and _distance_to_lines(target, current) < EPS and _crack_covers(target, current), label + ": every newly uncovered contact receives an attached mark")
		var network_count: int = chunk.get("_crack_networks").size()
		highest_networks = maxi(highest_networks, network_count)
		_check(network_count <= Chunk.MAX_CRACK_NETWORKS, label + ": new face contacts respect the major-network budget")
		var pinned := true
		for old in previous:
			if not bool(old.has_centerline):
				continue
			var same_hit: Array[Dictionary] = []
			for segment in current:
				if int(segment.hit_id) == int(old.hit_id):
					same_hit.append(segment)
			for point: Vector3 in [old.a, old.b, Vector3(old.a).lerp(old.b, 0.5)]:
				pinned = pinned and _distance_to_lines(point, same_hit) < EPS
		_check(pinned, label + ": old endpoints and bends stay fixed within their original hit network")
		var fresh := false
		for ray: Dictionary in chunk.light_node.get("_rays"):
			fresh = fresh or (int(ray.source_hit_id) == chunk.impact_count and Vector3(ray.source_impact).distance_to(target) < EPS)
		_check(fresh, label + ": the new light uses this actual face contact")
		_validate_light(chunk, current, label)
		_validate_unstretched_size(chunk, label)
		previous = current
	_check(highest_networks == Chunk.MAX_CRACK_NETWORKS and chunk.get("_crack_connectors").size() >= 3, "Moving-contact fixture exercises new face anchors after filling both major networks")
	var fatal_target := _uncovered_face_point(chunk, triangles, "rear")
	_check(fatal_target.is_finite(), "Moving fatal fixture selects a fresh uncovered rear point")
	if fatal_target.is_finite():
		_validate_idle_and_fatal(chunk, fatal_target, "moving rear fatal")
		_check(chunk.latest_impact_local.distance_to(fatal_target) < EPS and _distance_to_lines(fatal_target, chunk.get_surface_crack_segments()) < EPS, "Fatal moving contact preserves its real rear anchor without a ghost mesh")
	_validate_surface(chunk.get_surface_crack_segments(), triangles, "moving final surface")
	chunk.free()


func _validate_unstretched_size(chunk: Chunk, label: String) -> void:
	var canonical := chunk.get_visible_crack_segments()
	var physical_lengths := {}
	var width_matches := true
	for segment in chunk.get_surface_crack_segments():
		if not bool(segment.has_centerline):
			continue
		var source := int(segment.source_index)
		if source < 0 or source >= canonical.size():
			_check(false, label + ": surface size has a canonical source")
			return
		physical_lengths[source] = float(physical_lengths.get(source, 0.0)) + Vector3(segment.a).distance_to(segment.b)
		width_matches = width_matches and float(segment.width) <= float(canonical[source].width) + EPS
	var lengths_match := not canonical.is_empty()
	for i in canonical.size():
		var original_length := Vector3(canonical[i].a).distance_to(canonical[i].b)
		var surface_length := float(physical_lengths.get(i, 0.0))
		lengths_match = lengths_match and absf(surface_length - original_length) < EPS
	_check(lengths_match and width_matches, label + ": folded surface paths retain the original crack length and width without an artificial size multiplier")


func _validate_edge_origin(data: Dictionary) -> void:
	var chunk := _make_cover(data)
	var triangles := _triangles(chunk.mesh_instance.mesh)
	var target := Vector3.INF
	var largest_area := -1.0
	for triangle in triangles:
		if absf(Vector3(triangle.normal).dot(chunk.direction)) >= 0.75 or float(triangle.area) <= largest_area:
			continue
		var points: Array[Vector3] = [triangle.a, triangle.b, triangle.c]
		for i in 3:
			var a := points[i]
			var b := points[(i + 1) % 3]
			for neighbor in triangles:
				if Vector3(triangle.normal).dot(neighbor.normal) > 0.90:
					continue
				var shared_a := false
				var shared_b := false
				for point: Vector3 in [neighbor.a, neighbor.b, neighbor.c]:
					shared_a = shared_a or point.distance_to(a) < 0.00001
					shared_b = shared_b or point.distance_to(b) < 0.00001
				if shared_a and shared_b:
					var center := (points[0] + points[1] + points[2]) / 3.0
					target = a.lerp(b, 0.5).lerp(center, 0.035)
					largest_area = float(triangle.area)
	_check(target.is_finite(), "Edge fixture locates a point just inside a real noncoplanar side crease")
	if target.is_finite():
		for i in 15:
			chunk.hit(1.0, chunk.mesh_instance.to_global(target))
		var segments := chunk.get_surface_crack_segments()
		_check(_distance_to_lines(target, segments) < EPS, "Near-edge damage starts at the actual side contact")
		_validate_connections(segments, "natural edge growth", true)
		_validate_surface(segments, triangles, "natural edge growth")
		_validate_light(chunk, segments, "natural edge growth")
		_validate_unstretched_size(chunk, "natural edge growth")
		_validate_idle_and_fatal(chunk, target, "natural edge growth")
	chunk.free()


func _uncovered_face_point(chunk: Chunk, triangles: Array[Dictionary], kind: String) -> Vector3:
	var result := Vector3.INF
	var best_distance := -1.0
	var cracks := chunk.get_surface_crack_segments()
	for triangle in triangles:
		var alignment := Vector3(triangle.normal).dot(chunk.direction)
		var actual_kind := "front" if alignment > 0.95 else ("rear" if alignment < -0.75 else "side")
		if actual_kind != kind:
			continue
		for weights: Vector3 in [Vector3.ONE / 3.0, Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6)]:
			var point: Vector3 = Vector3(triangle.a) * weights.x + Vector3(triangle.b) * weights.y + Vector3(triangle.c) * weights.z
			var distance := _distance_to_lines(point, cracks)
			if not _crack_covers(point, cracks) and distance > best_distance:
				result = point
				best_distance = distance
	return result


func _crack_covers(point: Vector3, segments: Array[Dictionary]) -> bool:
	for segment in segments:
		var polygon: PackedVector3Array = segment.polygon
		for i in range(1, polygon.size() - 1):
			var triangle := {"a": polygon[0], "b": polygon[i], "c": polygon[i + 1], "normal": segment.normal}
			if _inside_triangle(point, triangle, 0.00001):
				return true
	return false


func _triangles(mesh: Mesh) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Read uploaded vertices directly. Mesh.get_faces() can return the cached
	# TriangleMesh's snapped vertices, which are unsuitable for micron-level
	# contact comparisons after an independent nonuniform transform.
	var vertices := PackedVector3Array()
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			vertices.append_array(source)
		else:
			for index in indices:
				vertices.append(source[index])
	for i in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() > 0.0000000001:
			result.append({"a": a, "b": b, "c": c, "normal": -cross.normalized(), "area": cross.length() * 0.5})
	return result


func _sites(triangles: Array[Dictionary], direction: Vector3) -> Dictionary:
	var result := {}
	for triangle in triangles:
		var alignment := Vector3(triangle.normal).dot(direction)
		var kind := "front" if alignment > 0.95 else ("rear" if alignment < -0.75 else "side")
		if not result.has(kind) or float(triangle.area) > float(result[kind].area):
			result[kind] = {"point": (Vector3(triangle.a) + Vector3(triangle.b) + Vector3(triangle.c)) / 3.0, "area": triangle.area}
	return result


func _validate_surface(segments: Array[Dictionary], triangles: Array[Dictionary], label: String) -> void:
	_check(not segments.is_empty(), label + ": actual surface patches exist")
	var endpoints_ok := true
	var polygons_ok := true
	var normals_ok := true
	var faces_ok := true
	var metadata_ok := true
	for segment in segments:
		metadata_ok = metadata_ok and segment.has("has_centerline") and segment.has("face_id") and segment.has("normal") and segment.has("polygon")
		var normal: Vector3 = segment.get("normal", Vector3.ZERO)
		normals_ok = normals_ok and absf(normal.length() - 1.0) < EPS
		faces_ok = faces_ok and int(segment.get("face_id", -1)) >= 0
		if bool(segment.get("has_centerline", true)):
			endpoints_ok = endpoints_ok and _on_mesh(segment.a, normal, triangles) and _on_mesh(segment.b, normal, triangles)
		var polygon: PackedVector3Array = segment.get("polygon", PackedVector3Array())
		polygons_ok = polygons_ok and polygon.size() >= 3
		for point in polygon:
			polygons_ok = polygons_ok and _on_mesh(point, normal, triangles)
		# Polygon interiors must remain on the solid too, not span a corner in air.
		if polygon.size() >= 3:
			for i in range(1, polygon.size() - 1):
				polygons_ok = polygons_ok and _on_mesh((polygon[0] + polygon[i] + polygon[i + 1]) / 3.0, normal, triangles)
	_check(metadata_ok and faces_ok, label + ": every patch exposes face and centerline provenance")
	_check(normals_ok, label + ": patch normals are normalized")
	_check(endpoints_ok, label + ": all centerline endpoints lie on actual triangles with matching outward normals")
	_check(polygons_ok, label + ": every crack bank vertex and interior lies on the actual solid")


func _on_mesh(point: Vector3, normal: Vector3, triangles: Array[Dictionary]) -> bool:
	for triangle in triangles:
		if Vector3(triangle.normal).dot(normal) > 0.999 and _inside_triangle(point, triangle):
			return true
	var key := str(normal.snapped(Vector3.ONE * 0.02))
	if not reported_points.has(key) and reported_points.size() < 8:
		reported_points[key] = true
		var nearby: Array[Dictionary] = []
		for triangle in triangles:
			if _inside_triangle(point, triangle):
				nearby.append({"normal": triangle.normal, "dot": Vector3(triangle.normal).dot(normal)})
		print("ALL_FACE_OFF_SURFACE point=", point, " normal=", normal, " containing_triangles=", nearby)
	return false


func _inside_triangle(point: Vector3, triangle: Dictionary, tolerance: float = EPS) -> bool:
	var a: Vector3 = triangle.a
	var ab: Vector3 = triangle.b - a
	var ac: Vector3 = triangle.c - a
	if absf(Vector3(triangle.normal).dot(point - a)) > tolerance:
		return false
	var ap := point - a
	var denominator := ab.dot(ab) * ac.dot(ac) - ab.dot(ac) * ab.dot(ac)
	if absf(denominator) < 0.000000000001:
		return false
	var u := (ac.dot(ac) * ap.dot(ab) - ab.dot(ac) * ap.dot(ac)) / denominator
	var v := (ab.dot(ab) * ap.dot(ac) - ab.dot(ac) * ap.dot(ab)) / denominator
	if u >= 0.0 and v >= 0.0 and u + v <= 1.0:
		return true
	# Use a world-distance tolerance at thin triangle edges, not an arbitrary
	# barycentric tolerance that grows or shrinks with the triangle altitude.
	for pair in [[triangle.a, triangle.b], [triangle.b, triangle.c], [triangle.c, triangle.a]]:
		var start: Vector3 = pair[0]
		var edge: Vector3 = pair[1] - start
		var t := clampf((point - start).dot(edge) / maxf(edge.length_squared(), 0.000000000001), 0.0, 1.0)
		if point.distance_to(start + edge * t) <= tolerance:
			return true
	return false


func _line_starts(segments: Array[Dictionary]) -> PackedVector3Array:
	var result := PackedVector3Array()
	for segment in segments:
		if bool(segment.get("has_centerline", true)):
			result.append(segment.a)
	return result


func _distance_to_lines(point: Vector3, segments: Array[Dictionary]) -> float:
	var distance := INF
	for segment in segments:
		if not bool(segment.get("has_centerline", true)):
			continue
		var a: Vector3 = segment.a
		var edge: Vector3 = segment.b - a
		var t := clampf((point - a).dot(edge) / maxf(edge.length_squared(), 0.000000000001), 0.0, 1.0)
		distance = minf(distance, point.distance_to(a + edge * t))
	return distance


func _validate_connections(segments: Array[Dictionary], label: String, require_seam: bool = false) -> void:
	var seams := 0
	var connected := true
	for i in segments.size():
		var segment := segments[i]
		if not bool(segment.get("has_centerline", true)):
			continue
		# Every same-hit arm must connect to another piece of its network.
		# This detects detached pieces at a folded face edge.
		var has_neighbor := false
		for j in segments.size():
			if i == j or not bool(segments[j].get("has_centerline", true)) or int(segment.hit_id) != int(segments[j].hit_id):
				continue
			var other := segments[j]
			var touches := minf(minf(Vector3(segment.a).distance_to(other.a), Vector3(segment.a).distance_to(other.b)), minf(Vector3(segment.b).distance_to(other.a), Vector3(segment.b).distance_to(other.b))) < EPS
			has_neighbor = has_neighbor or touches
			if touches and Vector3(segment.normal).dot(other.normal) < 0.99:
				seams += 1
		connected = connected and has_neighbor
	_check(connected, label + ": wrapped centerlines have no isolated pieces")
	if require_seam:
		_check(seams > 0, label + ": near-edge cracks meet exactly across real noncoplanar face edges at their original scale")


func _validate_light(chunk: Chunk, segments: Array[Dictionary], label: String) -> void:
	var rays: Array = chunk.light_node.get("_rays")
	var eligible := 0
	for segment in segments:
		if bool(segment.get("has_centerline", true)) and Vector3(segment.a).distance_squared_to(segment.b) > 0.00000001 and float(segment.width) > 0.0:
			eligible += 1
	_check(rays.size() == eligible, label + ": exactly one light sheet per centerline, none for bank-only spill")
	var mapped := true
	var outward := true
	var transformed := true
	var transform := chunk.mesh_instance.global_transform
	for ray: Dictionary in rays:
		var index := int(ray.source_index)
		if index < 0 or index >= segments.size():
			mapped = false
			continue
		var source := segments[index]
		var normal: Vector3 = source.normal
		mapped = mapped and bool(source.has_centerline) and Vector3(ray.source_a).distance_to(source.a) < EPS and Vector3(ray.source_b).distance_to(source.b) < EPS
		var expected := (Vector3(source.a) + Vector3(source.b) + (Vector3(ray.offset_a) + Vector3(ray.offset_b)) * 0.018) * 0.5
		mapped = mapped and Vector3(ray.origin).distance_to(expected) < EPS and Vector3(ray.normal).dot(normal) > 0.999
		outward = outward and Vector3(ray.direction).dot(normal) > 0.0
		var world_normal := (transform.basis.inverse().transposed() * normal).normalized()
		var world_direction := (transform.basis * Vector3(ray.direction)).normalized()
		transformed = transformed and world_direction.dot(world_normal) > 0.0 and chunk.light_node.to_global(ray.origin).distance_to(transform * expected) < EPS
	_check(mapped, label + ": beam roots coincide with the full actual crack segment")
	_check(outward and transformed, label + ": all sheets escape their own face after nonuniform scale and recoil")


func _validate_idle_and_fatal(chunk: Chunk, target: Vector3, label: String) -> void:
	var dark: MeshInstance3D = chunk.get("_crack_mesh")
	var dark_mesh := dark.mesh
	var children: Array[MeshInstance3D] = []
	var light_meshes: Array[Mesh] = []
	for child in chunk.light_node.get_children():
		if child is MeshInstance3D:
			children.append(child)
			light_meshes.append(child.mesh)
	var changes := [0]
	dark_mesh.changed.connect(func(): changes[0] += 1)
	for frame in 40:
		chunk._process(0.016)
		chunk.light_node.call("_process", 0.016)
	var stable := dark.mesh == dark_mesh and int(changes[0]) == 0
	for i in children.size():
		stable = stable and children[i].mesh == light_meshes[i]
	_check(stable, label + ": idle/recoil animates existing meshes without rebuilding them")
	_check(chunk.hit(chunk.health, chunk.mesh_instance.to_global(target)), label + ": final contact destroys the host")
	_check(dark.mesh == dark_mesh and int(changes[0]) == 0, label + ": lethal damage does not upload a replacement dark mesh")
	var no_fatal_upload := true
	for i in children.size():
		no_fatal_upload = no_fatal_upload and (children[i].mesh == null or children[i].mesh == light_meshes[i])
	_check(no_fatal_upload and not chunk.light_node.visible, label + ": final light updates provenance without a new mesh upload")
	var fragments := chunk.build_fracture_fragments()
	_check(fragments.size() >= 2, label + ": actual side/front/rear damage still creates a nonempty solid fracture")
	_check(not chunk.get_visible_crack_segments().is_empty(), label + ": canonical fracture chart remains available")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)
