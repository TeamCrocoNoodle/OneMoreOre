extends SceneTree
## Independent union coverage and boundary checks for the crack cut-wall contours.

const Outline = preload("res://scripts/crack_outline.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const Gem = preload("res://scripts/gem.gd")
const EPS := 0.00005

var checks := 0
var failures := 0
var fixture := Node3D.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(fixture)
	var y: Array[Dictionary] = [
		_segment(Vector2.ZERO, Vector2(0.0, 1.0), 0.14, 0.0),
		_segment(Vector2.ZERO, Vector2(-0.9, -0.65), 0.14, 0.0),
		_segment(Vector2.ZERO, Vector2(0.9, -0.65), 0.14, 0.0),
	]
	_validate(y, Vector3.FORWARD, "Y junction", 1)
	var tee: Array[Dictionary] = [_segment(Vector2(-1.0, 0.0), Vector2(1.0, 0.0), 0.12, 0.12), _segment(Vector2(0.0, -1.0), Vector2.ZERO, 0.12, 0.12)]
	_validate(tee, Vector3.FORWARD, "T junction", 1)
	var cross: Array[Dictionary] = [_segment(Vector2(-1.0, -0.7), Vector2(1.0, 0.7), 0.11, 0.16), _segment(Vector2(-0.8, 1.0), Vector2(0.8, -1.0), 0.18, 0.08)]
	_validate(cross, Vector3.FORWARD, "X crossing", 1)
	var ring: Array[Dictionary] = []
	var corners := [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)]
	for i in 4:
		ring.append(_segment(corners[i], corners[(i + 1) % 4], 0.13, 0.13))
	_validate(ring, Vector3.FORWARD, "Closed crack preserves stone island", 2)
	var two_islands := ring.duplicate(true)
	two_islands.append(_segment(Vector2(-0.8, 0.0), Vector2(0.8, 0.0), 0.09, 0.09))
	_validate(two_islands, Vector3.FORWARD, "Two separate stone islands", 3)
	var separate := y.duplicate(true)
	separate.append(_segment(Vector2(2.0, 0.0), Vector2(2.7, 0.1), 0.1, 0.0))
	_validate(separate, Vector3.FORWARD, "Disconnected tapered branch", 2)
	var collinear: Array[Dictionary] = [_segment(Vector2(-1.0, 0.0), Vector2(0.5, 0.0), 0.13, 0.13), _segment(Vector2.ZERO, Vector2(1.0, 0.0), 0.13, 0.13)]
	collinear.append(collinear[0].duplicate(true))
	_validate(collinear, Vector3.FORWARD, "Coincident and collinear overlaps", 1)
	var touching: Array[Dictionary] = [_segment(Vector2(-1.0, 0.0), Vector2.ZERO, 0.15, 0.0), _segment(Vector2(1.0, 0.0), Vector2.ZERO, 0.15, 0.0)]
	_validate(touching, Vector3.FORWARD, "Two sharp tips touch at one point", 2)
	var transformed := cross.duplicate(true)
	var basis := Basis.from_euler(Vector3(0.83, -0.32, 0.27))
	var offset := Vector3(0.7, -1.8, 2.3)
	for segment in transformed:
		segment.a = basis * Vector3(segment.a) + offset
		segment.b = basis * Vector3(segment.b) + offset
		segment.side_a = basis * Vector3(segment.side_a)
		segment.side_b = basis * Vector3(segment.side_b)
	_validate(transformed, basis * Vector3.FORWARD, "Rotated and translated face", 1)
	var many: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 980127
	for i in 32:
		var from := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var to := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		many.append(_segment(from, to, rng.randf_range(0.008, 0.08), 0.0 if i % 4 == 0 else rng.randf_range(0.008, 0.08)))
	_validate(many, Vector3.FORWARD, "Thirty-two crossed tapered ribbons")
	var degenerate: Array[Dictionary] = [_segment(Vector2.ZERO, Vector2(1.0, 0.0), 0.0, 0.0)]
	_check(Outline.build([], Vector3.FORWARD).is_empty() and Outline.build(degenerate, Vector3.FORWARD).is_empty(), "Empty or zero-area ribbons have no cut-wall contours")
	for index in [0, 24, 57, 86]:
		var data: Dictionary = Geometry.build_layer(4.9, 0, 12873, 100, 0.86)[index]
		var chunk := Chunk.new()
		fixture.add_child(chunk)
		chunk.configure(data, 0)
		chunk.set_process(false)
		var gem := Gem.new()
		gem.configure(Gem.ANCIENT, 0)
		fixture.add_child(gem)
		chunk.configure_gem_cover(gem, 5)
		for strike in 16:
			var edge := int(float(strike % 3) * chunk.face_points.size() / 3.0)
			var middle: Vector3 = (chunk.face_points[edge] + chunk.face_points[(edge + 1) % chunk.face_points.size()]) * 0.5
			var point: Vector3 = chunk.face_center.lerp(middle, 0.52)
			chunk.hit(1.0, chunk.mesh_instance.to_global(point))
		_validate(chunk.get_visible_crack_segments(), chunk.direction, "Actual sixteen-hit face %d" % index)
	var jitter_chunk := Chunk.new()
	fixture.add_child(jitter_chunk)
	jitter_chunk.configure(Geometry.build_layer(2.6, 0, 4821)[0], 0)
	jitter_chunk.set_process(false)
	var jitter_gem := Gem.new()
	jitter_gem.configure(Gem.ANCIENT, 0)
	fixture.add_child(jitter_gem)
	jitter_chunk.configure_gem_cover(jitter_gem, 5)
	var first_point: Vector3 = jitter_chunk.face_center.lerp(jitter_chunk.face_points[0], 0.5)
	var second_point: Vector3 = jitter_chunk.face_center.lerp(jitter_chunk.face_points[floori(jitter_chunk.face_points.size() * 0.5)], 0.5)
	jitter_chunk.hit(0.2, jitter_chunk.mesh_instance.to_global(first_point))
	jitter_chunk.hit(0.2, jitter_chunk.mesh_instance.to_global(second_point))
	var tangent := (second_point - first_point).normalized()
	var bitangent := jitter_chunk.direction.cross(tangent).normalized()
	for strike in 128:
		var point := second_point + tangent * float(strike % 7 - 3) * 0.001 + bitangent * float(strike % 5 - 2) * 0.001
		jitter_chunk.hit(0.002, jitter_chunk.mesh_instance.to_global(point))
	_validate(jitter_chunk.get_visible_crack_segments(), jitter_chunk.direction, "Actual 128 nearby hits and millimetre connectors")
	fixture.free()
	print("CRACK_OUTLINE_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _segment(a: Vector2, b: Vector2, width_a: float, width_b: float) -> Dictionary:
	var from := Vector3(a.x, a.y, 0.0)
	var to := Vector3(b.x, b.y, 0.0)
	var side := Vector3.FORWARD.cross(to - from).normalized()
	return {"a": from, "b": to, "side_a": side * width_a, "side_b": side * width_b, "width_a": width_a, "width_b": width_b, "width": maxf(width_a, width_b), "hit_id": 1, "impact": from}


func _validate(segments: Array[Dictionary], normal: Vector3, label: String, expected_contours: int = -1) -> void:
	var original := segments.duplicate(true)
	var start := Time.get_ticks_usec()
	var contours: Array[PackedVector3Array] = Outline.build(segments, normal)
	print("CRACK_OUTLINE_CASE %s segments=%d contours=%d build_ms=%.3f" % [label, segments.size(), contours.size(), float(Time.get_ticks_usec() - start) / 1000.0])
	_check(not contours.is_empty() and (expected_contours < 0 or contours.size() == expected_contours), label + ": all expected exterior and hole contours exist")
	_check(segments == original, label + ": source crack data is unchanged")
	var u := (Vector3(segments[0].b) - Vector3(segments[0].a)).normalized()
	var v := normal.cross(u).normalized()
	var origin: Vector3 = segments[0].a
	var source_polygons: Array[PackedVector2Array] = []
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for segment in segments:
		var polygon := PackedVector2Array()
		for point: Vector3 in [Vector3(segment.a) - Vector3(segment.side_a), Vector3(segment.a) + Vector3(segment.side_a), Vector3(segment.b) + Vector3(segment.side_b), Vector3(segment.b) - Vector3(segment.side_b)]:
			var projected := Vector2((point - origin).dot(u), (point - origin).dot(v))
			polygon.append(projected)
			bounds = bounds.expand(projected)
		source_polygons.append(polygon)
	var polygons: Array[PackedVector2Array] = []
	var valid := true
	var exposed := true
	var supported := true
	var directed_edges: Dictionary = {}
	for contour in contours:
		var polygon := PackedVector2Array()
		valid = valid and contour.size() >= 3
		for point in contour:
			valid = valid and point.is_finite() and absf((point - origin).dot(normal)) < EPS
			polygon.append(Vector2((point - origin).dot(u), (point - origin).dot(v)))
		polygons.append(polygon)
		valid = valid and absf(_area(polygon)) > 0.00000001
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var delta := b - a
			valid = valid and delta.length() > 0.000005
			var midpoint := (a + b) * 0.5
			var inward := Vector2(-delta.y, delta.x).normalized()
			exposed = exposed and _inside_any(midpoint + inward * EPS, source_polygons) and not _inside_any(midpoint - inward * EPS, source_polygons)
			supported = supported and _on_source_edge(a, b, source_polygons)
			var key := str(a.snapped(Vector2.ONE * EPS)) + "/" + str(b.snapped(Vector2.ONE * EPS))
			valid = valid and not directed_edges.has(key)
			directed_edges[key] = true
	_check(valid, label + ": contours are finite, planar and closed without repeated directed edges")
	_check(exposed, label + ": every cut wall has crack interior on its left and intact stone on its right")
	_check(supported, label + ": every contour edge lies on an original tapered or mitered ribbon boundary")
	var matches := true
	var sampled := 0
	for x in 59:
		for y in 53:
			var point := bounds.position + bounds.size * Vector2((x + 0.371) / 59.0, (y + 0.619) / 53.0)
			if _near_edges(point, source_polygons) or _near_edges(point, polygons):
				continue
			var winding := 0
			for polygon in polygons:
				if Geometry2D.is_point_in_polygon(point, polygon):
					winding += 1 if _area(polygon) > 0.0 else -1
			matches = matches and winding == (1 if _inside_any(point, source_polygons) else 0)
			sampled += 1
	_check(matches and sampled > 1000, label + ": independent samples match the full ribbon union without filling holes or adding internal walls")
	var reordered := segments.duplicate(true)
	reordered.reverse()
	_check(contours == Outline.build(reordered, normal), label + ": reversing source order produces exactly the same contours")
	if reordered.size() > 2:
		reordered.push_front(reordered.pop_back())
	_check(contours == Outline.build(reordered, normal), label + ": another source order preserves deterministic contour geometry")
	for segment in reordered:
		var a: Vector3 = segment.a
		var side_a: Vector3 = segment.side_a
		segment.a = segment.b
		segment.b = a
		segment.side_a = -Vector3(segment.side_b)
		segment.side_b = -side_a
	_check(contours == Outline.build(reordered, normal), label + ": reversing ribbon parameterization preserves directed exterior and hole contours")
	for segment in segments:
		if float(segment.width_b) <= 0.000001:
			var tip: Vector3 = segment.b
			# A tip hidden inside another ribbon is correctly absent from the
			# outside. Exposed sharp tips must survive without a rounded cap.
			var direction := (Vector3(segment.b) - Vector3(segment.a)).normalized()
			var just_beyond := Vector2((tip + direction * EPS * 3.0 - origin).dot(u), (tip + direction * EPS * 3.0 - origin).dot(v))
			if not _inside_any(just_beyond, source_polygons):
				var distance := INF
				for contour in contours:
					for point in contour:
						distance = minf(distance, point.distance_to(tip))
				_check(distance < EPS, label + ": an exposed zero-width branch retains its exact sharp tip")


func _inside_any(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func _near_edges(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		for i in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])) < EPS:
				return true
	return false


func _on_source_edge(a: Vector2, b: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		for i in polygon.size():
			var first := polygon[i]
			var second := polygon[(i + 1) % polygon.size()]
			if a.distance_to(Geometry2D.get_closest_point_to_segment(a, first, second)) < EPS and b.distance_to(Geometry2D.get_closest_point_to_segment(b, first, second)) < EPS:
				return true
	return false


func _area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in polygon.size():
		result += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return result * 0.5


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CRACK_OUTLINE_CHECK_FAILED: " + message)
