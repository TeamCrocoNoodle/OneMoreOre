extends "res://tests/validate_crack_wrap.gd"
## Independent clipping/area checks for the render-patch optimization, and
## cache invalidation against a freshly configured surface on every mutation.


func _run() -> void:
	var cube := _cube()
	var wrapper = Wrap.new()
	wrapper.configure(cube, Vector3.ZERO)
	var front: Dictionary = wrapper.get_surface_hit(Vector3(0.0, 0.0, 1.0))
	var face: int = front.face_id
	var polygon: PackedVector3Array = wrapper.get_face_polygon(face)
	_check(polygon.size() == 4 and absf(_polygon_area(polygon) - 4.0) < EPS, "Convex face cache removes only the internal triangulation diagonal")
	_check(wrapper.surface_offset(Vector3(0.2, 0.1, 1.0), face).distance_to(Vector3.BACK) < EPS, "Interior displacement is the true face normal")
	_check(wrapper.surface_offset(Vector3(1.0, 0.1, 1.0), face).distance_to(Vector3(1.0, 0.0, 1.0)) < EPS, "Crease displacement is the shared two-face miter")
	_check(wrapper.surface_offset(Vector3(1.0, 1.0, 1.0), face).distance_to(Vector3.ONE) < EPS, "Vertex displacement clears all three incident cube faces")
	var right: Dictionary = wrapper.get_surface_hit(Vector3(1.0, 0.1, 0.0))
	_check(wrapper.surface_offset(Vector3(1.0, 0.1, 1.0), face) == wrapper.surface_offset(Vector3(1.0, 0.1, 1.0), right.face_id), "Both sides of a crease share the identical offset")
	var segments: Array[Dictionary] = [
		_segment(Vector3.ZERO, Vector3(1.4, 0.12, 0.0), Vector3.BACK, 0.1, 0.08, 11),
		_segment(Vector3(1.4, 0.12, 0.0), Vector3(2.5, -0.2, 0.0), Vector3.BACK, 0.08, 0.0, 11),
		_segment(Vector3.ZERO, Vector3(-0.2, 0.75, 0.0), Vector3.BACK, 0.07, 0.0, 11),
	]
	var anchors := {11: {"point": Vector3(-0.3, 0.1, 1.0), "reference": Vector3.ZERO}}
	var raw: Array[Dictionary] = wrapper.wrap(segments, anchors, Vector3.BACK, 1.0)
	_validate_coalesced(wrapper, raw, "Cube zigzag")
	_check(wrapper.coalesce(raw).size() < raw.size(), "Coplanar triangle subdivision creates fewer render patches")
	for change in 8:
		match change:
			1: segments[1] = _segment(segments[1].a, Vector3(2.4, -0.1, 0.0), Vector3.BACK, 0.08, 0.0, 11)
			2: anchors[11].point = Vector3(1.0, 0.25, 0.3)
			3: anchors[11].reference = Vector3(0.04, -0.1, 0.0)
			4: segments[0].width_a = 0.15; segments[0].side_a *= 1.5
		var axis := Vector3.UP if change == 5 else Vector3.BACK
		var reach := 1.25 if change == 6 else 1.0
		var mesh := _cube() if change != 7 else _scaled_cube(Vector3(0.8, 0.9, 1.1))
		if change == 7:
			wrapper.configure(mesh, Vector3.ZERO)
		var fresh = Wrap.new()
		fresh.configure(mesh, Vector3.ZERO)
		var cached: Array[Dictionary] = wrapper.wrap(segments, anchors, axis, reach)
		var rebuilt: Array[Dictionary] = fresh.wrap(segments, anchors, axis, reach)
		_check(cached == rebuilt, "Cached walks exactly match a fresh surface after mutation %d" % change)
		_check(wrapper.coalesce(cached) == fresh.coalesce(rebuilt), "Coalescing remains deterministic after mutation %d" % change)
		_validate_coalesced(wrapper, cached, "Cache mutation %d" % change)

	# A connected but concave coplanar patch must not acquire its convex hull.
	var concave := PackedVector3Array([
		Vector3(0, 0, 1), Vector3(2, 0, 1), Vector3(2, 1, 1),
		Vector3(0, 0, 1), Vector3(2, 1, 1), Vector3(1, 1, 1),
		Vector3(0, 0, 1), Vector3(1, 1, 1), Vector3(1, 2, 1),
		Vector3(0, 0, 1), Vector3(1, 2, 1), Vector3(0, 2, 1),
	])
	wrapper.configure(concave, Vector3(0.5, 0.5, 0.0))
	var concave_face: Dictionary = wrapper.get_surface_hit(Vector3(0.5, 0.5, 1.0))
	_check(wrapper.get_face_polygon(concave_face.face_id).is_empty(), "A concave coplanar patch is never replaced by a convex hull")
	var outer := Geometry.build_layer(4.9, 0, 12873, 100, 0.86)
	for index in [0, 24, 57]:
		_validate_actual_coalesce(outer[index])
	print("CRACK_COALESCE_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _scaled_cube(scale: Vector3) -> PackedVector3Array:
	var points := _cube()
	for i in points.size():
		points[i] *= scale
	return points


func _validate_actual_coalesce(data: Dictionary) -> void:
	# Read actual vertex/index buffers directly, matching the precision of the
	# CPU data cached at spawn rather than get_faces' reconstructed positions.
	var triangles := PackedVector3Array()
	for surface in data.mesh.get_surface_count():
		var arrays: Array = data.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			triangles.append_array(vertices)
		else:
			for index in indices:
				triangles.append(vertices[index])
	var center := Vector3.ZERO
	for point in triangles:
		center += point
	center /= float(triangles.size())
	var wrapper = Wrap.new()
	wrapper.configure(triangles, center)
	var normal: Vector3 = data.direction
	var u := normal.cross(Vector3.UP).normalized()
	var v := normal.cross(u).normalized()
	var extent := 0.0
	for point: Vector3 in data.face_points:
		extent = maxf(extent, point.distance_to(data.face_center))
	var source: Array[Dictionary] = []
	var anchors := {31: {"point": data.face_center, "reference": Vector3.ZERO}}
	for branch in 3:
		var previous := Vector3.ZERO
		var angle := float(branch) * TAU / 3.0
		for step in 3:
			var reach := extent * float(step + 1) * 0.24
			var jog := angle + (0.18 if step == 1 else -0.07)
			var next := (u * cos(jog) + v * sin(jog)) * reach
			source.append(_segment(previous, next, normal, extent * 0.065, extent * (0.0 if step == 2 else 0.04), 31))
			previous = next
	var started := Time.get_ticks_usec()
	var raw: Array[Dictionary] = wrapper.wrap(source, anchors, normal, 3.2)
	var combined: Array[Dictionary] = wrapper.coalesce(raw)
	var first_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var repeated: Array[Dictionary] = wrapper.coalesce(wrapper.wrap(source, anchors, normal, 3.2))
	var second_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_check(combined == repeated, "Actual plate %d: repeated cached build is bitwise deterministic" % int(data.piece_index))
	_validate_coalesced(wrapper, raw, "Actual plate %d" % int(data.piece_index))
	print("CRACK_COALESCE_CASE plate=%d raw=%d merged=%d first_ms=%.3f cached_ms=%.3f" % [int(data.piece_index), raw.size(), combined.size(), first_ms, second_ms])


func _validate_coalesced(wrapper, raw: Array[Dictionary], label: String) -> void:
	var before := raw.duplicate(true)
	var output: Array[Dictionary] = wrapper.coalesce(raw)
	_check(raw == before and output.size() <= raw.size(), label + ": merging keeps source metadata unchanged and does not add patches")
	_check(absf(_surface_area(raw) - _surface_area(output)) < maxf(0.000005, _surface_area(raw) * 0.00025), label + ": total physical ribbon area is unchanged")
	_check(absf(_centerline_length(raw) - _centerline_length(output)) < 0.0001, label + ": total real centerline length is unchanged")
	var supported := true
	var centerlines := true
	var clip_domain := true
	for row in output:
		var normal: Vector3 = row.normal
		var u := normal.cross(Vector3.UP).normalized()
		if u.length_squared() < 0.1:
			u = normal.cross(Vector3.RIGHT).normalized()
		var v := normal.cross(u).normalized()
		var polygon := _project_2d(row.polygon, u, v)
		var clipped_area := 0.0
		var original_length := 0.0
		for old in raw:
			if int(old.face_id) != int(row.face_id) or int(old.source_index) != int(row.source_index):
				continue
			if not _ribbon_equal(old.ribbon, row.ribbon):
				continue
			for intersection in Geometry2D.intersect_polygons(polygon, _project_2d(old.polygon, u, v)):
				clipped_area += absf(_area_2d(intersection))
			if bool(old.has_centerline):
				original_length += Vector3(old.a).distance_to(old.b)
		var area := absf(_area_2d(polygon))
		# Native polygon intersection, independent of the helper's clipper.
		supported = supported and absf(clipped_area - area) <= maxf(0.000005, area * 0.0004)
		if bool(row.get("coalesced", false)) and bool(row.has_centerline):
			centerlines = centerlines and absf(original_length - Vector3(row.a).distance_to(row.b)) < 0.0001
		var domain := _project_2d(row.triangle, u, v)
		var domain_area := 0.0
		for intersection in Geometry2D.intersect_polygons(polygon, domain):
			domain_area += absf(_area_2d(intersection))
		clip_domain = clip_domain and absf(domain_area - area) <= maxf(0.000005, area * 0.0004)
	_check(supported, label + ": every combined polygon is covered by exactly its original source-ribbon clips")
	_check(centerlines, label + ": merged endpoints span exactly the original supported centerline interval")
	_check(clip_domain, label + ": all combined banks remain in their actual convex surface domain")


func _ribbon_equal(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.000031:
			return false
	return true


func _project_2d(polygon: PackedVector3Array, u: Vector3, v: Vector3) -> PackedVector2Array:
	var output := PackedVector2Array()
	for point in polygon:
		output.append(Vector2(point.dot(u), point.dot(v)))
	return output


func _area_2d(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in polygon.size():
		result += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return result * 0.5
