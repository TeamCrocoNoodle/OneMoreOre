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
	for kind: String in ["front", "side", "rear"]:
		if kind != "front":
			game = Main.new()
			game.process_mode = Node.PROCESS_MODE_DISABLED
			root.add_child(game)
		var owner: Chunk = game.showcase_covers[5]
		var strike_face := _capture_strike_face(owner, kind)
		_check(not strike_face.is_empty(), "Actual %s fixture has a real strike face" % kind)
		if strike_face.is_empty():
			game.queue_free()
			continue
		for strike in 15:
			owner.hit(1.0, owner.mesh_instance.to_global(strike_face.point))
		_check(owner.health == 1.0 and not owner.destroyed, "Actual %s owner survives fifteen repeated strikes" % kind)
		_validate_surface(owner, "showcase_%s15" % kind)
		_validate_transforms(owner, "showcase_%s15" % kind)
		_validate_idle_and_fatal(owner)
		game.queue_free()
	_validate_wall_morphology()
	fixture.queue_free()
	await process_frame
	print("CRACK_SURFACE_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_strike_face(chunk: Chunk, kind: String) -> Dictionary:
	# Match capture_all_face_cracks.gd: the largest actual side/rear triangle,
	# with repeated contact at its center; the broad front uses face_center.
	var triangles: PackedVector3Array = chunk.mesh_instance.mesh.get_faces()
	var selected: Dictionary = {}
	for i in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() < 0.0000000001:
			continue
		var normal := -cross.normalized()
		var alignment := normal.dot(chunk.direction)
		var classification := "front" if alignment > 0.95 else ("rear" if alignment < -0.75 else "side")
		if classification != kind:
			continue
		var area := cross.length() * 0.5
		if selected.is_empty() or area > float(selected.area):
			selected = {"point": (a + b + c) / 3.0, "normal": normal, "area": area}
	if kind == "front" and not selected.is_empty():
		selected.point = chunk.face_center
	return selected

func _validate_wall_morphology() -> void:
	# Keep every synthetic bank inside the real face so normal boundary
	# clamping cannot change the shape in this rotation/subdivision test.
	var probe := _make_chunk()
	var radius := INF
	for i in probe.face_points.size():
		var a := probe.face_points[i]
		var edge := probe.face_points[(i + 1) % probe.face_points.size()] - a
		radius = minf(radius, absf(probe.direction.cross(edge).normalized().dot(probe.face_center - a)))
	probe.queue_free()
	var width := radius * 0.08
	var baseline := PackedVector2Array()
	for angle: float in [0.0, PI / 4.0, PI / 2.0]:
		for divisions in [1, 3]:
			var chunk := _make_chunk()
			var axes := _axes(chunk.direction)
			var start := Vector2(-radius * 0.6, 0.0).rotated(angle)
			var finish := Vector2(radius * 0.6, 0.0).rotated(angle)
			for i in divisions:
				_add_planar_crack(chunk, axes, start.lerp(finish, float(i) / divisions), start.lerp(finish, float(i + 1) / divisions), width)
			chunk._join_crack_edges()
			chunk._draw_crack_surface()
			var mesh := _mesh_geometry(chunk, false)
			var profile := _body_profile(mesh.walls, start, finish, width)
			var label := "Constant-width %.0f degree path in %d sections" % [rad_to_deg(angle), divisions]
			_check(_healthy_profile(profile, width), label + ": both wall bands stay nonzero and leave a dark center")
			_check(_profile_spread(profile) < width * 0.08, label + ": straight body band width remains uniform")
			if baseline.is_empty():
				baseline = profile
			else:
				_check(_profiles_match(baseline, profile, TOL * 4.0), label + ": direction and source subdivision do not change wall thickness")
			chunk.queue_free()
	var bend_meshes: Array[Dictionary] = []
	for divisions in [1, 2]:
		var chunk := _make_chunk()
		var axes := _axes(chunk.direction)
		var points := PackedVector2Array([Vector2(-radius * 0.55, 0.0), Vector2.ZERO, Vector2(radius * 0.3, radius * 0.55)])
		for branch in 2:
			for i in divisions:
				_add_planar_crack(chunk, axes, points[branch].lerp(points[branch + 1], float(i) / divisions), points[branch].lerp(points[branch + 1], float(i + 1) / divisions), width)
		chunk._join_crack_edges()
		chunk._draw_crack_surface()
		var mesh := _mesh_geometry(chunk, false)
		_validate_surface(chunk, "Mitered bend with %d sections per leg" % divisions)
		for branch in 2:
			_check(_healthy_profile(_body_profile(mesh.walls, points[branch], points[branch + 1], width), width), "Mitered bend: each leg retains visible bands and a dark center")
		bend_meshes.append(mesh)
		_validate_join_width(_source_quads(chunk, false), mesh.walls, width, "Mitered bend")
		chunk.queue_free()
	_check(_same_wall_mask(bend_meshes[0].walls, bend_meshes[1].walls, Rect2(-width * 2.75, -width * 2.75, width * 5.5, width * 5.5)), "Splitting a mitered path leaves the actual junction wall footprint unchanged")
	var junction := _make_chunk()
	var axes := _axes(junction.direction)
	for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		_add_planar_crack(junction, axes, Vector2.ZERO, Vector2(radius * 0.6, 0.0).rotated(angle), width)
	junction._draw_crack_surface()
	var mesh := _mesh_geometry(junction, false)
	_validate_join_width(_source_quads(junction, false), mesh.walls, width, "Broad three-way junction")
	var core_open := true
	for i in 12:
		core_open = core_open and not _inside_union(Vector2(width * 0.12, 0.0).rotated(TAU * i / 12.0), mesh.walls)
	_check(core_open, "The broad Y junction keeps its central dark opening free of an internal wall crossbar")
	junction.queue_free()

func _add_planar_crack(chunk: Chunk, axes: Array[Vector3], a: Vector2, b: Vector2, width: float) -> void:
	var from := chunk.face_center + axes[0] * a.x + axes[1] * a.y
	var to := chunk.face_center + axes[0] * b.x + axes[1] * b.y
	chunk._append_visible_crack(from, to, width, width, 1.0, 1, chunk.face_center)

func _body_profile(walls: Array, a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var normal := (b - a).normalized().orthogonal()
	for t: float in [0.2, 0.35, 0.5, 0.65, 0.8]:
		var intervals := _line_intervals(a.lerp(b, t), normal, walls)
		result.append(Vector2(_interval_length(_restrict_intervals(intervals, -width, 0.0)), _interval_length(_restrict_intervals(intervals, 0.0, width))))
	return result

func _healthy_profile(profile: PackedVector2Array, width: float) -> bool:
	for sample in profile:
		if minf(sample.x, sample.y) < width * 0.2 or maxf(sample.x, sample.y) > width * 0.9:
			return false
	return not profile.is_empty()

func _profile_spread(profile: PackedVector2Array) -> float:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2.ZERO
	for sample in profile:
		minimum = minimum.min(sample)
		maximum = maximum.max(sample)
	return maxf(maximum.x - minimum.x, maximum.y - minimum.y)

func _profiles_match(first: PackedVector2Array, second: PackedVector2Array, tolerance: float) -> bool:
	if first.size() != second.size():
		return false
	for i in first.size():
		if first[i].distance_to(second[i]) > tolerance:
			return false
	return true

func _same_wall_mask(first: Array, second: Array, bounds: Rect2) -> bool:
	for x in 37:
		for y in 37:
			var point := bounds.position + bounds.size * Vector2((x + 0.371) / 37.0, (y + 0.619) / 37.0)
			if _inside_union(point, first) != _inside_union(point, second):
				return false
	return true

func _validate_join_width(quads: Array[PackedVector2Array], walls: Array, width: float, label: String) -> void:
	var sampled := 0
	var healthy := true
	for edge: Dictionary in _independent_boundary(quads):
		for endpoint: Vector2 in [edge.a, edge.b]:
			if endpoint.length() > width * 2.5:
				continue
			var other: Vector2 = edge.b if endpoint.distance_to(edge.a) < TOL else edge.a
			if endpoint.distance_to(other) < width * 0.5:
				continue
			var point := endpoint.move_toward(other, width * 0.25)
			var normal := (other - endpoint).normalized().orthogonal()
			var opening := _line_intervals(point, normal, quads)
			var strips := _line_intervals(point, normal, walls)
			var available := _inward_span(opening)
			if absf(available) < width * 0.8:
				continue
			var band := _near_zero_span(strips, signf(available))
			sampled += 1
			healthy = healthy and band >= width * 0.15
	_check(sampled >= 2 and healthy, label + ": wall bands retain positive width next to the shared corner instead of pinching to a line")

func _line_intervals(origin: Vector2, axis: Vector2, polygons: Array) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	var perpendicular := axis.orthogonal()
	for polygon: PackedVector2Array in polygons:
		var cuts: Array[float] = []
		for i in polygon.size():
			var a := polygon[i] - origin
			var b := polygon[(i + 1) % polygon.size()] - origin
			var from := perpendicular.dot(a)
			var to := perpendicular.dot(b)
			if absf(from) < 0.0000001:
				cuts.append(axis.dot(a))
			if (from < 0.0 and to > 0.0) or (from > 0.0 and to < 0.0):
				cuts.append(axis.dot(a.lerp(b, from / (from - to))))
		if cuts.size() >= 2:
			cuts.sort()
			intervals.append(Vector2(cuts[0], cuts[cuts.size() - 1]))
	return _merge_intervals(intervals)

func _merge_intervals(intervals: Array[Vector2]) -> Array[Vector2]:
	intervals.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	var result: Array[Vector2] = []
	for interval in intervals:
		if interval.y <= interval.x + 0.0000001:
			continue
		if not result.is_empty() and interval.x <= result[result.size() - 1].y + TOL:
			result[result.size() - 1].y = maxf(result[result.size() - 1].y, interval.y)
		else:
			result.append(interval)
	return result

func _restrict_intervals(intervals: Array[Vector2], low: float, high: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for interval in intervals:
		if minf(interval.y, high) > maxf(interval.x, low):
			result.append(Vector2(maxf(interval.x, low), minf(interval.y, high)))
	return result

func _interval_length(intervals: Array[Vector2]) -> float:
	var result := 0.0
	for interval in intervals:
		result += interval.y - interval.x
	return result

func _inward_span(intervals: Array[Vector2]) -> float:
	var result := 0.0
	for interval in intervals:
		if interval.x <= TOL and interval.y >= -TOL:
			var candidate := interval.x if absf(interval.x) > absf(interval.y) else interval.y
			if absf(candidate) > absf(result):
				result = candidate
	return result

func _near_zero_span(intervals: Array[Vector2], direction: float) -> float:
	var result := 0.0
	for interval in intervals:
		if interval.x <= TOL and interval.y >= -TOL:
			result = maxf(result, interval.y if direction > 0.0 else -interval.x)
	return result

func _bank_covered_by_walls(a: Vector2, b: Vector2, walls: Array) -> bool:
	var length := a.distance_to(b)
	if length <= TOL:
		return true
	var axis := (b - a).normalized()
	var intervals: Array[Vector2] = []
	for triangle: PackedVector2Array in walls:
		var winding := signf((triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]))
		if winding == 0.0:
			continue
		var low := 0.0
		var high := length
		for i in 3:
			var edge := triangle[(i + 1) % 3] - triangle[i]
			if edge.length_squared() < 0.000000000001:
				continue
			var distance := winding * edge.cross(a - triangle[i]) / edge.length()
			var rate := winding * edge.cross(axis) / edge.length()
			if absf(rate) < 0.00000001:
				if distance < -TOL:
					high = -1.0
			elif rate > 0.0:
				low = maxf(low, (-TOL - distance) / rate)
			else:
				high = minf(high, (-TOL - distance) / rate)
		if high > low:
			intervals.append(Vector2(low, high))
	return _interval_length(_merge_intervals(intervals)) >= length - TOL * 2.0

func _bank_has_width(a: Vector2, b: Vector2, quads: Array[PackedVector2Array], walls: Array) -> bool:
	if a.distance_to(b) <= TOL * 4.0:
		return true
	var normal := (b - a).normalized().orthogonal()
	for t: float in [0.25, 0.5, 0.75]:
		var point := a.lerp(b, t)
		var opening := _inward_span(_line_intervals(point, normal, quads))
		if absf(opening) <= TOL * 4.0:
			continue
		var step := minf(TOL * 3.0, absf(opening) * 0.05)
		if not _inside_union(point + normal * signf(opening) * step, walls):
			return false
	return true

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
	var mesh: ArrayMesh = chunk._crack_mesh.mesh
	var valid := mesh != null
	if not valid:
		return {"valid": false, "floor": [], "walls": []}
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
	return {"valid": valid, "floor": floor_triangles, "walls": wall_triangles}

func _validate_surface(chunk: Chunk, label: String, world: bool = false) -> void:
	if not chunk.get_surface_crack_segments().is_empty():
		_validate_wrapped_surface(chunk, label, world)
		return
	var quads := _source_quads(chunk, world)
	var mesh := _mesh_geometry(chunk, world)
	_validate_union_mesh(quads, mesh, label)

func _validate_union_mesh(quads: Array[PackedVector2Array], mesh: Dictionary, label: String, seams: Array[Dictionary] = []) -> void:
	var boundaries := _independent_boundary(quads)
	var source_edges: Array[Dictionary] = []
	for polygon in quads:
		for i in polygon.size():
			source_edges.append({"a": polygon[i], "b": polygon[(i + 1) % polygon.size()]})
	var bank_boundaries: Array[Dictionary] = []
	for edge in boundaries:
		if not _edge_covered(edge.a, edge.b, seams):
			bank_boundaries.append(edge)
	_check(mesh.valid and not mesh.floor.is_empty() and (bank_boundaries.is_empty() or not mesh.walls.is_empty()), label + ": real mesh has opaque floor and bright walls wherever a crack bank is exposed")
	if not mesh.valid:
		return
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
	# A thin facet can occupy fewer than twenty cells of a rectangular grid.
	# Add source-driven interior samples rather than lowering coverage checks.
	if inside_samples <= 20:
		for quad in quads:
			var center := Vector2.ZERO
			for vertex in quad:
				center += vertex
			center /= float(quad.size())
			for vertex in quad:
				for step in 8:
					var point := center.lerp(vertex, (float(step) + 0.371) / 9.0)
					if _distance_to_edges(point, boundaries) < TOL or not _inside_union(point, quads):
						continue
					inside_samples += 1
					coverage = coverage and _inside_union(point, triangles)
					floor_coverage = floor_coverage and _inside_union(point, mesh.floor)
	_check(inside_samples > 20 and outside_samples > 50 and floor_coverage, label + ": floor covers exactly the independently sampled ribbon union, including holes and gaps; inside=%d outside=%d coverage=%s" % [inside_samples, outside_samples, floor_coverage])
	_check(coverage, label + ": floor/wall footprint equals union; bad point=" + str(first_bad))
	var walls_inside := true
	var first_spill := Vector2.INF
	for triangle: PackedVector2Array in mesh.walls:
		# Every vertex, edge samples, and interior samples of every actual triangle.
		for i in 7:
			for j in range(7 - i):
				var point := triangle[0] * (1.0 - float(i + j) / 6.0) + triangle[1] * (float(i) / 6.0) + triangle[2] * (float(j) / 6.0)
				# For a point outside the union, its nearest source-polygon edge
				# is necessarily an exposed union edge. This avoids a secondary
				# boundary-probe classification at nearly coincident banks.
				if not _inside_union(point, quads) and _distance_to_edges(point, source_edges) > TOL:
					walls_inside = false
					if first_spill == Vector2.INF:
						first_spill = point
						print("CRACK_SURFACE_SPILL %s triangle=%s sample=(%d,%d)" % [label, triangle, i, j])
	_check(walls_inside, label + ": wall vertices and triangle interiors remain within footprint; spill=" + str(first_spill) + " distance=%.9f" % _distance_to_edges(first_spill, boundaries))
	var complete_banks := true
	var visible_banks := true
	for edge: Dictionary in bank_boundaries:
		complete_banks = complete_banks and _bank_covered_by_walls(edge.a, edge.b, mesh.walls)
		visible_banks = visible_banks and _bank_has_width(edge.a, edge.b, quads, mesh.walls)
	_check(complete_banks, label + ": walls cover exterior and hole boundaries without broken junctions")
	_check(visible_banks, label + ": exposed banks have visible inward wall area rather than zero-width triangles")
	if label == "closed_loop":
		_check(not _inside_union(Vector2.ZERO, triangles), "Closed-loop stone island remains unpainted at its center")

func _validate_wrapped_surface(chunk: Chunk, label: String, world: bool) -> void:
	var groups: Dictionary = {}
	var root_junctions := 0
	for segment in chunk.get_surface_crack_segments():
		var id := int(segment.face_id)
		if not groups.has(id):
			groups[id] = []
		groups[id].append(segment)
	for id: int in groups:
		var segments: Array[Dictionary] = []
		segments.assign(groups[id])
		var normal: Vector3 = segments[0].normal
		var origin: Vector3 = segments[0].triangle[0]
		var world_normal := (chunk.mesh_instance.global_basis.inverse().transposed() * normal).normalized() if world else normal
		var world_origin := chunk.mesh_instance.to_global(origin) if world else origin
		var axes := _axes(world_normal)
		var local_axes := _axes(normal)
		var clipped: Array[PackedVector2Array] = []
		# Independently clip the full source ribbon against its actual facet.
		# Do not use the helper's output polygon or outline as the union oracle.
		for segment in segments:
			var ribbon := PackedVector2Array()
			var facet := PackedVector2Array()
			for point: Vector3 in segment.ribbon:
				ribbon.append(_project(point, origin, local_axes))
			for point: Vector3 in segment.triangle:
				facet.append(_project(point, origin, local_axes))
			var polygon := _convex_intersection(ribbon, facet)
			if polygon.size() >= 3:
				# Transform the independently clipped local oracle just as the
				# rendered mesh transforms, without quantizing a second time.
				var projected := PackedVector2Array()
				for point: Vector2 in polygon:
					var local_point := origin + local_axes[0] * point.x + local_axes[1] * point.y
					projected.append(_project(chunk.mesh_instance.to_global(local_point) if world else local_point, world_origin, axes))
				clipped.append(projected)
		_check(not clipped.is_empty(), label + " face %d: original ribbons intersect real stone facets" % id)
		if clipped.is_empty():
			continue
		var seams := _actual_facet_boundaries(chunk, normal, origin, axes, world_origin, world)
		var mesh := _wrapped_mesh_geometry(chunk, segments, normal, origin, axes, world_origin, world, groups, seams)
		_validate_union_mesh(clipped, mesh, label + " face %d" % id, seams)
		if label == "showcase_side15" and not world:
			root_junctions += _validate_strike_junction(chunk, segments, mesh.floor, origin, axes)
	_check(not groups.is_empty(), label + ": actual struck surfaces produce independently checked crack patches")
	if label == "showcase_side15" and not world:
		_check(root_junctions > 0, "Exact side15 fixture exercises the asymmetric three-branch strike junction")

func _validate_strike_junction(chunk: Chunk, segments: Array[Dictionary], floors: Array, origin: Vector3, axes: Array[Vector3]) -> int:
	var root_banks := PackedVector2Array()
	var old_ribbons: Array[PackedVector2Array] = []
	var sources: Dictionary = {}
	var center := _project(chunk.latest_impact_local, origin, axes)
	for segment in segments:
		if bool(segment.get("junction", false)):
			continue
		var ribbon := PackedVector2Array()
		for point: Vector3 in segment.ribbon:
			ribbon.append(_project(point, origin, axes))
		old_ribbons.append(ribbon)
		if Vector3(segment.ribbon_a).distance_to(chunk.latest_impact_local) > TOL or sources.has(int(segment.source_index)):
			continue
		sources[int(segment.source_index)] = true
		root_banks.append(ribbon[0])
		root_banks.append(ribbon[1])
	if sources.size() < 3:
		return 0
	# Derive a small guaranteed root interior from the original branch banks,
	# without consulting the generated junction polygon or production hull.
	var hull := Geometry2D.convex_hull(root_banks)
	if hull.size() > 1 and hull[0].distance_to(hull[hull.size() - 1]) < TOL:
		hull.remove_at(hull.size() - 1)
	var radius := INF
	for i in hull.size():
		var edge := hull[(i + 1) % hull.size()] - hull[i]
		radius = minf(radius, absf(edge.cross(center - hull[i])) / edge.length())
	_check(radius > TOL * 4.0, "Side15 root banks define a measurable central opening")
	var complete := true
	var formerly_missing := 0
	for fraction: float in [0.1, 0.25, 0.4]:
		for i in 72:
			var point := center + Vector2(radius * fraction, 0.0).rotated(TAU * (i + 0.37) / 72.0)
			complete = complete and _inside_union(point, floors)
			if not _inside_union(point, old_ribbons):
				formerly_missing += 1
	_check(formerly_missing > 0, "Side15 root probes include the previously uncovered notch between the original branch caps")
	_check(complete, "Side15 asymmetric root stays fully open in every direction without a stone notch reaching the strike center")
	return 1

func _convex_intersection(first: PackedVector2Array, second: PackedVector2Array) -> PackedVector2Array:
	# Independent vertex/edge-event oracle, rather than the production
	# half-plane walk. Integer polygon clipping loses precision at long,
	# nearly parallel crack banks before a nonuniform world transform.
	var candidates := PackedVector2Array()
	var first_edges: Array[Dictionary] = []
	var second_edges: Array[Dictionary] = []
	for i in first.size():
		first_edges.append({"a": first[i], "b": first[(i + 1) % first.size()]})
	for i in second.size():
		second_edges.append({"a": second[i], "b": second[(i + 1) % second.size()]})
	for point in first:
		if _inside_polygon(point, second) or _distance_to_edges(point, second_edges) < 0.0000003:
			candidates.append(point)
	for point in second:
		if _inside_polygon(point, first) or _distance_to_edges(point, first_edges) < 0.0000003:
			candidates.append(point)
	for a: Dictionary in first_edges:
		var delta_a: Vector2 = a.b - a.a
		for b: Dictionary in second_edges:
			var delta_b: Vector2 = b.b - b.a
			var divisor := delta_a.cross(delta_b)
			if absf(divisor) <= 0.000000000001:
				continue
			var offset: Vector2 = b.a - a.a
			var t := offset.cross(delta_b) / divisor
			var u := offset.cross(delta_a) / divisor
			if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
				candidates.append(Vector2(a.a) + delta_a * t)
	if candidates.size() < 3:
		return PackedVector2Array()
	var hull := Geometry2D.convex_hull(candidates)
	if hull.size() > 1 and hull[0].distance_to(hull[hull.size() - 1]) < 0.0000001:
		hull.remove_at(hull.size() - 1)
	return hull

func _wrapped_mesh_geometry(chunk: Chunk, segments: Array[Dictionary], normal: Vector3, origin: Vector3, axes: Array[Vector3], projected_origin: Vector3, world: bool, groups: Dictionary, seams: Array[Dictionary]) -> Dictionary:
	var floors: Array[PackedVector2Array] = []
	var walls: Array[PackedVector2Array] = []
	var valid := true
	var mesh: ArrayMesh = chunk._crack_mesh.mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		valid = valid and count % 3 == 0 and vertices.size() == colors.size() and vertices.size() == normals.size()
		for i in range(0, count, 3):
			var first := indices[i] if not indices.is_empty() else i
			# The uploaded normals are quantized. Assign each triangle to one
			# nearest source face rather than dropping faces at a 1e-5 cutoff.
			var closest_face := -1
			var closest_distance := INF
			for candidate: int in groups:
				var distance := normals[first].distance_squared_to(groups[candidate][0].normal)
				if distance < closest_distance:
					closest_face = candidate
					closest_distance = distance
			if closest_face != int(segments[0].face_id):
				continue
			valid = valid and sqrt(closest_distance) < 0.00015
			var is_floor := maxf(colors[first].r, maxf(colors[first].g, colors[first].b)) < 0.12
			var depth := FLOOR_DEPTH if is_floor else WALL_DEPTH
			var triangle := PackedVector2Array()
			for j in 3:
				var index := indices[i + j] if not indices.is_empty() else i + j
				var vertex := vertices[index]
				var flat := _remove_surface_offset(vertex, segments, normal, depth, seams)
				var brightness := maxf(colors[index].r, maxf(colors[index].g, colors[index].b))
				valid = valid and vertex.is_finite() and absf((flat - origin).dot(normal)) < TOL and absf(colors[index].a - 1.0) < 0.00001 and (brightness < 0.12 if is_floor else brightness > 0.12)
				var point := chunk._crack_mesh.to_global(vertex) - chunk.mesh_instance.global_basis * (vertex - flat) if world else flat
				triangle.append(_project(point, projected_origin, axes))
			if is_floor:
				floors.append(triangle)
			else:
				walls.append(triangle)
	return {"valid": valid, "floor": floors, "walls": walls}

func _remove_surface_offset(vertex: Vector3, segments: Array[Dictionary], normal: Vector3, depth: float, seams: Array[Dictionary]) -> Vector3:
	var closest := INF
	var flattened := vertex - normal * depth
	# Corner offsets account for the shared physical mesh vertex. Along an
	# edge only the actual stone crease contributes a miter, not a crack bank.
	for segment in segments:
		var polygon: PackedVector3Array = segment.polygon
		var offsets: PackedVector3Array = segment.polygon_offsets
		for i in polygon.size():
			var distance := vertex.distance_to(polygon[i] + offsets[i] * depth)
			var candidate := vertex - offsets[i] * depth
			if distance < closest and distance < TOL * 1.5 and _supported_inverse(candidate, segments, normal):
				closest = distance
				flattened = candidate
	for seam in seams:
		var candidate: Vector3 = vertex - Vector3(seam.offset) * depth
		var edge: Vector3 = seam.local_b - seam.local_a
		var t := clampf((candidate - Vector3(seam.local_a)).dot(edge) / maxf(edge.length_squared(), 0.000000000001), 0.0, 1.0)
		var distance := candidate.distance_to(Vector3(seam.local_a) + edge * t)
		if distance < closest and distance < TOL * 1.5 and _supported_inverse(candidate, segments, normal):
			closest = distance
			flattened = candidate
	return flattened

func _supported_inverse(point: Vector3, segments: Array[Dictionary], normal: Vector3) -> bool:
	# At a crease both a normal-offset point and a miter-offset point may
	# reproduce the same rendered vertex. Require a candidate to belong to
	# an actual clipped source patch; the independent full-ribbon oracle still
	# checks the entire reconstructed triangle, not just these vertices.
	var axes := _axes(normal)
	for segment in segments:
		var polygon: PackedVector3Array = segment.polygon
		if polygon.is_empty() or absf((point - polygon[0]).dot(normal)) > TOL:
			continue
		var projected := PackedVector2Array()
		var edges: Array[Dictionary] = []
		for vertex in polygon:
			projected.append(_project(vertex, polygon[0], axes))
		for i in projected.size():
			edges.append({"a": projected[i], "b": projected[(i + 1) % projected.size()]})
		var probe := _project(point, polygon[0], axes)
		if _inside_polygon(probe, projected) or _distance_to_edges(probe, edges) < TOL:
			return true
	return false

func _actual_facet_boundaries(chunk: Chunk, normal: Vector3, origin: Vector3, axes: Array[Vector3], projected_origin: Vector3, world: bool) -> Array[Dictionary]:
	# Mesh.get_faces() welds nearby coordinates for collision geometry. Read
	# the render surface directly so the oracle uses the stone's exact planes.
	var sources := PackedVector3Array()
	var mesh: Mesh = chunk.mesh_instance.mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			sources.append_array(vertices)
		else:
			for index in indices:
				sources.append(vertices[index])
	var edges: Dictionary = {}
	var adjacent_normals: Dictionary = {}
	for i in range(0, sources.size(), 3):
		var triangle := PackedVector3Array([sources[i], sources[i + 1], sources[i + 2]])
		var triangle_normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
		if triangle_normal.dot((triangle[0] + triangle[1] + triangle[2]) / 3.0 - chunk.gem_socket_center) < 0.0:
			triangle_normal = -triangle_normal
		var coplanar := true
		for point in triangle:
			coplanar = coplanar and absf((point - origin).dot(normal)) < 0.00002
		for j in 3:
			var a := triangle[j]
			var b := triangle[(j + 1) % 3]
			var first := str(a.snapped(Vector3.ONE * 0.00001))
			var second := str(b.snapped(Vector3.ONE * 0.00001))
			var key := first + "/" + second if first < second else second + "/" + first
			if not adjacent_normals.has(key):
				adjacent_normals[key] = []
			adjacent_normals[key].append(triangle_normal)
			if not coplanar:
				continue
			if edges.has(key):
				edges[key].count += 1
			else:
				edges[key] = {"a": a, "b": b, "count": 1, "key": key}
	var result: Array[Dictionary] = []
	for edge: Dictionary in edges.values():
		if int(edge.count) == 1:
			var a: Vector3 = chunk.mesh_instance.to_global(edge.a) if world else edge.a
			var b: Vector3 = chunk.mesh_instance.to_global(edge.b) if world else edge.b
			var offset := normal
			var other_normal := normal
			var least_alignment := 1.0
			for neighbor: Vector3 in adjacent_normals[edge.key]:
				if normal.dot(neighbor) < least_alignment:
					other_normal = neighbor
					least_alignment = normal.dot(neighbor)
			offset = (normal + other_normal) / maxf(1.0 + normal.dot(other_normal), 0.25)
			result.append({"a": _project(a, projected_origin, axes), "b": _project(b, projected_origin, axes), "local_a": edge.a, "local_b": edge.b, "offset": offset})
	return result

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
	return _inside_polygon_at(point.x, point.y, polygon)

func _inside_polygon_at(x: float, y: float, polygon: PackedVector2Array) -> bool:
	var inside := false
	var previous := polygon.size() - 1
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[previous]
		if (a.y > y) != (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		previous = i
	return inside

func _inside_union(point: Vector2, polygons: Array) -> bool:
	return _inside_union_at(point.x, point.y, polygons)

func _inside_union_at(x: float, y: float, polygons: Array) -> bool:
	for polygon: PackedVector2Array in polygons:
		if _inside_polygon_at(x, y, polygon):
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
			var middle_t := (cuts[i] + cuts[i + 1]) * 0.5
			var midpoint_x: float = a.x + (float(edge.b.x) - float(a.x)) * middle_t
			var midpoint_y: float = a.y + (float(edge.b.y) - float(a.y)) * middle_t
			var probe_distance := minf(0.00002, length * 0.08)
			var probe := delta.normalized().orthogonal() * probe_distance
			# Preserve the probe in scalar double precision. Packing its sum
			# into Vector2 rounds a subpixel world-space step back onto the edge.
			if _inside_union_at(midpoint_x + probe.x, midpoint_y + probe.y, quads) != _inside_union_at(midpoint_x - probe.x, midpoint_y - probe.y, quads):
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
		# Clip each finite source segment to the target's tolerance strip.
		# Extrapolating a tiny, quantized bank's direction over a long target
		# incorrectly rejects valid coverage far beyond that bank's endpoints.
		var distance_a := direction.cross(first - a)
		var distance_b := direction.cross(second - a)
		var low := 0.0
		var high := 1.0
		var change := distance_b - distance_a
		if absf(change) < 0.000000000001:
			if absf(distance_a) > TOL:
				continue
		else:
			var enter := (-TOL - distance_a) / change
			var leave := (TOL - distance_a) / change
			low = maxf(low, minf(enter, leave))
			high = minf(high, maxf(enter, leave))
			if low > high:
				continue
		var x := direction.dot(first.lerp(second, low) - a)
		var y := direction.dot(first.lerp(second, high) - a)
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
