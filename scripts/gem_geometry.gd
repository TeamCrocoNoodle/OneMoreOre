class_name GemGeometry
extends RefCounted

## One solid mineral cut: broad irregular facets, a small flat crown, and a
## substantial oblique base. Bevels are real convex geometry, never wire lines.
const EPS := 0.00001


static func build(variant: int, special: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 82463 + posmod(variant, 6) * 1597 + (733 if special else 0)
	var points := _profile_points(rng)
	var base_faces := _polygon_faces(points, _convex_hull(points))
	var bevel_points := PackedVector3Array()
	var bevel_width := rng.randf_range(0.003, 0.005)
	for face in base_faces:
		var polygon: PackedVector3Array = face["points"]
		var normal: Vector3 = face["normal"]
		var center := _average(polygon)
		var u := _tangent(normal)
		var v := normal.cross(u).normalized()
		var flat := PackedVector2Array()
		for point in polygon:
			flat.append(Vector2((point - center).dot(u), (point - center).dot(v)))
		var inradius := INF
		for i in flat.size():
			var a := flat[i]
			var b := flat[(i + 1) % flat.size()]
			inradius = minf(inradius, absf(a.cross(b)) / maxf(a.distance_to(b), EPS))
		var inset := minf(bevel_width, inradius * 0.17)
		for i in flat.size():
			var previous := flat[posmod(i - 1, flat.size())]
			var current := flat[i]
			var following := flat[(i + 1) % flat.size()]
			var first := (current - previous).normalized()
			var second := (following - current).normalized()
			var inward_a := Vector2(-first.y, first.x)
			var inward_b := Vector2(-second.y, second.x)
			var offset := (inward_a + inward_b) * inset / maxf(1.0 + inward_a.dot(inward_b), 0.001)
			var point := current + offset
			bevel_points.append(center + u * point.x + v * point.y)
	# Taking the hull of inset face corners closes every edge and vertex with
	# proper bevel planes, including vertices where more than three cuts meet.
	var faces := _polygon_faces(bevel_points, _convex_hull(bevel_points))
	var used_points := PackedVector3Array()
	for face in faces:
		for point: Vector3 in face["points"]:
			if not _contains_point(used_points, point):
				used_points.append(point)
	var radius := 0.0
	for point in used_points:
		radius = maxf(radius, point.length())
	var target_radius := 0.517 if special else 0.397
	var scale_factor := target_radius / maxf(radius, EPS)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face_index in faces.size():
		var face: Dictionary = faces[face_index]
		var normal: Vector3 = face["normal"]
		var distance: float = face["distance"]
		var is_bevel := true
		var body_id := face_index
		for base_index in base_faces.size():
			var original: Dictionary = base_faces[base_index]
			if normal.dot(original["normal"]) > 0.99995 and absf(distance - float(original["distance"])) < 0.0001:
				is_bevel = false
				body_id = base_index
				break
		var brightness := 1.0 if is_bevel else 0.82 + float(posmod(body_id * 37 + variant * 13, 19)) * 0.008
		var tint := Color(brightness * 0.995, brightness, brightness * 0.995)
		var polygon := PackedVector3Array()
		for point: Vector3 in face["points"]:
			polygon.append(point * scale_factor)
		var triangles := PackedVector3Array()
		for point: Vector3 in face["triangles"]:
			triangles.append(point * scale_factor)
		_emit_face(surface, polygon, triangles, normal, tint, face_index, is_bevel)
	var collider_points := PackedVector3Array()
	for point in used_points:
		collider_points.append(point * scale_factor)
	return {"mesh": surface.commit(), "collider_points": collider_points, "bound_radius": target_radius}


static func _profile_points(rng: RandomNumberGenerator) -> PackedVector3Array:
	var points := PackedVector3Array()
	var phase := rng.randf_range(0.13, 0.22)
	# The top is only about 28% of the body's width, and is an actual small
	# tilted planar quadrilateral instead of a needle or a ring of triangles.
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25 + phase
		var x := -0.045 + cos(angle) * 0.17
		var z := -0.025 + sin(angle) * 0.145
		points.append(Vector3(x, 0.825 + x * 0.065 - z * 0.04, z))
	# Staggered shoulders and lower corners produce genuine large triangular
	# and polygonal cleavage faces instead of horizontal jewelry bands.
	for i in 4:
		var angle := TAU * float(i) / 4.0 + phase + rng.randf_range(-0.09, 0.09)
		var x := -0.025 + cos(angle) * rng.randf_range(0.315, 0.345)
		# The left shoulder steps outward around the upper third of the
		# silhouette, then continues into the broad lower mineral body.
		if cos(angle) < -0.5:
			x = -0.025 + (x + 0.025) * 1.20
		var z := sin(angle) * rng.randf_range(0.235, 0.265)
		var y := 0.29 + sin(angle + 0.8) * 0.105 + rng.randf_range(-0.025, 0.025)
		points.append(Vector3(x, y, z))
	for i in 6:
		var angle := TAU * float(i) / 6.0 + phase + rng.randf_range(-0.085, 0.085)
		var x := 0.025 + cos(angle) * rng.randf_range(0.485, 0.520)
		var z := 0.018 + sin(angle) * rng.randf_range(0.340, 0.370)
		var y := -0.265 + sin(angle - 0.55) * 0.13 + rng.randf_range(-0.025, 0.025)
		points.append(Vector3(x, y, z))
	# A wide five-sided oblique base supplies the thick broken-mineral end.
	for i in 5:
		var angle := TAU * float(i) / 5.0 + phase + 0.12 + rng.randf_range(-0.04, 0.04)
		var x := 0.025 + cos(angle) * rng.randf_range(0.335, 0.355)
		var z := 0.030 + sin(angle) * rng.randf_range(0.285, 0.305)
		points.append(Vector3(x, -0.77 + x * 0.19 + z * 0.13, z))
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	var center := (low + high) * 0.5
	for i in points.size():
		points[i] -= center
		points[i].x *= 1.12
	return points


static func _convex_hull(points: PackedVector3Array) -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	if points.size() < 4:
		return faces
	var a := 0
	var b := 1
	var greatest := 0.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			var distance := points[i].distance_squared_to(points[j])
			if distance > greatest:
				greatest = distance
				a = i
				b = j
	var c := -1
	greatest = 0.0
	var edge := (points[b] - points[a]).normalized()
	for i in points.size():
		var distance := (points[i] - points[a]).cross(edge).length_squared()
		if distance > greatest:
			greatest = distance
			c = i
	if c < 0:
		return faces
	var plane_normal := (points[b] - points[a]).cross(points[c] - points[a]).normalized()
	var d := -1
	greatest = 0.0
	for i in points.size():
		var distance := absf((points[i] - points[a]).dot(plane_normal))
		if distance > greatest:
			greatest = distance
			d = i
	if d < 0:
		return faces
	var inside := (points[a] + points[b] + points[c] + points[d]) * 0.25
	for indices: Vector3i in [Vector3i(a, b, c), Vector3i(a, d, b), Vector3i(a, c, d), Vector3i(b, d, c)]:
		faces.append(_hull_face(points, indices.x, indices.y, indices.z, inside))
	for point_id in points.size():
		if point_id == a or point_id == b or point_id == c or point_id == d:
			continue
		var visible: Dictionary = {}
		var horizon: Dictionary = {}
		for i in faces.size():
			var face: Dictionary = faces[i]
			if Vector3(face["normal"]).dot(points[point_id]) - float(face["distance"]) <= EPS:
				continue
			visible[i] = true
			var vertices: Vector3i = face["vertices"]
			for pair: Vector2i in [Vector2i(vertices.x, vertices.y), Vector2i(vertices.y, vertices.z), Vector2i(vertices.z, vertices.x)]:
				var key := Vector2i(mini(pair.x, pair.y), maxi(pair.x, pair.y))
				if horizon.has(key):
					horizon.erase(key)
				else:
					horizon[key] = pair
		if visible.is_empty():
			continue
		var kept: Array[Dictionary] = []
		for i in faces.size():
			if not visible.has(i):
				kept.append(faces[i])
		for pair: Vector2i in horizon.values():
			var face := _hull_face(points, pair.x, pair.y, point_id, inside)
			if Vector3(face["normal"]).length_squared() > 0.1:
				kept.append(face)
		faces = kept
	return faces


static func _hull_face(points: PackedVector3Array, a: int, b: int, c: int, inside: Vector3) -> Dictionary:
	var normal := (points[b] - points[a]).cross(points[c] - points[a]).normalized()
	if normal.dot(inside - points[a]) > 0.0:
		var temporary := b
		b = c
		c = temporary
		normal = -normal
	return {"vertices": Vector3i(a, b, c), "normal": normal, "distance": normal.dot(points[a])}


static func _polygon_faces(points: PackedVector3Array, triangles: Array[Dictionary]) -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	for triangle in triangles:
		var normal: Vector3 = triangle["normal"]
		var distance: float = triangle["distance"]
		var found := -1
		for i in faces.size():
			if normal.dot(faces[i]["normal"]) > 0.99999 and absf(distance - float(faces[i]["distance"])) < EPS * 2.0:
				found = i
				break
		if found < 0:
			faces.append({"normal": normal, "distance": distance, "ids": {}, "triangles": PackedVector3Array()})
			found = faces.size() - 1
		var indices: Vector3i = triangle["vertices"]
		for index: int in [indices.x, indices.y, indices.z]:
			faces[found]["ids"][index] = true
			faces[found]["triangles"].append(points[index])
	for face in faces:
		var polygon := PackedVector3Array()
		for id: int in face["ids"]:
			polygon.append(points[id])
		var center := _average(polygon)
		var normal: Vector3 = face["normal"]
		var u := _tangent(normal)
		var v := normal.cross(u).normalized()
		var sorted: Array[Vector3] = []
		for point in polygon:
			sorted.append(point)
		sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool: return atan2((a - center).dot(v), (a - center).dot(u)) < atan2((b - center).dot(v), (b - center).dot(u)))
		face["points"] = PackedVector3Array(sorted)
	return faces


static func _emit_face(surface: SurfaceTool, polygon: PackedVector3Array, triangles: PackedVector3Array, normal: Vector3, color: Color, face_id: int, bevel: bool) -> void:
	var center := _average(polygon)
	var u := _tangent(normal)
	var v := normal.cross(u).normalized()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in polygon:
		var flat := Vector2((point - center).dot(u), (point - center).dot(v))
		low = low.min(flat)
		high = high.max(flat)
	var extent := (high - low).max(Vector2(EPS, EPS))
	# Keep the hull's exact topology. Near-coplanar corner cuts can include a
	# vertex inside their projected face boundary; a new center fan would erase
	# that shared edge and leave a seam. All triangles of a cut still share UVs,
	# tint and its face ID, so these internal diagonals have no visual outline.
	for i in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 2]
		var c := triangles[i + 1]
		for point: Vector3 in [a, b, c]:
			var flat := Vector2((point - center).dot(u), (point - center).dot(v))
			surface.set_normal(normal)
			surface.set_color(color)
			surface.set_uv((flat - low) / extent)
			surface.set_uv2(Vector2(float(face_id), 1.0 if bevel else 0.0))
			surface.add_vertex(point)


static func _average(points: PackedVector3Array) -> Vector3:
	var center := Vector3.ZERO
	for point in points:
		center += point
	return center / maxf(float(points.size()), 1.0)


static func _tangent(normal: Vector3) -> Vector3:
	var tangent := normal.cross(Vector3.UP).normalized()
	if tangent.length_squared() < 0.1:
		tangent = normal.cross(Vector3.RIGHT).normalized()
	return tangent


static func _contains_point(points: PackedVector3Array, candidate: Vector3) -> bool:
	for point in points:
		if point.distance_squared_to(candidate) < EPS * EPS:
			return true
	return false
