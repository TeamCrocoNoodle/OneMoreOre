class_name RockFracture
extends RefCounted

## Builds a planar arrangement of the stone's visible fractures. Every interior
## edge is an actual crack, or a collinear continuation of its open final tip.
const EPS := 0.00001
const MAX_FRAGMENTS := 18

var _origin := Vector3.ZERO
var _normal := Vector3.UP
var _u := Vector3.RIGHT
var _v := Vector3.FORWARD
var _vertices: Array[Vector2] = []
var _vertex_ids: Dictionary = {}
var _edges: Dictionary = {}
var _mesh_vertices := PackedVector3Array()
var _fallback_depth := 0.3
var _depth_cache: Dictionary = {}


static func build(mesh: ArrayMesh, face: PackedVector3Array, center: Vector3, normal: Vector3, cracks: Array[Dictionary], source_vertices: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	var builder: RefCounted = (load("res://scripts/rock_fracture.gd") as GDScript).new()
	return builder._build(mesh, face, center, normal, cracks, source_vertices)


func _build(mesh: ArrayMesh, face: PackedVector3Array, center: Vector3, normal: Vector3, cracks: Array[Dictionary], source_vertices: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	_origin = center
	_normal = normal.normalized()
	_u = _normal.cross(Vector3.UP).normalized()
	if _u.length_squared() < 0.1:
		_u = _normal.cross(Vector3.RIGHT).normalized()
	_v = _normal.cross(_u).normalized()
	var boundary := PackedVector2Array()
	for point in face:
		boundary.append(_project(point))
	if _area(boundary) < 0.0:
		boundary.reverse()
	var lines: Array[Dictionary] = []
	for i in cracks.size():
		var a := _project(cracks[i]["a"])
		var b := _project(cracks[i]["b"])
		if a.distance_squared_to(b) > EPS * EPS:
			lines.append({"a": a, "b": b, "kind": "crack", "source": i, "cuts": [0.0, 1.0]})
	var source_count := lines.size()
	_extend_tips(lines, source_count, boundary)
	for i in boundary.size():
		lines.append({"a": boundary[i], "b": boundary[(i + 1) % boundary.size()], "kind": "boundary", "source": -1, "cuts": [0.0, 1.0]})
	_split_intersections(lines)
	for line in lines:
		var cuts: Array = line["cuts"]
		cuts.sort()
		var a: Vector2 = line["a"]
		var b: Vector2 = line["b"]
		for i in cuts.size() - 1:
			if float(cuts[i + 1]) - float(cuts[i]) <= 0.000001:
				continue
			var first := _vertex(a.lerp(b, float(cuts[i])))
			var second := _vertex(a.lerp(b, float(cuts[i + 1])))
			if first == second:
				continue
			var key := Vector2i(mini(first, second), maxi(first, second))
			if not _edges.has(key):
				_edges[key] = {"a": first, "b": second, "kind": line["kind"], "source": line["source"]}
	var topology := _trace_faces()
	var polygons: Array = topology["polygons"]
	var owners: Dictionary = topology["owners"]
	var parents: Array[int] = []
	for i in polygons.size():
		parents.append(i)
	var regions: Dictionary = {}
	for i in polygons.size():
		regions[i] = polygons[i]
	_merge_regions(regions, parents, owners)
	var boundaries: Array[Dictionary] = []
	for edge: Dictionary in _edges.values():
		var a: int = edge["a"]
		var b: int = edge["b"]
		var left := int(owners.get(Vector2i(a, b), -1))
		var right := int(owners.get(Vector2i(b, a), -1))
		if left >= 0 and right >= 0 and _root(parents, left) == _root(parents, right):
			continue
		var sources := PackedInt32Array()
		if int(edge["source"]) >= 0:
			sources.append(int(edge["source"]))
		boundaries.append({"a": _unproject(_vertices[a]), "b": _unproject(_vertices[b]), "kind": edge["kind"], "source_indices": sources})
	_read_mesh(mesh, source_vertices)
	var fragments: Array[Dictionary] = []
	var region_ids: Array = regions.keys()
	region_ids.sort()
	for id: int in region_ids:
		var polygon: PackedVector2Array = regions[id]
		var fragment := _extrude(polygon)
		if not fragment.is_empty():
			fragments.append(fragment)
	return {"fragments": fragments, "boundaries": boundaries, "source_segments": cracks.duplicate(true)}


func _extend_tips(lines: Array[Dictionary], count: int, boundary: PackedVector2Array) -> void:
	var endpoints: Dictionary = {}
	for i in count:
		for key: String in ["a", "b"]:
			var point: Vector2 = lines[i][key]
			var snapped := _key(point)
			if not endpoints.has(snapped):
				endpoints[snapped] = []
			endpoints[snapped].append({"line": i, "end": key})
	for entries: Array in endpoints.values():
		if entries.size() != 1:
			continue
		var index: int = entries[0]["line"]
		var end_key: String = entries[0]["end"]
		var tip: Vector2 = lines[index][end_key]
		var previous: Vector2 = lines[index]["b" if end_key == "a" else "a"]
		var joined := false
		for j in count:
			if j != index and _point_on_segment(tip, lines[j]["a"], lines[j]["b"]):
				joined = true
				break
		if joined:
			continue
		var direction := (tip - previous).normalized()
		var nearest := INF
		var target := tip
		for j in boundary.size():
			var a := boundary[j]
			var b := boundary[(j + 1) % boundary.size()]
			if _point_on_segment(tip, a, b):
				nearest = 0.0
				break
			var edge := b - a
			var cross := direction.cross(edge)
			if absf(cross) <= EPS:
				continue
			var distance := (a - tip).cross(edge) / cross
			var along := (a - tip).cross(direction) / cross
			if distance > EPS and along >= -EPS and along <= 1.0 + EPS and distance < nearest:
				nearest = distance
				target = tip + direction * distance
		if nearest < INF and nearest > EPS:
			lines.append({"a": tip, "b": target, "kind": "extension", "source": lines[index]["source"], "cuts": [0.0, 1.0]})


func _split_intersections(lines: Array[Dictionary]) -> void:
	for i in lines.size():
		var a: Vector2 = lines[i]["a"]
		var b: Vector2 = lines[i]["b"]
		var ab := b - a
		for j in range(i + 1, lines.size()):
			var c: Vector2 = lines[j]["a"]
			var d: Vector2 = lines[j]["b"]
			if maxf(a.x, b.x) + EPS < minf(c.x, d.x) or maxf(c.x, d.x) + EPS < minf(a.x, b.x) or maxf(a.y, b.y) + EPS < minf(c.y, d.y) or maxf(c.y, d.y) + EPS < minf(a.y, b.y):
				continue
			var cd := d - c
			var cross := ab.cross(cd)
			if absf(cross) > 0.00000001:
				var t := (c - a).cross(cd) / cross
				var u := (c - a).cross(ab) / cross
				if t >= -EPS and t <= 1.0 + EPS and u >= -EPS and u <= 1.0 + EPS:
					lines[i]["cuts"].append(clampf(t, 0.0, 1.0))
					lines[j]["cuts"].append(clampf(u, 0.0, 1.0))
			elif absf(ab.cross(c - a)) < EPS * ab.length():
				for point: Vector2 in [c, d]:
					if _point_on_segment(point, a, b):
						lines[i]["cuts"].append(clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0))
				for point: Vector2 in [a, b]:
					if _point_on_segment(point, c, d):
						lines[j]["cuts"].append(clampf((point - c).dot(cd) / cd.length_squared(), 0.0, 1.0))


func _trace_faces() -> Dictionary:
	var adjacency: Dictionary = {}
	for edge: Dictionary in _edges.values():
		var a: int = edge["a"]
		var b: int = edge["b"]
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		adjacency[a].append(b)
		adjacency[b].append(a)
	for id: int in adjacency:
		var point := _vertices[id]
		adjacency[id].sort_custom(func(a: int, b: int) -> bool: return (_vertices[a] - point).angle() < (_vertices[b] - point).angle())
	var visited: Dictionary = {}
	var owners: Dictionary = {}
	var polygons: Array[PackedVector2Array] = []
	for edge: Dictionary in _edges.values():
		for reverse: bool in [false, true]:
			var a: int = edge["b"] if reverse else edge["a"]
			var b: int = edge["a"] if reverse else edge["b"]
			var start := Vector2i(a, b)
			if visited.has(start):
				continue
			var polygon := PackedVector2Array()
			var path: Array[Vector2i] = []
			var closed := false
			for guard in _edges.size() * 2 + 2:
				var directed := Vector2i(a, b)
				if visited.has(directed):
					closed = directed == start
					break
				visited[directed] = true
				path.append(directed)
				polygon.append(_vertices[a])
				var neighbors: Array = adjacency[b]
				var incoming := neighbors.find(a)
				var next: int = neighbors[posmod(incoming - 1, neighbors.size())]
				a = b
				b = next
			if closed and _area(polygon) > EPS * EPS and not Geometry2D.triangulate_polygon(polygon).is_empty():
				var owner := polygons.size()
				polygons.append(polygon)
				for directed in path:
					owners[directed] = owner
	return {"polygons": polygons, "owners": owners}


func _merge_regions(regions: Dictionary, parents: Array[int], owners: Dictionary) -> void:
	var adjacency: Dictionary = {}
	var areas: Dictionary = {}
	for id: int in regions:
		areas[id] = absf(_area(regions[id]))
	for edge: Dictionary in _edges.values():
		var a := int(owners.get(Vector2i(edge["a"], edge["b"]), -1))
		var b := int(owners.get(Vector2i(edge["b"], edge["a"]), -1))
		if a < 0 or b < 0 or a == b:
			continue
		if not adjacency.has(a):
			adjacency[a] = {}
		if not adjacency.has(b):
			adjacency[b] = {}
		var length := _vertices[int(edge["a"])].distance_to(_vertices[int(edge["b"])])
		adjacency[a][b] = float(adjacency[a].get(b, 0.0)) + length
		adjacency[b][a] = float(adjacency[b].get(a, 0.0)) + length
	var blocked: Dictionary = {}
	while regions.size() > MAX_FRAGMENTS:
		var smallest := -1
		var smallest_area := INF
		for id: int in regions:
			if not blocked.has(id) and float(areas[id]) < smallest_area:
				smallest = id
				smallest_area = float(areas[id])
		if smallest < 0:
			break
		var a := smallest
		var merged := false
		if adjacency.has(a):
			var neighbors: Array = adjacency[a].keys()
			neighbors.sort_custom(func(b: int, c: int) -> bool: return float(adjacency[a][b]) > float(adjacency[a][c]))
			for b: int in neighbors:
				var combined := Geometry2D.merge_polygons(regions[a], regions[b])
				if combined.size() != 1 or _area(combined[0]) <= EPS * EPS:
					continue
				regions[b] = combined[0]
				regions.erase(a)
				parents[a] = b
				areas[b] = float(areas[b]) + float(areas[a])
				areas.erase(a)
				for neighbor: int in adjacency[a]:
					if neighbor == b:
						continue
					var shared := float(adjacency[a][neighbor]) + float(adjacency[b].get(neighbor, 0.0))
					adjacency[b][neighbor] = shared
					adjacency[neighbor][b] = shared
					adjacency[neighbor].erase(a)
				adjacency[b].erase(a)
				adjacency.erase(a)
				blocked.clear()
				merged = true
				break
		if not merged:
			blocked[a] = true


func _read_mesh(mesh: ArrayMesh, source_vertices: PackedVector3Array = PackedVector3Array()) -> void:
	_mesh_vertices = source_vertices
	# External callers can still supply only a mesh. Game chunks provide the
	# same flattened triangle vertices retained during their socket setup.
	if _mesh_vertices.is_empty():
		for surface_index in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				_mesh_vertices.append_array(vertices)
			else:
				for index in indices:
					_mesh_vertices.append(vertices[index])
	_fallback_depth = 0.02
	for vertex in _mesh_vertices:
		_fallback_depth = maxf(_fallback_depth, (_origin - vertex).dot(_normal))


func _depth_at(point: Vector3) -> float:
	var key := _key(_project(point))
	if _depth_cache.has(key):
		return float(_depth_cache[key])
	var start := point - _normal * 0.00005
	var ray := -_normal
	var nearest := INF
	for i in range(0, _mesh_vertices.size() - 2, 3):
		var a := _mesh_vertices[i]
		var first := _mesh_vertices[i + 1] - a
		var second := _mesh_vertices[i + 2] - a
		var cross := ray.cross(second)
		var determinant := first.dot(cross)
		if absf(determinant) < 0.00000001:
			continue
		var inverse := 1.0 / determinant
		var offset := start - a
		var u := offset.dot(cross) * inverse
		if u < -EPS or u > 1.0 + EPS:
			continue
		var q := offset.cross(first)
		var v := ray.dot(q) * inverse
		if v < -EPS or u + v > 1.0 + EPS:
			continue
		var distance := second.dot(q) * inverse
		if distance > 0.0001:
			nearest = minf(nearest, distance + 0.00005)
	var depth := clampf(nearest if nearest < INF else _fallback_depth, 0.018, _fallback_depth)
	_depth_cache[key] = depth
	return depth


func _extrude(polygon: PackedVector2Array) -> Dictionary:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():
		return {}
	var area := absf(_area(polygon))
	var shape := _footprint_dimensions(polygon)
	var short_axis: Vector2 = shape["short_axis"]
	var long_axis := short_axis.orthogonal()
	var width: float = shape["width"]
	var length: float = shape["length"]
	var centroid := _polygon_centroid(polygon)
	var rng := RandomNumberGenerator.new()
	var seed_value: int = 1729
	for point in polygon:
		var key := _key(point)
		seed_value = posmod(seed_value * 31 + key.x * 17 + key.y, 2147483647)
	rng.seed = seed_value
	var profile := rng.randi_range(0, 2)
	# A narrow fracture footprint produces a chip, never a long column. Broader
	# regions can carry more mass, but remain much shallower than the full plate.
	var depth := minf(width * rng.randf_range(0.42, 0.64), sqrt(area) * 0.47)
	depth = minf(depth, _fallback_depth * rng.randf_range(0.40, 0.58))
	var short_inset := rng.randf_range(0.52, 0.73)
	var long_inset := rng.randf_range(0.65, 0.84)
	if profile == 0:
		depth *= 0.66
		short_inset = rng.randf_range(0.73, 0.84)
		long_inset = rng.randf_range(0.79, 0.88)
	elif profile == 2:
		short_inset = rng.randf_range(0.62, 0.79)
		long_inset = rng.randf_range(0.59, 0.75)
	var rear_shift := short_axis * width * rng.randf_range(-0.095, 0.095) + long_axis * width * rng.randf_range(-0.07, 0.07)
	var short_slope := rng.randf_range(0.14, 0.22) * (-1.0 if rng.randf() < 0.5 else 1.0)
	var long_slope := rng.randf_range(0.10, 0.20) * (-1.0 if rng.randf() < 0.5 else 1.0)
	var phase := rng.randf_range(-PI, PI)
	var front := PackedVector3Array()
	var shoulder := PackedVector3Array()
	var back := PackedVector3Array()
	var center := Vector3.ZERO
	for point in polygon:
		var position := _unproject(point)
		var offset := point - centroid
		var across := offset.dot(short_axis)
		var along := offset.dot(long_axis)
		var normalized_short := clampf(across / maxf(width * 0.5, EPS), -1.0, 1.0)
		var normalized_long := clampf(along / maxf(length * 0.5, EPS), -1.0, 1.0)
		# The rear is a skewed wedge with shallow unequal facets, rather than a
		# translated copy of the front or a common apex shared by every shard.
		var facet_variation := sin(normalized_long * 3.7 + phase) * sin(normalized_short * 2.6 - phase) * 0.045
		var rear_depth := minf(depth, _depth_at(position)) * clampf(0.76 + normalized_short * short_slope + normalized_long * long_slope + facet_variation, 0.42, 1.0)
		var rear_point := centroid + short_axis * across * short_inset + long_axis * along * long_inset + rear_shift
		var shoulder_point := centroid + short_axis * across * 0.94 + long_axis * along * 0.96 + rear_shift * 0.28
		var middle := _unproject(shoulder_point) - _normal * rear_depth * 0.38
		var rear := _unproject(rear_point) - _normal * rear_depth
		front.append(position)
		shoulder.append(middle)
		back.append(rear)
		center += position + middle + rear
	center /= float(front.size() * 3)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		_triangle(surface, front[a] - center, front[b] - center, front[c] - center, _normal, Color(0.7143, 0.7143, 0.7143))
		_triangle(surface, back[a] - center, back[b] - center, back[c] - center, -_normal, Color(0.77, 0.80, 0.82))
	for i in front.size():
		var next := (i + 1) % front.size()
		var outward := (front[next] - front[i]).cross(_normal).normalized()
		var lip_shade := Color(0.88, 0.92, 0.93)
		var cut_shade := Color(0.95, 0.98, 0.98) if i % 3 == 0 else Color(0.85, 0.89, 0.91)
		_triangle(surface, front[i] - center, shoulder[i] - center, shoulder[next] - center, outward, lip_shade)
		_triangle(surface, front[i] - center, shoulder[next] - center, front[next] - center, outward, lip_shade)
		_triangle(surface, shoulder[i] - center, back[i] - center, back[next] - center, outward, cut_shade)
		_triangle(surface, shoulder[i] - center, back[next] - center, shoulder[next] - center, outward, cut_shade)
	return {"mesh": surface.commit(), "center": center, "area": area, "polygon": front}


func _footprint_dimensions(polygon: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(polygon)
	var width := INF
	var short_axis := Vector2.RIGHT
	for i in hull.size() - 1:
		var edge := hull[i + 1] - hull[i]
		if edge.length_squared() <= EPS * EPS:
			continue
		var axis := edge.normalized().orthogonal()
		var low := INF
		var high := -INF
		for point in hull:
			var projection := point.dot(axis)
			low = minf(low, projection)
			high = maxf(high, projection)
		if high - low < width:
			width = high - low
			short_axis = axis
	var long_axis := short_axis.orthogonal()
	var low := INF
	var high := -INF
	for point in hull:
		var projection := point.dot(long_axis)
		low = minf(low, projection)
		high = maxf(high, projection)
	return {"width": maxf(width, EPS), "length": maxf(high - low, EPS), "short_axis": short_axis}


func _polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var weighted := Vector2.ZERO
	var signed_area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var cross := a.cross(b)
		weighted += (a + b) * cross
		signed_area += cross
	return weighted / (3.0 * signed_area)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < 0.1:
		return
	if normal.dot(outward) < 0.0:
		normal = -normal
	surface.set_normal(normal)
	surface.set_color(color)
	surface.add_vertex(a)
	if (b - a).cross(c - a).dot(normal) > 0.0:
		surface.add_vertex(c)
		surface.add_vertex(b)
	else:
		surface.add_vertex(b)
		surface.add_vertex(c)


func _vertex(point: Vector2) -> int:
	var key := _key(point)
	if not _vertex_ids.has(key):
		# Two lines compute their shared crossing independently. Float error
		# can put that one crossing on opposite sides of a quantization border.
		# Weld neighboring bins geometrically as well as by their rounded key;
		# otherwise a crack appears to stop just short of another edge and a
		# face walk doubles back through the resulting false bridge.
		var nearest := -1
		var distance_squared := EPS * EPS
		for x in range(-1, 2):
			for y in range(-1, 2):
				var neighbor := key + Vector2i(x, y)
				if not _vertex_ids.has(neighbor):
					continue
				var index := int(_vertex_ids[neighbor])
				var candidate := _vertices[index].distance_squared_to(point)
				if candidate < distance_squared:
					nearest = index
					distance_squared = candidate
		if nearest >= 0:
			_vertex_ids[key] = nearest
			return nearest
		_vertex_ids[key] = _vertices.size()
		_vertices.append(Vector2(key) * EPS)
	return int(_vertex_ids[key])


func _key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / EPS), roundi(point.y / EPS))


func _project(point: Vector3) -> Vector2:
	var offset := point - _origin
	return Vector2(offset.dot(_u), offset.dot(_v))


func _unproject(point: Vector2) -> Vector3:
	return _origin + _u * point.x + _v * point.y


func _point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> bool:
	var delta := b - a
	var t := clampf((point - a).dot(delta) / maxf(delta.length_squared(), EPS * EPS), 0.0, 1.0)
	return point.distance_squared_to(a + delta * t) <= EPS * EPS * 4.0


func _area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return area * 0.5


func _root(parents: Array[int], id: int) -> int:
	var root := id
	while parents[root] != root:
		root = parents[root]
	while parents[id] != id:
		var next := parents[id]
		parents[id] = root
		id = next
	return root
