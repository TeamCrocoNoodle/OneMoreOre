class_name CrackWrap
extends RefCounted
## Walks a bounded planar crack network across the actual triangulated stone.
## Frames unfold at shared edges; ribbon banks are clipped to each real facet.

const EPS := 0.00001

var _triangles: Array[Dictionary] = []
var _vertices: Array[Vector3] = []
var _vertex_ids: Dictionary = {}
var _vertex_miters: Array[Vector3] = []
var _edges: Dictionary = {}
var _face_boundaries: Dictionary = {}
var _face_normals: Dictionary = {}
var _face_polygons: Dictionary = {}
var _edge_miters: Dictionary = {}
var _surface_offset_cache: Dictionary = {}
var _anchor_hit_cache: Dictionary = {}
var _walk_cache: Dictionary = {}
var _hinge_cache: Dictionary = {}


func configure(triangle_vertices: PackedVector3Array, interior: Vector3) -> void:
	_triangles.clear()
	_vertices.clear()
	_vertex_ids.clear()
	_vertex_miters.clear()
	_edges.clear()
	_face_boundaries.clear()
	_face_normals.clear()
	_face_polygons.clear()
	_edge_miters.clear()
	_surface_offset_cache.clear()
	_anchor_hit_cache.clear()
	_walk_cache.clear()
	_hinge_cache.clear()
	for i in range(0, triangle_vertices.size() - 2, 3):
		var ids := PackedInt32Array([_vertex(triangle_vertices[i]), _vertex(triangle_vertices[i + 1]), _vertex(triangle_vertices[i + 2])])
		var a := _vertices[ids[0]]
		var b := _vertices[ids[1]]
		var c := _vertices[ids[2]]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() <= 0.000000000001:
			continue
		normal = normal.normalized()
		if normal.dot((a + b + c) / 3.0 - interior) < 0.0:
			var swap := ids[1]
			ids[1] = ids[2]
			ids[2] = swap
			normal = -normal
		var index := _triangles.size()
		_triangles.append({"ids": ids, "points": PackedVector3Array([_vertices[ids[0]], _vertices[ids[1]], _vertices[ids[2]]]), "normal": normal, "plane": normal.dot(a), "neighbors": PackedInt32Array([-1, -1, -1]), "face_id": -1})
		for edge in 3:
			var key := _edge_key(ids[edge], ids[(edge + 1) % 3])
			if not _edges.has(key):
				_edges[key] = []
			_edges[key].append(Vector2i(index, edge))
	for uses: Array in _edges.values():
		if uses.size() == 2:
			var a: Vector2i = uses[0]
			var b: Vector2i = uses[1]
			_triangles[a.x]["neighbors"][a.y] = b.x
			_triangles[b.x]["neighbors"][b.y] = a.x
	_build_faces()
	_build_offsets()
	_build_face_polygons()


func get_surface_hit(point: Vector3) -> Dictionary:
	var closest := INF
	var result: Dictionary = {}
	for index in _triangles.size():
		var triangle := _triangle_points(index)
		var projected := _closest_triangle(point, triangle[0], triangle[1], triangle[2])
		var distance := point.distance_squared_to(projected)
		if distance < closest:
			closest = distance
			result = {"point": projected, "normal": _triangles[index]["normal"], "triangle_id": index, "face_id": _triangles[index]["face_id"]}
	return result


func wrap(segments: Array[Dictionary], anchors: Dictionary, reference_normal: Vector3, reach_scale: float = 1.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_surface_offset_cache.clear()
	if _triangles.is_empty() or reach_scale <= 0.0:
		return result
	var states: Dictionary = {}
	var origins: Dictionary = {}
	var reference_axis := reference_normal.normalized()
	for source_index in segments.size():
		var segment := segments[source_index]
		var hit_id := int(segment.get("hit_id", 0))
		if not origins.has(hit_id):
			var anchor: Dictionary = anchors.get(hit_id, {"point": segment.get("impact", segment["a"]), "reference": segment.get("impact", segment["a"])})
			var hit := _anchor_hit(hit_id, anchor["point"])
			if hit.is_empty():
				continue
			var frame := _hinge_rotation(reference_axis, Vector3(hit["normal"]))
			origins[hit_id] = {"point": hit["point"], "reference": anchor.get("reference", segment.get("impact", segment["a"])), "triangle_id": hit["triangle_id"], "frame": frame}
			states[_state_key(hit_id, origins[hit_id]["reference"])] = origins[hit_id].duplicate()
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var reference_delta := b - a
		if reference_delta.length_squared() <= EPS * EPS:
			continue
		var key_a := _state_key(hit_id, a)
		if not states.has(key_a):
			var anchor: Dictionary = origins[hit_id]
			var to_start: Vector3 = a - Vector3(anchor["reference"])
			states[key_a] = _cached_walk(key_a + "_approach", anchor, to_start, reach_scale)["end"]
		var start: Dictionary = states[key_a]
		var walked := _cached_walk(key_a + "_segment", start, reference_delta, reach_scale)
		states[_state_key(hit_id, b)] = walked["end"]
		var pieces: Array[Dictionary] = walked["pieces"]
		if pieces.is_empty():
			continue
		var physical_length := reference_delta.length() * reach_scale
		var reference_direction := reference_delta.normalized()
		var reference_side := reference_axis.cross(reference_direction).normalized()
		var fallback := reference_side * float(segment.get("width", 0.0))
		var side_a: Vector3 = segment.get("side_a", fallback)
		var side_b: Vector3 = segment.get("side_b", fallback)
		var sa := Vector2(side_a.dot(reference_direction), side_a.dot(reference_side))
		var sb := Vector2(side_b.dot(reference_direction), side_b.dot(reference_side))
		var ribbon := PackedVector2Array([-sa, sa, Vector2(physical_length, 0.0) + sb, Vector2(physical_length, 0.0) - sb])
		var patches := _ribbon_patches(pieces, reference_direction, ribbon)
		for patch in patches:
			var triangle_id: int = patch["triangle_id"]
			var pose: Dictionary = patch["pose"]
			var polygon_2d: PackedVector2Array = patch["polygon"]
			var polygon := PackedVector3Array()
			var offsets := PackedVector3Array()
			for point in polygon_2d:
				var surface_point := _snap_surface(_from_chart(point, pose), triangle_id)
				if polygon.is_empty() or polygon[polygon.size() - 1].distance_squared_to(surface_point) > EPS * EPS:
					polygon.append(surface_point)
					offsets.append(_offset_at(surface_point, triangle_id))
			if polygon.size() > 1 and polygon[0].distance_squared_to(polygon[polygon.size() - 1]) <= EPS * EPS:
				polygon.remove_at(polygon.size() - 1)
				offsets.remove_at(offsets.size() - 1)
			if polygon.size() < 3:
				continue
			var center_piece: Dictionary = {}
			for piece in pieces:
				if int(piece["triangle_id"]) == triangle_id:
					center_piece = piece
					break
			var has_centerline := not center_piece.is_empty()
			var section := Vector2.ZERO
			var middle_y := 0.0
			if has_centerline:
				section = Vector2(float(center_piece["start_distance"]), float(center_piece["end_distance"]))
			else:
				for point in polygon_2d:
					middle_y += point.y
				middle_y /= float(polygon_2d.size())
				section = _horizontal_section(polygon_2d, middle_y)
			var t_a := clampf(section.x / physical_length, 0.0, 1.0)
			var t_b := clampf(section.y / physical_length, 0.0, 1.0)
			var actual_a := _snap_surface(_from_chart(Vector2(section.x, middle_y), pose), triangle_id)
			var actual_b := _snap_surface(_from_chart(Vector2(section.y, middle_y), pose), triangle_id)
			if has_centerline:
				actual_a = _snap_surface(center_piece["a"], triangle_id)
				actual_b = _snap_surface(center_piece["b"], triangle_id)
			var full_ribbon := PackedVector3Array()
			for point in ribbon:
				full_ribbon.append(_from_chart(point, pose))
			var mapped := segment.duplicate()
			mapped["a"] = actual_a
			mapped["b"] = actual_b
			mapped["normal"] = _triangles[triangle_id]["normal"]
			mapped["face_id"] = _triangles[triangle_id]["face_id"]
			mapped["triangle_id"] = triangle_id
			mapped["triangle"] = _triangle_points(triangle_id)
			mapped["polygon"] = polygon
			mapped["polygon_offsets"] = offsets
			mapped["offset_a"] = _offset_at(actual_a, triangle_id)
			mapped["offset_b"] = _offset_at(actual_b, triangle_id)
			mapped["ribbon"] = full_ribbon
			mapped["ribbon_a"] = _from_chart(Vector2.ZERO, pose)
			mapped["ribbon_b"] = _from_chart(Vector2(physical_length, 0.0), pose)
			mapped["has_centerline"] = has_centerline
			mapped["source_index"] = source_index
			mapped["source_t0"] = t_a
			mapped["source_t1"] = t_b
			mapped["reference_a"] = a.lerp(b, t_a)
			mapped["reference_b"] = a.lerp(b, t_b)
			mapped["reference_impact"] = segment.get("impact", a)
			mapped["impact"] = origins[hit_id]["point"]
			mapped["width_a"] = lerpf(float(segment.get("width_a", segment.get("width", 0.0))), float(segment.get("width_b", segment.get("width", 0.0))), t_a)
			mapped["width_b"] = lerpf(float(segment.get("width_a", segment.get("width", 0.0))), float(segment.get("width_b", segment.get("width", 0.0))), t_b)
			mapped["width"] = maxf(float(mapped["width_a"]), float(mapped["width_b"]))
			var interpolated_a := sa.lerp(sb, t_a)
			var interpolated_b := sa.lerp(sb, t_b)
			mapped["side_a"] = Vector3(pose["x"]) * interpolated_a.x + Vector3(pose["y"]) * interpolated_a.y
			mapped["side_b"] = Vector3(pose["x"]) * interpolated_b.x + Vector3(pose["y"]) * interpolated_b.y
			result.append(mapped)
	result.append_array(_root_junctions(segments, states, reference_axis))
	return result


func _root_junctions(segments: Array[Dictionary], states: Dictionary, reference_axis: Vector3) -> Array[Dictionary]:
	# Three perpendicular start caps otherwise leave a triangular bite at the
	# common strike. Fill only the convex hull of their existing bank endpoints;
	# centerlines, physical widths, tip positions and emitted rays stay intact.
	var groups: Dictionary = {}
	for source_index in segments.size():
		var source := segments[source_index]
		var key := _state_key(int(source.get("hit_id", 0)), source["a"])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(source_index)
	var result: Array[Dictionary] = []
	var chart_x := reference_axis.cross(Vector3.UP).normalized()
	if chart_x.length_squared() < 0.1:
		chart_x = reference_axis.cross(Vector3.RIGHT).normalized()
	var chart_y := reference_axis.cross(chart_x).normalized()
	for key: String in groups:
		var indices: Array = groups[key]
		if indices.size() < 3 or not states.has(key):
			continue
		var banks := PackedVector2Array()
		var width := 0.0
		for source_index: int in indices:
			var source := segments[source_index]
			var fallback := reference_axis.cross(Vector3(source["b"]) - Vector3(source["a"])).normalized() * float(source.get("width_a", source.get("width", 0.0)))
			var side: Vector3 = source.get("side_a", fallback)
			var bank := Vector2(side.dot(chart_x), side.dot(chart_y))
			banks.append(bank)
			banks.append(-bank)
			width = maxf(width, side.length())
		var hull := Geometry2D.convex_hull(banks)
		if hull.size() > 1 and hull[0].distance_squared_to(hull[hull.size() - 1]) <= EPS * EPS:
			hull.remove_at(hull.size() - 1)
		if hull.size() < 3 or absf(_area(hull)) <= EPS * EPS:
			continue
		var state: Dictionary = states[key]
		var seed: Array[Dictionary] = [{"a": state["point"], "frame": state["frame"], "triangle_id": state["triangle_id"], "start_distance": 0.0}]
		var patches := _ribbon_patches(seed, chart_x, hull)
		for patch in patches:
			var triangle_id := int(patch["triangle_id"])
			var pose: Dictionary = patch["pose"]
			var polygon := PackedVector3Array()
			var offsets := PackedVector3Array()
			for point: Vector2 in patch["polygon"]:
				var actual := _snap_surface(_from_chart(point, pose), triangle_id)
				if polygon.is_empty() or polygon[polygon.size() - 1].distance_squared_to(actual) > EPS * EPS:
					polygon.append(actual)
					offsets.append(_offset_at(actual, triangle_id))
			if polygon.size() > 1 and polygon[0].distance_squared_to(polygon[polygon.size() - 1]) <= EPS * EPS:
				polygon.remove_at(polygon.size() - 1)
				offsets.remove_at(offsets.size() - 1)
			if polygon.size() < 3:
				continue
			var full_hull := PackedVector3Array()
			for point in hull:
				full_hull.append(_from_chart(point, pose))
			var a := polygon[0]
			var b := polygon[1]
			for first in polygon:
				for second in polygon:
					if first.distance_squared_to(second) > a.distance_squared_to(b):
						a = first
						b = second
			var mapped := segments[int(indices[0])].duplicate()
			var normal: Vector3 = _triangles[triangle_id]["normal"]
			mapped.merge({
				"a": a, "b": b, "normal": normal, "face_id": _triangles[triangle_id]["face_id"],
				"triangle_id": triangle_id, "triangle": _triangle_points(triangle_id),
				"polygon": polygon, "polygon_offsets": offsets,
				"offset_a": _offset_at(a, triangle_id), "offset_b": _offset_at(b, triangle_id),
				"ribbon": full_hull, "ribbon_a": a, "ribbon_b": b,
				"has_centerline": false, "junction": true,
				"junction_center": _from_chart(Vector2.ZERO, pose),
				"junction_source_indices": PackedInt32Array(indices),
				"source_index": int(indices[0]), "source_t0": 0.0, "source_t1": 0.0,
				"reference_a": segments[int(indices[0])]["a"], "reference_b": segments[int(indices[0])]["a"],
				"width": width, "width_a": width, "width_b": width,
				"side_a": normal.cross(b - a).normalized() * width,
				"side_b": normal.cross(b - a).normalized() * width,
				"impact": state["point"],
			}, true)
			result.append(mapped)
	return result


func is_surface_edge(a: Vector3, b: Vector3, face_id: int) -> bool:
	for edge: Vector2i in _face_boundaries.get(face_id, []):
		var first := _vertices[edge.x]
		var second := _vertices[edge.y]
		if _closest_segment(a, first, second).distance_to(a) <= EPS * 3.0 and _closest_segment(b, first, second).distance_to(b) <= EPS * 3.0:
			return true
	return false


func get_face_polygon(face_id: int) -> PackedVector3Array:
	# Only genuinely convex, coplanar groups have a combined clip polygon.
	# A nonconvex group must retain its original triangle-clipped patches.
	return _face_polygons.get(face_id, PackedVector3Array())


func surface_offset(point: Vector3, face_id: int) -> Vector3:
	var key := _state_key(face_id, point)
	if _surface_offset_cache.has(key):
		return _surface_offset_cache[key]
	var offset: Vector3 = _face_normals.get(face_id, Vector3.UP)
	for edge: Vector2i in _face_boundaries.get(face_id, []):
		var a := _vertices[edge.x]
		var b := _vertices[edge.y]
		if point.distance_squared_to(a) <= EPS * EPS * 9.0:
			offset = _vertex_miters[edge.x]
			break
		if point.distance_squared_to(b) <= EPS * EPS * 9.0:
			offset = _vertex_miters[edge.y]
			break
		if point.distance_squared_to(_closest_segment(point, a, b)) <= EPS * EPS * 9.0:
			offset = _edge_miters[edge]
			break
	_surface_offset_cache[key] = offset
	return offset


func coalesce(segments: Array[Dictionary]) -> Array[Dictionary]:
	# A front cap is triangulated as a fan, but its crack need not remain a
	# dozen render/light patches. Combine only the same unfolded source ribbon
	# on a verified convex coplanar face, and verify that its area is unchanged.
	var result: Array[Dictionary] = []
	var groups: Dictionary = {}
	for segment in segments:
		if bool(segment.get("junction", false)):
			result.append(segment)
			continue
		var face := int(segment["face_id"])
		if get_face_polygon(face).is_empty():
			result.append(segment)
			continue
		var key := Vector2i(face, int(segment["source_index"]))
		if not groups.has(key):
			groups[key] = []
		var matched := false
		for batch: Array in groups[key]:
			if _same_ribbon(segment["ribbon"], batch[0]["ribbon"]):
				batch.append(segment)
				matched = true
				break
		if not matched:
			groups[key].append([segment])
	for batches: Array in groups.values():
		for batch: Array in batches:
			if batch.size() == 1:
				result.append(batch[0])
				continue
			var merged := _coalesce_batch(batch)
			if merged.is_empty():
				for segment: Dictionary in batch:
					result.append(segment)
			else:
				result.append(merged)
	return result


func _coalesce_batch(batch: Array) -> Dictionary:
	var first: Dictionary = batch[0]
	var face := int(first["face_id"])
	var face_polygon := get_face_polygon(face)
	var normal: Vector3 = _face_normals[face]
	var origin: Vector3 = first["ribbon_a"]
	var x := (Vector3(first["ribbon_b"]) - origin).normalized()
	x = (x - normal * x.dot(normal)).normalized()
	var y := normal.cross(x).normalized()
	var pose := {"origin": origin, "chart_origin": Vector2.ZERO, "x": x, "y": y}
	var subject := PackedVector2Array()
	var boundary := PackedVector2Array()
	for point: Vector3 in first["ribbon"]:
		subject.append(_to_chart(point, pose))
	for point in face_polygon:
		boundary.append(_to_chart(point, pose))
	if _area(boundary) < 0.0:
		boundary.reverse()
	var clipped := _clip_polygon(subject, boundary)
	if clipped.size() < 3:
		return {}
	var previous_area := 0.0
	var min_t := INF
	var max_t := -INF
	var first_piece: Dictionary = {}
	var last_piece: Dictionary = {}
	var triangle_ids := PackedInt32Array()
	for row: Dictionary in batch:
		var polygon := PackedVector2Array()
		for point: Vector3 in row["polygon"]:
			polygon.append(_to_chart(point, pose))
		previous_area += absf(_area(polygon))
		triangle_ids.append(int(row["triangle_id"]))
		if bool(row["has_centerline"]):
			if float(row["source_t0"]) < min_t:
				min_t = float(row["source_t0"])
				first_piece = row
			if float(row["source_t1"]) > max_t:
				max_t = float(row["source_t1"])
				last_piece = row
	if absf(previous_area - absf(_area(clipped))) > maxf(EPS * EPS * 16.0, previous_area * 0.00015):
		return {}
	var polygon := PackedVector3Array()
	var offsets := PackedVector3Array()
	for point in clipped:
		var actual := _snap_face_surface(_from_chart(point, pose), face)
		if polygon.is_empty() or polygon[polygon.size() - 1].distance_squared_to(actual) > EPS * EPS:
			polygon.append(actual)
			offsets.append(surface_offset(actual, face))
	if polygon.size() > 1 and polygon[0].distance_squared_to(polygon[polygon.size() - 1]) <= EPS * EPS:
		polygon.remove_at(polygon.size() - 1)
		offsets.remove_at(offsets.size() - 1)
	if polygon.size() < 3:
		return {}
	var merged := first.duplicate()
	merged["polygon"] = polygon
	merged["polygon_offsets"] = offsets
	merged["normal"] = normal
	merged["triangle"] = face_polygon
	merged["triangle_ids"] = triangle_ids
	merged["coalesced"] = true
	merged["has_centerline"] = not first_piece.is_empty()
	if not first_piece.is_empty():
		for suffix: String in ["a", "b"]:
			var source := first_piece if suffix == "a" else last_piece
			merged[suffix] = source[suffix]
			merged["reference_" + suffix] = source["reference_" + suffix]
			merged["width_" + suffix] = source["width_" + suffix]
			merged["side_" + suffix] = source["side_" + suffix]
		merged["source_t0"] = min_t
		merged["source_t1"] = max_t
		merged["width"] = maxf(float(merged["width_a"]), float(merged["width_b"]))
	merged["offset_a"] = surface_offset(merged["a"], face)
	merged["offset_b"] = surface_offset(merged["b"], face)
	return merged


func _same_ribbon(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_squared_to(b[i]) > EPS * EPS * 9.0:
			return false
	return true


func _anchor_hit(hit_id: int, point: Vector3) -> Dictionary:
	if _anchor_hit_cache.has(hit_id):
		var cached: Dictionary = _anchor_hit_cache[hit_id]
		if Vector3(cached["query"]) == point:
			return cached["hit"]
	var hit := get_surface_hit(point)
	_anchor_hit_cache[hit_id] = {"query": point, "hit": hit}
	return hit


func _cached_walk(key: String, start: Dictionary, delta: Vector3, reach: float) -> Dictionary:
	# Completed chart sections keep their endpoints and transported frame.
	# Growing endpoints, a moved/reanchored hit, or a changed reach/frame
	# replace the entry; configure clears all geometry-dependent entries.
	if _walk_cache.has(key):
		var cached: Dictionary = _walk_cache[key]
		if Vector3(cached["point"]) == Vector3(start["point"]) and int(cached["triangle_id"]) == int(start["triangle_id"]) and Basis(cached["frame"]) == Basis(start["frame"]) and Vector3(cached["delta"]) == delta and float(cached["reach"]) == reach:
			return cached["walk"]
	var walked := _walk(start, delta, reach)
	_walk_cache[key] = {"point": start["point"], "triangle_id": start["triangle_id"], "frame": start["frame"], "delta": delta, "reach": reach, "walk": walked}
	return walked


func _walk(start: Dictionary, reference_delta: Vector3, scale: float) -> Dictionary:
	var state := start.duplicate()
	var pieces: Array[Dictionary] = []
	var remaining := reference_delta.length() * scale
	if remaining <= EPS:
		return {"end": state, "pieces": pieces}
	var reference_direction := reference_delta.normalized()
	var traveled := 0.0
	var crossings: Dictionary = {}
	for guard in _triangles.size() * 2 + 4:
		var triangle_id := int(state["triangle_id"])
		var triangle := _triangles[triangle_id]
		var normal: Vector3 = triangle["normal"]
		var point: Vector3 = state["point"]
		var frame: Basis = state["frame"]
		var heading := frame * reference_direction
		heading = (heading - normal * heading.dot(normal)).normalized()
		if heading.length_squared() < 0.5:
			break
		var nearest := remaining
		var exit_edge := -1
		var ids: PackedInt32Array = triangle["ids"]
		for edge in 3:
			var a := _vertices[ids[edge]]
			var b := _vertices[ids[(edge + 1) % 3]]
			var inward := normal.cross(b - a).normalized()
			var rate := inward.dot(heading)
			if rate >= -0.000001:
				continue
			var distance := -inward.dot(point - a) / rate
			if distance >= -EPS * 3.0 and distance < nearest:
				nearest = maxf(distance, 0.0)
				exit_edge = edge
		var endpoint := point + heading * nearest
		if exit_edge >= 0:
			endpoint = _closest_segment(endpoint, _vertices[ids[exit_edge]], _vertices[ids[(exit_edge + 1) % 3]])
		if nearest > EPS:
			pieces.append({"a": point, "b": endpoint, "triangle_id": triangle_id, "frame": frame, "start_distance": traveled, "end_distance": traveled + nearest})
		traveled += nearest
		remaining -= nearest
		state["point"] = endpoint
		if remaining <= EPS or exit_edge < 0:
			break
		var neighbor := int(triangle["neighbors"][exit_edge])
		var crossing := Vector2i(triangle_id, neighbor)
		if neighbor < 0 or crossings.has(crossing):
			break
		crossings[crossing] = true
		var rotation := _surface_hinge(triangle_id, neighbor)
		state["frame"] = rotation * frame
		state["triangle_id"] = neighbor
	return {"end": state, "pieces": pieces}


func _ribbon_patches(pieces: Array[Dictionary], reference_direction: Vector3, ribbon: PackedVector2Array) -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	var poses: Dictionary = {}
	var queue: Array[int] = []
	for piece in pieces:
		var index := int(piece["triangle_id"])
		if poses.has(index):
			continue
		var normal: Vector3 = _triangles[index]["normal"]
		var x := Basis(piece["frame"]) * reference_direction
		x = (x - normal * x.dot(normal)).normalized()
		var y := normal.cross(x).normalized()
		poses[index] = {"origin": piece["a"], "chart_origin": Vector2(float(piece["start_distance"]), 0.0), "x": x, "y": y}
		queue.append(index)
	var cursor := 0
	var ribbon_bounds := _bounds(ribbon).grow(EPS)
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		var pose: Dictionary = poses[index]
		var triangle := _triangle_points(index)
		var chart_triangle := PackedVector2Array()
		for point in triangle:
			chart_triangle.append(_to_chart(point, pose))
		if not ribbon_bounds.intersects(_bounds(chart_triangle).grow(EPS), true):
			continue
		var clipped := _clip_polygon(ribbon, chart_triangle)
		if clipped.size() < 3 or absf(_area(clipped)) <= EPS * EPS:
			continue
		patches.append({"triangle_id": index, "pose": pose, "polygon": clipped})
		for edge in 3:
			var neighbor := int(_triangles[index]["neighbors"][edge])
			if neighbor < 0 or poses.has(neighbor):
				continue
			var anchor := triangle[edge]
			var next_normal: Vector3 = _triangles[neighbor]["normal"]
			var rotation := _surface_hinge(index, neighbor)
			var next_x := rotation * Vector3(pose["x"])
			next_x = (next_x - next_normal * next_x.dot(next_normal)).normalized()
			poses[neighbor] = {"origin": anchor, "chart_origin": _to_chart(anchor, pose), "x": next_x, "y": next_normal.cross(next_x).normalized()}
			queue.append(neighbor)
	return patches


func _build_faces() -> void:
	for first in _triangles.size():
		if int(_triangles[first]["face_id"]) >= 0:
			continue
		var normal: Vector3 = _triangles[first]["normal"]
		var plane := float(_triangles[first]["plane"])
		_face_normals[first] = normal
		var queue: Array[int] = [first]
		_triangles[first]["face_id"] = first
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			for neighbor in _triangles[current]["neighbors"]:
				if neighbor < 0 or int(_triangles[neighbor]["face_id"]) >= 0:
					continue
				if normal.dot(_triangles[neighbor]["normal"]) > 0.999999 and absf(plane - float(_triangles[neighbor]["plane"])) < EPS:
					_triangles[neighbor]["face_id"] = first
					queue.append(neighbor)
	for key: Vector2i in _edges:
		var uses: Array = _edges[key]
		if uses.size() == 2 and _triangles[uses[0].x]["face_id"] == _triangles[uses[1].x]["face_id"]:
			continue
		for use: Vector2i in uses:
			var face := int(_triangles[use.x]["face_id"])
			if not _face_boundaries.has(face):
				_face_boundaries[face] = []
			_face_boundaries[face].append(key)


func _build_offsets() -> void:
	var faces: Array[Dictionary] = []
	for vertex in _vertices:
		faces.append({})
	for triangle in _triangles:
		for vertex in triangle["ids"]:
			faces[vertex][int(triangle["face_id"])] = true
	for adjacent in faces:
		var normal := Vector3.ZERO
		for face: int in adjacent:
			normal += Vector3(_face_normals[face])
		normal = normal.normalized()
		var clearance := 1.0
		for face: int in adjacent:
			clearance = minf(clearance, normal.dot(_face_normals[face]))
		_vertex_miters.append(normal / maxf(clearance, 0.25))
	for edge: Vector2i in _edges:
		var uses: Array = _edges[edge]
		var first: Vector3 = _triangles[uses[0].x]["normal"]
		var offset := first
		if uses.size() == 2:
			var second: Vector3 = _triangles[uses[1].x]["normal"]
			offset = (first + second) / maxf(1.0 + first.dot(second), 0.25)
		_edge_miters[edge] = offset


func _build_face_polygons() -> void:
	var groups: Dictionary = {}
	for index in _triangles.size():
		var face := int(_triangles[index]["face_id"])
		if not groups.has(face):
			groups[face] = {"vertices": {}, "area": 0.0}
		var triangle := _triangle_points(index)
		groups[face]["area"] += (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).length() * 0.5
		for vertex in _triangles[index]["ids"]:
			groups[face]["vertices"][int(vertex)] = true
	for face: int in groups:
		var normal: Vector3 = _face_normals[face]
		var u := normal.cross(Vector3.UP).normalized()
		if u.length_squared() < 0.1:
			u = normal.cross(Vector3.RIGHT).normalized()
		var v := normal.cross(u).normalized()
		var plane := float(_triangles[face]["plane"])
		var projected := PackedVector2Array()
		var originals := PackedVector3Array()
		var coplanar := true
		for id: int in groups[face]["vertices"]:
			var point := _vertices[id]
			coplanar = coplanar and absf(normal.dot(point) - plane) <= EPS * 2.0
			projected.append(Vector2(point.dot(u), point.dot(v)))
			originals.append(point)
		if not coplanar:
			continue
		var hull := Geometry2D.convex_hull(projected)
		if hull.size() > 1 and hull[0].distance_squared_to(hull[hull.size() - 1]) < EPS * EPS:
			hull.remove_at(hull.size() - 1)
		var area := float(groups[face]["area"])
		if hull.size() < 3 or absf(absf(_area(hull)) - area) > maxf(EPS * EPS * 8.0, area * 0.00001):
			continue
		var polygon := PackedVector3Array()
		for point in hull:
			var closest := 0
			var distance := INF
			for i in projected.size():
				var candidate := point.distance_squared_to(projected[i])
				if candidate < distance:
					distance = candidate
					closest = i
			polygon.append(originals[closest])
		_face_polygons[face] = polygon


func _offset_at(point: Vector3, triangle_id: int) -> Vector3:
	var ids: PackedInt32Array = _triangles[triangle_id]["ids"]
	for id in ids:
		if point.distance_squared_to(_vertices[id]) <= EPS * EPS * 9.0:
			return _vertex_miters[id]
	var normal: Vector3 = _triangles[triangle_id]["normal"]
	for edge in 3:
		if point.distance_to(_closest_segment(point, _vertices[ids[edge]], _vertices[ids[(edge + 1) % 3]])) <= EPS * 3.0:
			var neighbor := int(_triangles[triangle_id]["neighbors"][edge])
			if neighbor >= 0:
				var other: Vector3 = _triangles[neighbor]["normal"]
				return (normal + other) / maxf(1.0 + normal.dot(other), 0.25)
	return normal


func _snap_surface(point: Vector3, triangle_id: int) -> Vector3:
	var ids: PackedInt32Array = _triangles[triangle_id]["ids"]
	for id in ids:
		if point.distance_squared_to(_vertices[id]) <= EPS * EPS * 9.0:
			return _vertices[id]
	for edge in 3:
		var key := _edge_key(ids[edge], ids[(edge + 1) % 3])
		var a := _vertices[key.x]
		var b := _vertices[key.y]
		var nearest := _closest_segment(point, a, b)
		if nearest.distance_squared_to(point) <= EPS * EPS * 9.0:
			var length := a.distance_to(b)
			var along := roundf(a.distance_to(nearest) / EPS) * EPS
			return a.lerp(b, clampf(along / length, 0.0, 1.0))
	return point


func _snap_face_surface(point: Vector3, face_id: int) -> Vector3:
	for edge: Vector2i in _face_boundaries.get(face_id, []):
		var a := _vertices[edge.x]
		var b := _vertices[edge.y]
		if point.distance_squared_to(a) <= EPS * EPS * 9.0:
			return a
		if point.distance_squared_to(b) <= EPS * EPS * 9.0:
			return b
		var nearest := _closest_segment(point, a, b)
		if nearest.distance_squared_to(point) <= EPS * EPS * 9.0:
			var length := a.distance_to(b)
			var along := roundf(a.distance_to(nearest) / EPS) * EPS
			return a.lerp(b, clampf(along / length, 0.0, 1.0))
	return point


func _triangle_points(index: int) -> PackedVector3Array:
	return _triangles[index]["points"]


func _surface_hinge(from: int, to: int) -> Basis:
	var key := Vector2i(from, to)
	if not _hinge_cache.has(key):
		_hinge_cache[key] = _hinge_rotation(_triangles[from]["normal"], _triangles[to]["normal"])
	return _hinge_cache[key]


func _clip_polygon(subject: PackedVector2Array, triangle: PackedVector2Array) -> PackedVector2Array:
	var result := subject
	for edge in triangle.size():
		var output := PackedVector2Array()
		var a := triangle[edge]
		var delta := triangle[(edge + 1) % triangle.size()] - a
		for i in result.size():
			var point := result[i]
			var next := result[(i + 1) % result.size()]
			var d_a := delta.cross(point - a)
			var d_b := delta.cross(next - a)
			if d_a >= 0.0:
				output.append(point)
			if (d_a > 0.0 and d_b < 0.0) or (d_a < 0.0 and d_b > 0.0):
				output.append(point.lerp(next, d_a / (d_a - d_b)))
		result = output
		if result.is_empty():
			break
	return result


func _horizontal_section(polygon: PackedVector2Array, y: float) -> Vector2:
	var low := INF
	var high := -INF
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		if y < minf(a.y, b.y) - EPS or y > maxf(a.y, b.y) + EPS:
			continue
		if absf(a.y - b.y) <= EPS:
			low = minf(low, minf(a.x, b.x))
			high = maxf(high, maxf(a.x, b.x))
		else:
			var x := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
			low = minf(low, x)
			high = maxf(high, x)
	return Vector2(low, high)


func _to_chart(point: Vector3, pose: Dictionary) -> Vector2:
	var delta := point - Vector3(pose["origin"])
	return Vector2(pose["chart_origin"]) + Vector2(delta.dot(pose["x"]), delta.dot(pose["y"]))


func _from_chart(point: Vector2, pose: Dictionary) -> Vector3:
	var delta := point - Vector2(pose["chart_origin"])
	return Vector3(pose["origin"]) + Vector3(pose["x"]) * delta.x + Vector3(pose["y"]) * delta.y


func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		result = result.expand(point)
	return result


func _area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in polygon.size():
		result += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return result * 0.5


func _closest_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var delta := b - a
	return a + delta * clampf((point - a).dot(delta) / maxf(delta.length_squared(), 0.000000000001), 0.0, 1.0)


func _closest_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * d1 / (d1 - d3)
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * d2 / (d2 - d6)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * (d4 - d3) / (d4 - d3 + d5 - d6)
	var inverse := 1.0 / (va + vb + vc)
	return a + ab * vb * inverse + ac * vc * inverse


func _vertex(point: Vector3) -> int:
	var key := Vector3i(roundi(point.x / EPS), roundi(point.y / EPS), roundi(point.z / EPS))
	if not _vertex_ids.has(key):
		_vertex_ids[key] = _vertices.size()
		_vertices.append(point)
	return int(_vertex_ids[key])


func _edge_key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


func _state_key(hit_id: int, point: Vector3) -> String:
	return "%d:%d,%d,%d" % [hit_id, roundi(point.x / EPS), roundi(point.y / EPS), roundi(point.z / EPS)]


func _hinge_rotation(from: Vector3, to: Vector3) -> Basis:
	# Preserve even shallow facet angles. The convenience from/to quaternion
	# can treat nearly parallel normals as equal, accumulating chart drift.
	var cross := from.cross(to)
	var length := cross.length()
	var cosine := clampf(from.dot(to), -1.0, 1.0)
	if length > 0.00000001:
		return Basis(cross / length, atan2(length, cosine))
	if cosine >= 0.0:
		return Basis.IDENTITY
	var axis := from.cross(Vector3.UP).normalized()
	if axis.length_squared() < 0.1:
		axis = from.cross(Vector3.RIGHT).normalized()
	return Basis(axis, PI)
