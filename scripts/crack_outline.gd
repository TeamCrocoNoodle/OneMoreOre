class_name CrackOutline
extends RefCounted
## Exposed contours of the actual tapered crack ribbons, including stone islands.
## Directed edges keep the opened crack on their left in the face's local plane.

const EPS := 0.00001

var _normal := Vector3.FORWARD
var _u := Vector3.RIGHT
var _v := Vector3.UP
var _plane := 0.0
var _polygons: Array[Dictionary] = []
var _vertices: Array[Vector2] = []
var _vertex_ids: Dictionary = {}


static func build(segments: Array[Dictionary], normal: Vector3) -> Array[PackedVector3Array]:
	var builder: RefCounted = (load("res://scripts/crack_outline.gd") as GDScript).new()
	return builder._build(segments, normal)


func _build(segments: Array[Dictionary], normal: Vector3) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	if segments.is_empty() or not normal.is_finite() or normal.length_squared() < 0.5:
		return result
	_normal = normal.normalized()
	_u = _normal.cross(Vector3.UP).normalized()
	if _u.length_squared() < 0.1:
		_u = _normal.cross(Vector3.RIGHT).normalized()
	_v = _normal.cross(_u).normalized()
	var plane_anchor := Vector3(INF, INF, INF)
	for segment in segments:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		if not a.is_finite() or not b.is_finite():
			continue
		var side := _normal.cross(b - a).normalized() * float(segment.get("width", 0.0))
		var side_a: Vector3 = segment.get("side_a", side)
		var side_b: Vector3 = segment.get("side_b", side)
		if not side_a.is_finite() or not side_b.is_finite():
			continue
		# Surface wrapping clips a ribbon into convex facet polygons. Keep those
		# exact banks; a reconstructed symmetric quad would spill across edges.
		var points: PackedVector3Array = segment.get("polygon", PackedVector3Array([a - side_a, a + side_a, b + side_b, b - side_b]))
		var polygon := PackedVector2Array()
		for point in points:
			if point.x < plane_anchor.x or (point.x == plane_anchor.x and (point.y < plane_anchor.y or (point.y == plane_anchor.y and point.z < plane_anchor.z))):
				plane_anchor = point
			var projected := Vector2(point.dot(_u), point.dot(_v))
			if polygon.is_empty() or polygon[polygon.size() - 1].distance_squared_to(projected) > EPS * EPS:
				polygon.append(projected)
		if polygon.size() > 1 and polygon[0].distance_squared_to(polygon[polygon.size() - 1]) <= EPS * EPS:
			polygon.remove_at(polygon.size() - 1)
		if polygon.size() < 3 or absf(_area(polygon)) <= EPS * EPS:
			continue
		if _area(polygon) < 0.0:
			polygon.reverse()
		polygon = _rotate_to_first(polygon)
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		var planes := PackedVector3Array()
		for i in polygon.size():
			bounds = bounds.expand(polygon[i])
			var delta := polygon[(i + 1) % polygon.size()] - polygon[i]
			var inward := Vector2(-delta.y, delta.x).normalized()
			planes.append(Vector3(inward.x, inward.y, inward.dot(polygon[i])))
		_polygons.append({"points": polygon, "bounds": bounds.grow(EPS * 2.0), "planes": planes})
	if _polygons.is_empty():
		return result
	_plane = plane_anchor.dot(_normal)
	_polygons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _polygon_before(a["points"], b["points"]))
	var lines: Array[Dictionary] = []
	for polygon_index in _polygons.size():
		var polygon: PackedVector2Array = _polygons[polygon_index]["points"]
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			lines.append({"a": a, "b": b, "polygon": polygon_index, "cuts": [0.0, 1.0], "bounds": Rect2(a, Vector2.ZERO).expand(b).grow(EPS)})
	_split_intersections(lines)
	var exposed: Dictionary = {}
	for line in lines:
		var a: Vector2 = line["a"]
		var b: Vector2 = line["b"]
		var delta := b - a
		var left := Vector2(-delta.y, delta.x).normalized()
		var cuts: Array = line["cuts"]
		cuts.sort()
		for i in cuts.size() - 1:
			var start := a.lerp(b, float(cuts[i]))
			var end := a.lerp(b, float(cuts[i + 1]))
			if start.distance_squared_to(end) <= EPS * EPS:
				continue
			var middle := (start + end) * 0.5
			var left_inside := _covers_side(middle, left)
			var right_inside := _covers_side(middle, -left)
			if left_inside == right_inside:
				continue
			var first := _vertex(start)
			var second := _vertex(end)
			if first == second:
				continue
			var directed := Vector2i(first, second) if left_inside else Vector2i(second, first)
			exposed[directed] = true
	for polygon in _trace_contours(exposed):
		var contour := PackedVector3Array()
		for point in polygon:
			contour.append(_u * point.x + _v * point.y + _normal * _plane)
		result.append(contour)
	return result


func _split_intersections(lines: Array[Dictionary]) -> void:
	for i in lines.size():
		var a: Vector2 = lines[i]["a"]
		var b: Vector2 = lines[i]["b"]
		var ab := b - a
		var ab_length := ab.length()
		for j in range(i + 1, lines.size()):
			if int(lines[i]["polygon"]) == int(lines[j]["polygon"]) or not Rect2(lines[i]["bounds"]).intersects(lines[j]["bounds"], true):
				continue
			var c: Vector2 = lines[j]["a"]
			var d: Vector2 = lines[j]["b"]
			var cd := d - c
			var cross := ab.cross(cd)
			if absf(cross) > 0.00000001:
				var t := (c - a).cross(cd) / cross
				var s := (c - a).cross(ab) / cross
				var tolerance_a := EPS / maxf(ab_length, EPS)
				var tolerance_b := EPS / maxf(cd.length(), EPS)
				if t >= -tolerance_a and t <= 1.0 + tolerance_a and s >= -tolerance_b and s <= 1.0 + tolerance_b:
					lines[i]["cuts"].append(clampf(t, 0.0, 1.0))
					lines[j]["cuts"].append(clampf(s, 0.0, 1.0))
			elif absf(ab.cross(c - a)) <= EPS * ab_length:
				for point: Vector2 in [c, d]:
					var t := (point - a).dot(ab) / ab.length_squared()
					if t >= 0.0 and t <= 1.0:
						lines[i]["cuts"].append(t)
				for point: Vector2 in [a, b]:
					var t := (point - c).dot(cd) / cd.length_squared()
					if t >= 0.0 and t <= 1.0:
						lines[j]["cuts"].append(t)


func _covers_side(point: Vector2, toward: Vector2) -> bool:
	# Evaluate the infinitesimal side of an edge, rather than probing a fixed
	# distance away and accidentally jumping across a very thin tapered tip.
	for polygon in _polygons:
		if not Rect2(polygon["bounds"]).has_point(point):
			continue
		var inside := true
		for plane: Vector3 in polygon["planes"]:
			var inward := Vector2(plane.x, plane.y)
			var distance := inward.dot(point) - plane.z
			if distance < -EPS or (absf(distance) <= EPS and inward.dot(toward) < -0.000001):
				inside = false
				break
		if inside:
			return true
	return false


func _trace_contours(edges: Dictionary) -> Array[PackedVector2Array]:
	var contours: Array[PackedVector2Array] = []
	var outgoing: Dictionary = {}
	for edge: Vector2i in edges:
		if not outgoing.has(edge.x):
			outgoing[edge.x] = []
		outgoing[edge.x].append(edge.y)
	var visited: Dictionary = {}
	for first: Vector2i in edges:
		if visited.has(first):
			continue
		var current := first
		var polygon := PackedVector2Array()
		var closed := false
		for guard in edges.size() + 1:
			if visited.has(current):
				closed = current == first
				break
			visited[current] = true
			polygon.append(_vertices[current.x])
			if not outgoing.has(current.y):
				break
			var reverse := (_vertices[current.x] - _vertices[current.y]).angle()
			var smallest_turn := INF
			var next := -1
			for candidate: int in outgoing[current.y]:
				var angle := (_vertices[candidate] - _vertices[current.y]).angle()
				var turn := fposmod(reverse - angle, TAU)
				if turn < smallest_turn:
					smallest_turn = turn
					next = candidate
			if next < 0:
				break
			current = Vector2i(current.y, next)
		if closed and polygon.size() >= 3 and absf(_area(polygon)) > EPS * EPS:
			contours.append(_rotate_to_first(polygon))
	contours.sort_custom(_polygon_before)
	return contours


func _vertex(point: Vector2) -> int:
	var key := Vector2i(roundi(point.x / EPS), roundi(point.y / EPS))
	if _vertex_ids.has(key):
		return int(_vertex_ids[key])
	var closest := -1
	var distance := EPS * EPS
	for x in range(-1, 2):
		for y in range(-1, 2):
			var neighbor := key + Vector2i(x, y)
			if not _vertex_ids.has(neighbor):
				continue
			var index := int(_vertex_ids[neighbor])
			var candidate := point.distance_squared_to(_vertices[index])
			if candidate < distance:
				distance = candidate
				closest = index
	if closest < 0:
		closest = _vertices.size()
		_vertices.append(Vector2(key) * EPS)
	_vertex_ids[key] = closest
	return closest


func _rotate_to_first(polygon: PackedVector2Array) -> PackedVector2Array:
	var first := 0
	for i in range(1, polygon.size()):
		if polygon[i].x < polygon[first].x or (polygon[i].x == polygon[first].x and polygon[i].y < polygon[first].y):
			first = i
	var result := PackedVector2Array()
	for i in polygon.size():
		result.append(polygon[(first + i) % polygon.size()])
	return result


func _polygon_before(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i].x != b[i].x:
			return a[i].x < b[i].x
		if a[i].y != b[i].y:
			return a[i].y < b[i].y
	return a.size() < b.size()


func _area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return area * 0.5
