extends SceneTree
## Independent source-quad oracle; no CrackOutline or production containment calls.
const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const Main = preload("res://scripts/main.gd")
const TOL := 0.00008
const FLOOR_DEPTH := 0.006
const WALL_DEPTH := 0.0062

var fixture := Node3D.new()
var checks := 0
var failures: Array[String] = []
var data: Dictionary

func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
		push_error("CRACK_SURFACE_TIMEOUT")
		quit(2)
	)

func _run() -> void:
	root.add_child(fixture)
	fixture.process_mode = Node.PROCESS_MODE_DISABLED
	data = Geometry.build_layer(4.9, 0, 12873, 100, 0.86)[0]
	var cases := {
		"Y": [[Vector2.ZERO, Vector2(-0.65, 0.54), 0.10, 0.035], [Vector2.ZERO, Vector2(0.65, 0.54), 0.10, 0.035], [Vector2.ZERO, Vector2(0, -0.72), 0.10, 0.025]],
		"T": [[Vector2(-0.72, 0.28), Vector2(0.72, 0.28), 0.09, 0.09], [Vector2(0, -0.7), Vector2(0, 0.28), 0.07, 0.12]],
		"X": [[Vector2(-0.65, -0.65), Vector2(0.65, 0.65), 0.09, 0.09], [Vector2(-0.65, 0.65), Vector2(0.65, -0.65), 0.11, 0.06]],
		"closed_loop": [[Vector2(-0.5, -0.5), Vector2(0.5, -0.5), 0.07, 0.07], [Vector2(0.5, -0.5), Vector2(0.5, 0.5), 0.07, 0.07], [Vector2(0.5, 0.5), Vector2(-0.5, 0.5), 0.07, 0.07], [Vector2(-0.5, 0.5), Vector2(-0.5, -0.5), 0.07, 0.07]],
		"disconnected": [[Vector2(-0.75, -0.5), Vector2(-0.3, 0.5), 0.06, 0.10], [Vector2(0.3, -0.5), Vector2(0.75, 0.5), 0.09, 0.04]],
		"acute_taper": [[Vector2(-0.75, 0), Vector2(0.7, 0), 0.025, 0.0], [Vector2(-0.2, 0.02), Vector2(0.7, 0.19), 0.11, 0.0], [Vector2(-0.15, -0.6), Vector2(0.05, 0.05), 0.0, 0.095]]
	}
	for label: String in cases:
		var chunk := _make_chunk()
		var axes := _axes(chunk.direction)
		for spec: Array in cases[label]:
			var a: Vector3 = chunk.face_center + axes[0] * spec[0].x + axes[1] * spec[0].y
			var b: Vector3 = chunk.face_center + axes[0] * spec[1].x + axes[1] * spec[1].y
			chunk._append_visible_crack(a, b, spec[2], spec[3], 1.0, 1, a)
		chunk._draw_crack_surface()
		_validate_surface(chunk, label)
		_validate_transforms(chunk, label)
		chunk.queue_free()
	var game := Main.new()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	_check(game.showcase_covers.size() == 6, "Production seed creates six real showcase owners")
	var owner: Chunk = game.showcase_covers[5]
	for strike in 15:
		var edge := int(float(strike % 3) * owner.face_points.size() / 3.0)
		var midpoint: Vector3 = (owner.face_points[edge] + owner.face_points[(edge + 1) % owner.face_points.size()]) * 0.5
		owner.hit(1.0, owner.mesh_instance.to_global(owner.face_center.lerp(midpoint, 0.52)))
	_check(owner.health == 1.0 and not owner.destroyed, "Real red showcase owner survives fifteen hits at three sites")
	_validate_surface(owner, "showcase_15_hits")
	_validate_transforms(owner, "showcase_15_hits")
	_validate_idle_and_fatal(owner)
	game.queue_free()
	fixture.queue_free()
	await process_frame
	print("CRACK_SURFACE_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _make_chunk() -> Chunk:
	var chunk := Chunk.new()
	fixture.add_child(chunk)
	chunk.configure(data, 0)
	chunk.set_process(false)
	return chunk

func _axes(normal: Vector3) -> Array[Vector3]:
	var u := normal.cross(Vector3(0.31, 0.87, -0.27)).normalized()
	if u.length_squared() < 0.5:
		u = normal.cross(Vector3.RIGHT).normalized()
	return [u, normal.cross(u).normalized()]

func _project(point: Vector3, origin: Vector3, axes: Array[Vector3]) -> Vector2:
	return Vector2((point - origin).dot(axes[0]), (point - origin).dot(axes[1]))

func _source_quads(chunk: Chunk, world: bool) -> Array[PackedVector2Array]:
	var normal := chunk.direction
	var origin := chunk.face_center
	if world:
		normal = (chunk.mesh_instance.global_basis.inverse().transposed() * normal).normalized()
		origin = chunk.mesh_instance.to_global(origin)
	var axes := _axes(normal)
	var result: Array[PackedVector2Array] = []
	for segment in chunk.get_visible_crack_segments():
		var polygon := PackedVector2Array()
		for point: Vector3 in [segment.a - segment.side_a, segment.a + segment.side_a, segment.b + segment.side_b, segment.b - segment.side_b]:
			polygon.append(_project(chunk.mesh_instance.to_global(point) if world else point, origin, axes))
		result.append(polygon)
	return result

func _mesh_geometry(chunk: Chunk, world: bool) -> Dictionary:
	var origin := chunk.face_center
	var normal := chunk.direction
	if world:
		origin = chunk.mesh_instance.to_global(origin)
		normal = (chunk.mesh_instance.global_basis.inverse().transposed() * normal).normalized()
	var axes := _axes(normal)
	var floor_triangles: Array[PackedVector2Array] = []
	var wall_triangles: Array[PackedVector2Array] = []
	var wall_vertices := PackedVector2Array()
	var mesh: ArrayMesh = chunk._crack_mesh.mesh
	var valid := mesh != null
	if not valid:
		return {"valid": false, "floor": [], "walls": [], "outer_edges": []}
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		valid = valid and count % 3 == 0 and colors.size() == vertices.size()
		for i in range(0, count, 3):
			var triangle := PackedVector2Array()
			var is_floor := true
			for j in 3:
				var index := indices[i + j] if not indices.is_empty() else i + j
				var vertex := vertices[index]
				var depth := (vertex - chunk.face_center).dot(chunk.direction)
				var on_floor := absf(depth - FLOOR_DEPTH) < 0.00003
				valid = valid and vertex.is_finite() and (on_floor or absf(depth - WALL_DEPTH) < 0.00003) and absf(colors[index].a - 1.0) < 0.00001
				is_floor = is_floor and on_floor
				var brightness := maxf(colors[index].r, maxf(colors[index].g, colors[index].b))
				valid = valid and (brightness < 0.12 if on_floor else brightness > 0.12)
				var flat := vertex - chunk.direction * depth
				var actual := chunk._crack_mesh.to_global(vertex) - chunk.mesh_instance.global_basis * chunk.direction * depth if world else flat
				triangle.append(_project(actual, origin, axes))
			if is_floor:
				floor_triangles.append(triangle)
			else:
				wall_triangles.append(triangle)
				wall_vertices.append_array(triangle)
	var outer_edges: Array[Dictionary] = []
	valid = valid and wall_vertices.size() % 6 == 0
	for i in range(0, wall_vertices.size(), 6):
		# Check the emitted paired triangles before extracting their bright bank.
		valid = valid and wall_vertices[i].distance_to(wall_vertices[i + 3]) < TOL and wall_vertices[i + 2].distance_to(wall_vertices[i + 4]) < TOL
		outer_edges.append({"a": wall_vertices[i], "b": wall_vertices[i + 5]})
	return {"valid": valid, "floor": floor_triangles, "walls": wall_triangles, "outer_edges": outer_edges}

func _validate_surface(chunk: Chunk, label: String, world: bool = false) -> void:
	var quads := _source_quads(chunk, world)
	var mesh := _mesh_geometry(chunk, world)
	_check(mesh.valid and not mesh.floor.is_empty() and not mesh.walls.is_empty(), label + ": real mesh has opaque dark floor and bright wall triangles")
	if not mesh.valid:
		return
	var boundaries := _independent_boundary(quads)
	var triangles: Array = mesh.floor + mesh.walls
	var bounds := Rect2(quads[0][0], Vector2.ZERO)
	for quad in quads:
		for point in quad:
			bounds = bounds.expand(point)
	bounds = bounds.grow(maxf(bounds.size.x, bounds.size.y) * 0.08)
	var coverage := true
	var floor_coverage := true
	var inside_samples := 0
	var outside_samples := 0
	var first_bad := Vector2.INF
	for x in 67:
		for y in 61:
			var point := bounds.position + bounds.size * Vector2((x + 0.371) / 67.0, (y + 0.619) / 61.0)
			if _distance_to_edges(point, boundaries) < TOL:
				continue
			var expected := _inside_union(point, quads)
			var actual := _inside_union(point, triangles)
			var floor_actual := _inside_union(point, mesh.floor)
			if expected:
				inside_samples += 1
			else:
				outside_samples += 1
			if expected != actual and first_bad == Vector2.INF:
				first_bad = point
			coverage = coverage and expected == actual
			floor_coverage = floor_coverage and expected == floor_actual
	_check(inside_samples > 20 and outside_samples > 50 and floor_coverage, label + ": floor covers exactly the independently sampled ribbon union, including holes and gaps")
	_check(coverage, label + ": floor/wall footprint equals union; bad point=" + str(first_bad))
	var walls_inside := true
	var first_spill := Vector2.INF
	for triangle: PackedVector2Array in mesh.walls:
		# Every vertex, edge samples, and interior samples of every actual triangle.
		for i in 7:
			for j in range(7 - i):
				var point := triangle[0] * (1.0 - float(i + j) / 6.0) + triangle[1] * (float(i) / 6.0) + triangle[2] * (float(j) / 6.0)
				if not _inside_union(point, quads) and _distance_to_edges(point, boundaries) > TOL:
					walls_inside = false
					if first_spill == Vector2.INF:
						first_spill = point
	_check(walls_inside, label + ": wall vertices and triangle interiors remain within footprint; spill=" + str(first_spill))
	var external_only := true
	for edge: Dictionary in mesh.outer_edges:
		external_only = external_only and _edge_covered(edge.a, edge.b, boundaries)
	_check(external_only, label + ": bright outer banks exist only on union exterior, never internal crossings")
	var complete_banks := true
	for edge: Dictionary in boundaries:
		complete_banks = complete_banks and _edge_covered(edge.a, edge.b, mesh.outer_edges)
	_check(complete_banks, label + ": walls cover exterior and hole boundaries without broken junctions")
	if label == "closed_loop":
		_check(not _inside_union(Vector2.ZERO, triangles), "Closed-loop stone island remains unpainted at its center")

func _validate_transforms(chunk: Chunk, label: String) -> void:
	var mesh: ArrayMesh = chunk._crack_mesh.mesh
	var original := chunk.transform
	var original_mesh_transform := chunk.mesh_instance.transform
	for i in 3:
		chunk.rotation = Vector3(0.37, -0.61, 0.23) * float(i + 1)
		chunk.scale = [Vector3(1.1, 0.78, 1.5), Vector3(3.7, 2.9, 4.2), Vector3(0.76, 1.6, 1.13)][i]
		chunk.mesh_instance.position = -chunk.direction * (0.035 + i * 0.023)
		if i == 1:
			_validate_surface(chunk, label + "_zoom_rotation_recoil", true)
		_check(chunk._crack_mesh.mesh == mesh and chunk._crack_mesh.mesh.get_rid() == mesh.get_rid(), label + ": repeated transforms reuse the same uploaded mesh")
	chunk.transform = original
	chunk.mesh_instance.transform = original_mesh_transform

func _validate_idle_and_fatal(chunk: Chunk) -> void:
	var mesh: ArrayMesh = chunk._crack_mesh.mesh
	var faces := mesh.get_faces()
	var changes := [0]
	var record_change := func(): changes[0] += 1
	mesh.changed.connect(record_change)
	for i in 40:
		chunk._process(1.0 / 60.0)
	_check(chunk._crack_mesh.mesh == mesh and changes[0] == 0 and mesh.get_faces() == faces, "Forty recoil/idle frames never regenerate or mutate the dark mesh")
	var broke := chunk.hit(chunk.health, chunk.mesh_instance.to_global(chunk.face_center))
	_check(broke and chunk.destroyed and not chunk.visible and not chunk.get_visible_crack_segments().is_empty(), "Fatal damage keeps final crack data and hides the stone")
	_check(chunk._crack_mesh.mesh == mesh and changes[0] == 0 and mesh.get_faces() == faces, "Fatal damage never builds or uploads an invisible replacement mesh")
	mesh.changed.disconnect(record_change)

func _inside_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var previous := polygon.size() - 1
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[previous]
		if (a.y > point.y) != (b.y > point.y) and point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		previous = i
	return inside

func _inside_union(point: Vector2, polygons: Array) -> bool:
	for polygon: PackedVector2Array in polygons:
		if _inside_polygon(point, polygon):
			return true
	return false

func _independent_boundary(quads: Array[PackedVector2Array]) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for quad in quads:
		for i in quad.size():
			if quad[i].distance_to(quad[(i + 1) % quad.size()]) > 0.0000001:
				edges.append({"a": quad[i], "b": quad[(i + 1) % quad.size()]})
	var result: Array[Dictionary] = []
	for edge in edges:
		var a: Vector2 = edge.a
		var delta: Vector2 = edge.b - a
		var cuts: Array[float] = [0.0, 1.0]
		for other in edges:
			var c: Vector2 = other.a
			var cd: Vector2 = other.b - c
			var cross := delta.cross(cd)
			if absf(cross) > 0.0000000001:
				var t := (c - a).cross(cd) / cross
				var u := (c - a).cross(delta) / cross
				if t > 0.0 and t < 1.0 and u >= -0.000001 and u <= 1.000001:
					cuts.append(t)
			elif absf(delta.normalized().cross(c - a)) < 0.000001:
				for point: Vector2 in [other.a, other.b]:
					cuts.append(clampf((point - a).dot(delta) / delta.length_squared(), 0.0, 1.0))
		cuts.sort()
		for i in range(cuts.size() - 1):
			var first := a + delta * cuts[i]
			var second := a + delta * cuts[i + 1]
			var length := first.distance_to(second)
			if length <= 0.0000001:
				continue
			var midpoint := (first + second) * 0.5
			var probe := delta.normalized().orthogonal() * minf(0.00002, length * 0.08)
			if _inside_union(midpoint + probe, quads) != _inside_union(midpoint - probe, quads):
				result.append({"a": first, "b": second})
	return result

func _distance_to_edges(point: Vector2, edges: Array) -> float:
	var result := INF
	for edge: Dictionary in edges:
		var a: Vector2 = edge.a
		var delta: Vector2 = edge.b - a
		var t := clampf((point - a).dot(delta) / maxf(delta.length_squared(), 0.00000000000001), 0.0, 1.0)
		result = minf(result, point.distance_to(a + delta * t))
	return result

func _edge_covered(a: Vector2, b: Vector2, sources: Array) -> bool:
	var length := a.distance_to(b)
	if length <= TOL:
		return true
	var direction := (b - a) / length
	var intervals: Array[Vector2] = []
	for source: Dictionary in sources:
		var first: Vector2 = source.a
		var second: Vector2 = source.b
		var source_direction := (second - first).normalized()
		if absf(source_direction.cross(a - first)) > TOL or absf(source_direction.cross(b - first)) > TOL:
			continue
		var x := direction.dot(first - a)
		var y := direction.dot(second - a)
		intervals.append(Vector2(maxf(minf(x, y), 0.0), minf(maxf(x, y), length)))
	intervals.sort_custom(func(left: Vector2, right: Vector2): return left.x < right.x)
	var covered := 0.0
	for interval in intervals:
		if interval.y <= interval.x:
			continue
		if interval.x > covered + TOL:
			return false
		covered = maxf(covered, interval.y)
	return covered >= length - TOL

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("CRACK_SURFACE_FAILED: " + description)
