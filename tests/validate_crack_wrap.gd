extends SceneTree
## Independent surface, distance, and seam checks for geodesic crack ribbons.

const Wrap = preload("res://scripts/crack_wrap.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const EPS := 0.0002

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cube := _cube()
	var wrapper = Wrap.new()
	wrapper.configure(cube, Vector3.ZERO)
	_check(wrapper.wrap([], {}, Vector3.BACK).is_empty(), "An empty crack set produces no surface ribbons")
	var front_hit: Dictionary = wrapper.get_surface_hit(Vector3(0.2, 0.1, 1.0))
	_check(wrapper.is_surface_edge(Vector3(1.0, -0.5, 1.0), Vector3(1.0, 0.5, 1.0), front_hit.face_id), "A real front/side crease is identified as a surface edge")
	_check(not wrapper.is_surface_edge(Vector3(-0.5, -0.5, 1.0), Vector3(0.5, 0.5, 1.0), front_hit.face_id), "A coplanar triangulation diagonal is not a physical surface edge")
	for entry: Dictionary in [
		{"point": Vector3(0.23, 0.17, 1.0), "normal": Vector3.BACK, "label": "front"},
		{"point": Vector3(1.0, 0.17, 0.23), "normal": Vector3.RIGHT, "label": "right side"},
		{"point": Vector3(-1.0, 0.17, 0.23), "normal": Vector3.LEFT, "label": "left side"},
		{"point": Vector3(0.23, 0.17, -1.0), "normal": Vector3.FORWARD, "label": "back"},
	]:
		var hit: Dictionary = wrapper.get_surface_hit(entry.point)
		_check(_valid_hit(hit, cube, entry.point, entry.normal), "Cube %s: nearest surface query retains the real struck face" % entry.label)
		var source: Array[Dictionary] = [_segment(Vector3.ZERO, Vector3(0.32, 0.0, 0.0), Vector3.BACK, 0.07, 0.025, 7)]
		var anchors := {7: {"point": entry.point, "reference": Vector3.ZERO}}
		var output: Array[Dictionary] = _validate(wrapper, cube, Vector3.ZERO, source, anchors, Vector3.BACK, 1.0, "Cube " + str(entry.label))
		_check(_has_centerline_endpoint(output, 0, entry.point), "Cube %s: the visible crack begins at the actual strike" % entry.label)
		_check(absf(_centerline_length(output) - 0.32) < EPS, "Cube %s: surface transport preserves the short path length" % entry.label)
		_check(absf(_surface_area(output) - 0.32 * 0.095) < EPS, "Cube %s: clipping preserves tapered ribbon area" % entry.label)

	var anchor := Vector3(-0.6, 0.217, 1.0)
	var long_source: Array[Dictionary] = [_segment(Vector3.ZERO, Vector3(4.3, 0.0, 0.0), Vector3.BACK, 0.09, 0.09, 12)]
	var long_anchors := {12: {"point": anchor, "reference": Vector3.ZERO}}
	for reach_scale: float in [0.5, 1.0, 1.25]:
		var output := _validate(wrapper, cube, Vector3.ZERO, long_source, long_anchors, Vector3.BACK, reach_scale, "Cube long path, reach %.2f" % reach_scale)
		var expected_length := 4.3 * reach_scale
		var expected_end := Vector3(1.0, anchor.y, 1.0 - (expected_length - 1.6)) if expected_length < 3.6 else Vector3(1.0 - (expected_length - 3.6), anchor.y, -1.0)
		_check(_has_centerline_endpoint(output, 0, anchor) and _has_centerline_endpoint(output, 0, expected_end), "Long path %.2f: unfolded cube has the analytically expected endpoints" % reach_scale)
		_check(absf(_centerline_length(output) - expected_length) < EPS * 4.0, "Long path %.2f: distance continues across successive faces" % reach_scale)
		_check(absf(_surface_area(output) - expected_length * 0.18) < EPS * 4.0, "Long path %.2f: reach changes distance without widening the physical ribbon" % reach_scale)
		_check(_normal_count(output) >= (2 if reach_scale < 0.8 else 3), "Long path %.2f: actual side and back faces receive the continuing crack" % reach_scale)
		_check(_seam_covered(output, Vector3.BACK, 1.0, 1.0, anchor.y - 0.09, anchor.y + 0.09) and _seam_covered(output, Vector3.RIGHT, 1.0, 1.0, anchor.y - 0.09, anchor.y + 0.09), "Long path %.2f: both banks meet exactly on the front/side edge" % reach_scale)
		if reach_scale >= 0.8:
			_check(_seam_covered(output, Vector3.FORWARD, 1.0, -1.0, anchor.y - 0.09, anchor.y + 0.09) and _seam_covered(output, Vector3.RIGHT, 1.0, -1.0, anchor.y - 0.09, anchor.y + 0.09), "Long path %.2f: both banks also meet at the side/back edge" % reach_scale)

	var bank_anchor := Vector3(0.97, 0.15, 1.0)
	var bank_source: Array[Dictionary] = [_segment(Vector3.ZERO, Vector3(0.0, 0.45, 0.0), Vector3.BACK, 0.11, 0.11, 19)]
	var bank_anchors := {19: {"point": bank_anchor, "reference": Vector3.ZERO}}
	var bank_output := _validate(wrapper, cube, Vector3.ZERO, bank_source, bank_anchors, Vector3.BACK, 1.0, "Ribbon bank crossing an edge")
	var has_side_bank := false
	var centerline_stays_front := true
	for row in bank_output:
		if Vector3(row.normal).dot(Vector3.RIGHT) > 0.999:
			has_side_bank = has_side_bank or not bool(row.get("has_centerline", true))
		if bool(row.get("has_centerline", true)):
			centerline_stays_front = centerline_stays_front and Vector3(row.normal).dot(Vector3.BACK) > 0.999
	_check(has_side_bank and centerline_stays_front, "A bank reaches the adjacent face even when its centerline never crosses the edge")
	_check(absf(_surface_area(bank_output) - 0.45 * 0.22) < EPS * 3.0, "Bank-only surface clips preserve the full physical ribbon area")
	_check(_seam_covered(bank_output, Vector3.BACK, 1.0, 1.0, 0.15, 0.6) and _seam_covered(bank_output, Vector3.RIGHT, 1.0, 1.0, 0.15, 0.6), "Bank-only neighboring polygons share the exact same edge interval")

	var zigzag: Array[Dictionary] = [
		_segment(Vector3.ZERO, Vector3(0.65, 0.14, 0.0), Vector3.BACK, 0.045, 0.065, 23),
		_segment(Vector3(0.65, 0.14, 0.0), Vector3(1.2, -0.1, 0.0), Vector3.BACK, 0.065, 0.05, 23),
		_segment(Vector3(1.2, -0.1, 0.0), Vector3(2.3, 0.16, 0.0), Vector3.BACK, 0.05, 0.0, 23),
	]
	# A second strike has a separate chart origin and an actual rear-face anchor.
	zigzag.append(_segment(Vector3(-0.4, 0.3, 0.0), Vector3(-0.12, 0.3, 0.0), Vector3.BACK, 0.04, 0.0, 31))
	var zigzag_anchors := {23: {"point": Vector3(0.0, 0.11, 1.0), "reference": Vector3.ZERO}, 31: {"point": Vector3(0.2, -0.2, -1.0), "reference": Vector3(-0.4, 0.3, 0.0)}}
	var zigzag_output := _validate(wrapper, cube, Vector3.ZERO, zigzag, zigzag_anchors, Vector3.BACK, 1.0, "Angular path with independent front/back strikes")
	for i in range(2):
		_check(_centerlines_join(zigzag_output, i, i + 1), "Angular path: consecutive source sections %d/%d meet on the actual surface" % [i, i + 1])
	_check(_has_centerline_endpoint(zigzag_output, 3, zigzag_anchors[31].point), "A later rear-face strike starts at its own physical anchor")
	_check(absf(_centerline_length(zigzag_output) - _source_length(zigzag)) < EPS * 8.0, "Transport keeps all original zigzag distances")

	var outer := Geometry.build_layer(4.9, 0, 12873, 100, 0.86)
	var inner := Geometry.build_layer(1.0, 5, 61477, 14, 0.3)
	for data: Dictionary in [outer[0], outer[57], inner[0], inner[9]]:
		_validate_rock(data)
	print("CRACK_WRAP_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _validate_rock(data: Dictionary) -> void:
	var triangles: PackedVector3Array = data.mesh.get_faces()
	var interior := Vector3.ZERO
	for point in triangles:
		interior += point
	interior /= float(triangles.size())
	var normal: Vector3 = data.direction
	var tangent := normal.cross(Vector3.UP).normalized()
	if tangent.length_squared() < 0.1:
		tangent = normal.cross(Vector3.RIGHT).normalized()
	var extent := 0.0
	for point: Vector3 in data.face_points:
		extent = maxf(extent, point.distance_to(data.face_center))
	var wrapper = Wrap.new()
	wrapper.configure(triangles, interior)
	var chosen := {"front": {"index": -1, "score": -INF}, "side": {"index": -1, "score": -INF}, "back": {"index": -1, "score": -INF}}
	for triangle in int(triangles.size() / 3):
		var actual_normal := _triangle_normal(triangles, triangle, interior)
		var score := actual_normal.dot(normal)
		for label: String in chosen:
			var candidate := score if label == "front" else (-score if label == "back" else -absf(score))
			if candidate > float(chosen[label].score):
				chosen[label] = {"index": triangle, "score": candidate}
	for label: String in chosen:
		var index: int = chosen[label].index
		var anchor := (triangles[index * 3] + triangles[index * 3 + 1] + triangles[index * 3 + 2]) / 3.0
		var expected_normal := _triangle_normal(triangles, index, interior)
		var name := "Actual rock %d/%d %s" % [int(data.seed), int(data.piece_index), label]
		_check(_valid_hit(wrapper.get_surface_hit(anchor), triangles, anchor, expected_normal), name + ": query selects the actual struck triangle")
		var source: Array[Dictionary] = [_segment(Vector3.ZERO, tangent * extent * 1.35, normal, extent * 0.04, extent * 0.018, 43)]
		var output := _validate(wrapper, triangles, interior, source, {43: {"point": anchor, "reference": Vector3.ZERO}}, normal, 1.0, name)
		_check(_has_centerline_endpoint(output, 0, anchor), name + ": crack begins at the true front/side/rear strike")
		_check(absf(_centerline_length(output) - _source_length(source)) < EPS * 12.0, name + ": mesh-edge crossings preserve requested travel")
		_check(_normal_count(output) >= 2, name + ": crack reaches a genuinely different surface plane")


func _validate(wrapper, triangles: PackedVector3Array, interior: Vector3, source: Array[Dictionary], anchors: Dictionary, normal: Vector3, reach_scale: float, label: String) -> Array[Dictionary]:
	var source_before := source.duplicate(true)
	var anchors_before := anchors.duplicate(true)
	var started := Time.get_ticks_usec()
	var output: Array[Dictionary] = wrapper.wrap(source, anchors, normal, reach_scale)
	print("CRACK_WRAP_CASE %s source=%d clips=%d build_ms=%.3f" % [label, source.size(), output.size(), float(Time.get_ticks_usec() - started) / 1000.0])
	_check(not output.is_empty() and output.size() <= source.size() * triangles.size() / 3, label + ": output has a bounded, nonempty set of surface clips")
	_check(source == source_before and anchors == anchors_before, label + ": transport leaves all authoritative source and strike data unchanged")
	_check(output == wrapper.wrap(source, anchors, normal, reach_scale), label + ": the same cached surface produces deterministic clips")
	var valid := true
	var on_triangle := true
	var outward := true
	var provenance := true
	var centerline_valid := true
	var offsets_valid := true
	var shared_offsets_valid := true
	var shared_vertices := {}
	var sources_seen := {}
	for row in output:
		if not row.has_all(["a", "b", "normal", "face_id", "triangle_id", "source_index", "reference_a", "reference_b", "polygon", "has_centerline", "polygon_offsets", "offset_a", "offset_b"]):
			valid = false
			continue
		var polygon: PackedVector3Array = row.polygon
		var face_normal: Vector3 = row.normal
		var triangle_id: int = row.triangle_id
		var source_index: int = row.source_index
		valid = valid and polygon.size() >= 3 and face_normal.is_finite() and absf(face_normal.length() - 1.0) < EPS and _polygon_area(polygon) > 0.000000001
		if triangle_id < 0 or triangle_id >= triangles.size() / 3 or source_index < 0 or source_index >= source.size():
			valid = false
			continue
		var ta := triangles[triangle_id * 3]
		var tb := triangles[triangle_id * 3 + 1]
		var tc := triangles[triangle_id * 3 + 2]
		for point in polygon:
			valid = valid and point.is_finite()
			if not _inside_triangle(point, ta, tb, tc):
				var metrics := _triangle_coordinates(point, ta, tb, tc)
				print("CRACK_WRAP_OUTSIDE %s triangle=%d point=%s plane=%.9f u=%.9f v=%.9f a=%s b=%s c=%s" % [label, triangle_id, point, metrics.x, metrics.y, metrics.z, ta, tb, tc])
			on_triangle = on_triangle and _inside_triangle(point, ta, tb, tc)
		outward = outward and face_normal.dot(_triangle_normal(triangles, triangle_id, interior)) > 0.999
		provenance = provenance and _on_segment(row.reference_a, source[source_index].a, source[source_index].b) and _on_segment(row.reference_b, source[source_index].a, source[source_index].b)
		if row.has("hit_id"):
			provenance = provenance and int(row.hit_id) == int(source[source_index].hit_id)
		if bool(row.has_centerline):
			sources_seen[source_index] = true
			centerline_valid = centerline_valid and Vector3(row.a).is_finite() and Vector3(row.b).is_finite() and _inside_triangle(row.a, ta, tb, tc) and _inside_triangle(row.b, ta, tb, tc)
			centerline_valid = centerline_valid and Vector3(row.a).distance_to(row.b) > 0.0000001
			centerline_valid = centerline_valid and absf(Vector3(row.a).distance_to(row.b) - Vector3(row.reference_a).distance_to(row.reference_b) * reach_scale) < EPS * 3.0
		if row.has("polygon_offsets"):
			var offsets: PackedVector3Array = row.polygon_offsets
			offsets_valid = offsets_valid and offsets.size() == polygon.size()
			for offset in offsets:
				offsets_valid = offsets_valid and offset.is_finite() and offset.dot(face_normal) > 0.9
			for i in mini(offsets.size(), polygon.size()):
				var point := polygon[i]
				var key := Vector3i(roundi(point.x / EPS), roundi(point.y / EPS), roundi(point.z / EPS))
				if shared_vertices.has(key):
					for existing: Dictionary in shared_vertices[key]:
						if point.distance_to(existing.point) < EPS and face_normal.dot(existing.normal) < 0.999:
							if offsets[i].distance_to(existing.offset) >= EPS * 5.0:
								print("CRACK_WRAP_OFFSET %s point=%s other=%s point_distance=%.9f offset=%s other_offset=%s offset_distance=%.9f" % [label, point, existing.point, point.distance_to(existing.point), offsets[i], existing.offset, offsets[i].distance_to(existing.offset)])
							shared_offsets_valid = shared_offsets_valid and offsets[i].distance_to(existing.offset) < EPS * 5.0
				else:
					shared_vertices[key] = []
				shared_vertices[key].append({"point": point, "normal": face_normal, "offset": offsets[i]})
	_check(valid, label + ": every clip has a complete finite nondegenerate surface record")
	_check(on_triangle, label + ": every polygon vertex lies inside its exact source mesh triangle")
	_check(outward, label + ": every clip uses the actual outward surface normal")
	_check(provenance and sources_seen.size() == source.size(), label + ": every source section survives with reference coordinates on the original centerline")
	_check(centerline_valid, label + ": centerline clips lie on their real triangles with positive length")
	_check(offsets_valid, label + ": shared-surface normal offsets remain finite and face-facing")
	_check(shared_offsets_valid, label + ": coincident banks on different faces receive the same physical render offset")
	return output


func _valid_hit(hit: Dictionary, triangles: PackedVector3Array, expected_point: Vector3, expected_normal: Vector3) -> bool:
	if not hit.has_all(["point", "normal", "face_id", "triangle_id"]):
		return false
	var triangle: int = hit.triangle_id
	return triangle >= 0 and triangle < triangles.size() / 3 and Vector3(hit.point).distance_to(expected_point) < EPS and Vector3(hit.normal).dot(expected_normal) > 0.999 and _inside_triangle(hit.point, triangles[triangle * 3], triangles[triangle * 3 + 1], triangles[triangle * 3 + 2])


func _segment(a: Vector3, b: Vector3, normal: Vector3, width_a: float, width_b: float, hit_id: int) -> Dictionary:
	var side := normal.cross(b - a).normalized()
	return {"a": a, "b": b, "width_a": width_a, "width_b": width_b, "width": maxf(width_a, width_b), "side_a": side * width_a, "side_b": side * width_b, "hit_id": hit_id, "impact": a}


func _cube() -> PackedVector3Array:
	var triangles := PackedVector3Array()
	for normal: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN]:
		var u := normal.cross(Vector3.UP).normalized()
		if u.length_squared() < 0.1:
			u = normal.cross(Vector3.RIGHT).normalized()
		var v := normal.cross(u).normalized()
		var a := normal - u - v
		var b := normal + u - v
		var c := normal + u + v
		var d := normal - u + v
		triangles.append_array(PackedVector3Array([a, b, c, a, c, d]))
	return triangles


func _triangle_normal(triangles: PackedVector3Array, triangle: int, interior: Vector3) -> Vector3:
	var a := triangles[triangle * 3]
	var b := triangles[triangle * 3 + 1]
	var c := triangles[triangle * 3 + 2]
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot((a + b + c) / 3.0 - interior) < 0.0:
		normal = -normal
	return normal


func _inside_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var coordinates := _triangle_coordinates(point, a, b, c)
	return absf(coordinates.x) <= EPS and coordinates.y >= -EPS * 3.0 and coordinates.z >= -EPS * 3.0 and coordinates.y + coordinates.z <= 1.0 + EPS * 3.0


func _triangle_coordinates(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b - a).cross(c - a).normalized()
	var v0 := b - a
	var v1 := c - a
	var v2 := point - a
	var denominator := v0.dot(v0) * v1.dot(v1) - v0.dot(v1) * v0.dot(v1)
	if absf(denominator) < 0.000000000001:
		return Vector3(INF, INF, INF)
	var u := (v1.dot(v1) * v2.dot(v0) - v0.dot(v1) * v2.dot(v1)) / denominator
	var v := (v0.dot(v0) * v2.dot(v1) - v0.dot(v1) * v2.dot(v0)) / denominator
	return Vector3(normal.dot(point - a), u, v)


func _on_segment(point: Vector3, a: Vector3, b: Vector3) -> bool:
	var delta := b - a
	if delta.length_squared() < 0.0000000001:
		return point.distance_to(a) < EPS
	var amount := (point - a).dot(delta) / delta.length_squared()
	return amount >= -EPS and amount <= 1.0 + EPS and point.distance_to(a + delta * clampf(amount, 0.0, 1.0)) < EPS


func _has_centerline_endpoint(output: Array[Dictionary], source_index: int, expected: Vector3) -> bool:
	for row in output:
		if int(row.get("source_index", -1)) == source_index and bool(row.get("has_centerline", true)) and (Vector3(row.a).distance_to(expected) < EPS * 2.0 or Vector3(row.b).distance_to(expected) < EPS * 2.0):
			return true
	return false


func _centerlines_join(output: Array[Dictionary], first: int, second: int) -> bool:
	for a in output:
		if int(a.source_index) != first or not bool(a.has_centerline):
			continue
		for b in output:
			if int(b.source_index) == second and bool(b.has_centerline) and Vector3(a.b).distance_to(b.a) < EPS * 2.0:
				return true
	return false


func _centerline_length(output: Array[Dictionary]) -> float:
	var total := 0.0
	for row in output:
		if bool(row.get("has_centerline", true)):
			total += Vector3(row.a).distance_to(row.b)
	return total


func _source_length(source: Array[Dictionary]) -> float:
	var total := 0.0
	for row in source:
		total += Vector3(row.a).distance_to(row.b)
	return total


func _surface_area(output: Array[Dictionary]) -> float:
	var total := 0.0
	for row in output:
		total += _polygon_area(row.polygon)
	return total


func _polygon_area(polygon: PackedVector3Array) -> float:
	var total := Vector3.ZERO
	for i in range(1, polygon.size() - 1):
		total += (polygon[i] - polygon[0]).cross(polygon[i + 1] - polygon[0])
	return total.length() * 0.5


func _normal_count(output: Array[Dictionary]) -> int:
	var normals: Array[Vector3] = []
	for row in output:
		if not bool(row.get("has_centerline", true)):
			continue
		var found := false
		for normal in normals:
			found = found or normal.dot(row.normal) > 0.999
		if not found:
			normals.append(row.normal)
	return normals.size()


func _seam_covered(output: Array[Dictionary], normal: Vector3, seam_x: float, seam_z: float, low: float, high: float) -> bool:
	var intervals: Array[Vector2] = []
	for row in output:
		if Vector3(row.normal).dot(normal) < 0.999:
			continue
		var polygon: PackedVector3Array = row.polygon
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if absf(a.x - seam_x) < EPS and absf(a.z - seam_z) < EPS and absf(b.x - seam_x) < EPS and absf(b.z - seam_z) < EPS and absf(a.y - b.y) > EPS:
				intervals.append(Vector2(minf(a.y, b.y), maxf(a.y, b.y)))
	if intervals.is_empty():
		return false
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var covered := low
	for interval in intervals:
		if interval.x > covered + EPS or interval.x < low - EPS or interval.y > high + EPS:
			return false
		covered = maxf(covered, interval.y)
	return absf(covered - high) < EPS


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CRACK_WRAP_CHECK_FAILED: " + message)
