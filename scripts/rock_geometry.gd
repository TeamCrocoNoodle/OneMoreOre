class_name RockGeometry
extends RefCounted

## A deterministic spherical Voronoi shell. Every cell is a solid, independent
## stone plate, with a large planar face, clipped corners, and a pale chamfer.
## Vertices are local to the returned center so a mined plate can become debris.
static func build_layer(radius: float, layer_index: int, seed_value: int, piece_count: int = 0, thickness: float = 0.0) -> Array[Dictionary]:
	if radius <= 0.0:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + layer_index * 7919
	var count: int = maxi(piece_count, 8) if piece_count > 0 else [38, 30, 24][clampi(layer_index, 0, 2)]
	var depth := clampf(thickness, radius * 0.015, radius * 0.98) if thickness > 0.0 else minf(0.63, radius * 0.42)
	# Scale angular irregularity with cell spacing: dense shells should not
	# collapse nearby seed points into tiny slivers or nearly coincident faces.
	var jitter := minf(0.19, 0.16 * sqrt(38.0 / float(count)))
	var relief := minf(radius * 0.07, depth * 0.40)
	var bevel_depth := minf(radius * 0.022, depth * 0.13)
	var backing_radius := radius - (relief * 0.9286 + bevel_depth + minf(depth * 0.08, radius * 0.01))
	var inner_radius := radius - depth
	var directions: Array[Vector3] = []
	var rotation := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-PI, PI), rng.randf_range(-0.3, 0.3)))
	for i in count:
		var height := 1.0 - 2.0 * (float(i) + 0.5) / float(count)
		var angle := float(i) * 2.3999632297
		var width := sqrt(1.0 - height * height)
		var direction := Vector3(cos(angle) * width, height, sin(angle) * width)
		direction += Vector3(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		directions.append((rotation * direction).normalized())
	var result: Array[Dictionary] = []
	for i in count:
		var normal := directions[i]
		var tangent := normal.cross(Vector3.UP).normalized()
		if tangent.length_squared() < 0.1:
			tangent = normal.cross(Vector3.RIGHT).normalized()
		var bitangent := normal.cross(tangent).normalized()
		var polygon: Array[Vector2] = [Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)]
		for j in count:
			if i == j:
				continue
			var plane := normal - directions[j]
			polygon = _clip_polygon(polygon, tangent.dot(plane), bitangent.dot(plane), normal.dot(plane))
		if polygon.size() < 3:
			continue
		# Chamfer the silhouette corners as well as the face perimeter. This
		# prevents the regular hexagon / soccer-ball appearance of raw Voronoi.
		var corners: Array[Vector2] = []
		for k in polygon.size():
			var previous := polygon[posmod(k - 1, polygon.size())]
			var current := polygon[k]
			var following := polygon[(k + 1) % polygon.size()]
			var cut := rng.randf_range(0.065, 0.16)
			corners.append(current.lerp(previous, cut) * 0.945)
			corners.append(current.lerp(following, cut) * 0.945)
		var face_distance := radius + relief * rng.randf_range(-0.9286, 0.0714)
		var center := normal * (radius - depth * 0.48)
		var front := PackedVector3Array()
		var shoulder := PackedVector3Array()
		var lower := PackedVector3Array()
		var back := PackedVector3Array()
		var footprint := PackedVector3Array()
		var face_width := rng.randf_range(0.905, 0.945)
		for corner_index in corners.size():
			var corner := corners[corner_index]
			var planar := tangent * corner.x + bitangent * corner.y
			var outward := (normal + planar).normalized()
			# Every bevel must descend from its face. Using a fixed shoulder
			# sphere can put narrow cells' shoulders above their faces, producing
			# recessed panels instead of solid stone. Tangential inset also keeps
			# broad cells from overhanging the shoulder and inverting their normals.
			var shoulder_radius := minf(radius - bevel_depth, (face_distance - bevel_depth) / outward.dot(normal))
			var shoulder_point := outward * shoulder_radius
			var front_tangent := shoulder_point - normal * shoulder_point.dot(normal)
			front.append(normal * face_distance + front_tangent * face_width - center)
			shoulder.append(shoulder_point - center)
			# The visible lips are separated, but each piece widens into its full
			# uncut Voronoi footprint below the seam. Adjacent backing skirts meet
			# exactly and block both sight and mining rays through an intact layer.
			# Two chamfer corners share one backing vertex; zero-area triangles
			# are discarded by the mesh helpers below.
			var full_corner := polygon[corner_index / 2]
			var full_direction := (normal + tangent * full_corner.x + bitangent * full_corner.y).normalized()
			lower.append(full_direction * backing_radius - center)
			back.append(full_direction * inner_radius - center)
			if corner_index % 2 == 0:
				footprint.append(full_direction)
		var value := rng.randf_range(0.78, 1.08)
		var color := Color(0.47, 0.49, 0.49) * value
		if layer_index == 1:
			color = Color(0.43, 0.46, 0.49) * value
		elif layer_index >= 2:
			color = Color(0.40, 0.43, 0.49) * value
		color.a = 1.0
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var face_center := normal * face_distance - center
		for k in front.size():
			var next := (k + 1) % front.size()
			_triangle(surface, face_center, front[k], front[next], normal, Color(0.7143, 0.7143, 0.7143))
			var bevel_color := Color(1.0, 1.0, 0.9643) if k % 2 == 0 else Color(0.8786, 0.8929, 0.8714)
			_quad(surface, front[k], shoulder[k], shoulder[next], front[next], normal, bevel_color)
			_quad(surface, shoulder[k], lower[k], lower[next], shoulder[next], normal, Color(0.5143, 0.5429, 0.5643))
			_quad(surface, lower[k], back[k], back[next], lower[next], normal, Color(0.3643, 0.3929, 0.4357))
			_triangle(surface, normal * inner_radius - center, back[next], back[k], -normal, Color(0.3214, 0.35, 0.3929))
		var mesh := surface.commit()
		var collision := ConvexPolygonShape3D.new()
		var hull := PackedVector3Array()
		hull.append_array(front)
		hull.append_array(shoulder)
		hull.append_array(lower)
		hull.append_array(back)
		collision.points = hull
		result.append({
			"mesh": mesh,
			"collision": collision,
			"direction": normal,
			"normal": normal,
			"center": center,
			"color": color,
			"face_points": front,
			"face_center": face_center,
			"footprint_directions": footprint,
			"radius": radius,
			"inner_radius": inner_radius,
			"backing_radius": backing_radius,
			"thickness": depth,
			"piece_index": i,
			"seed": seed_value + i * 127 + layer_index * 7919,
		})
	return result


static func _clip_polygon(points: Array[Vector2], a: float, b: float, c: float) -> Array[Vector2]:
	var clipped: Array[Vector2] = []
	if points.is_empty():
		return clipped
	for i in points.size():
		var current := points[i]
		var following := points[(i + 1) % points.size()]
		var distance_a := a * current.x + b * current.y + c
		var distance_b := a * following.x + b * following.y + c
		if distance_a >= -0.000001:
			clipped.append(current)
		if (distance_a > 0.0 and distance_b < 0.0) or (distance_a < 0.0 and distance_b > 0.0):
			clipped.append(current.lerp(following, distance_a / (distance_a - distance_b)))
	return clipped


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < 0.01:
		normal = (c - a).cross(d - a).normalized()
	if normal.length_squared() < 0.01:
		return
	# The side walls point away from the cell's own radial axis.
	var middle := (a + b + c + d) * 0.25
	var side := middle - outward * middle.dot(outward)
	if normal.dot(side) < 0.0:
		normal = -normal
	if side.length_squared() < 0.0001:
		normal = outward
	_triangle(surface, a, b, c, normal, color)
	_triangle(surface, a, c, d, normal, color)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).length_squared() < 0.0000000001:
		return
	surface.set_normal(normal)
	surface.set_color(color)
	# Godot's front faces use clockwise winding.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		surface.add_vertex(a)
		surface.add_vertex(c)
		surface.add_vertex(b)
	else:
		surface.add_vertex(a)
		surface.add_vertex(b)
		surface.add_vertex(c)
