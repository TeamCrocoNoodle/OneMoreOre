extends "res://tests/validate_crack_wrap.gd"
## A root hub fills only the convex hull of existing root banks, without
## changing any physical centerline or branch width.


func _run() -> void:
	var source: Array[Dictionary] = []
	for i in 3:
		var angle := deg_to_rad([95.0, 182.0, 248.0][i])
		source.append(_segment(Vector3.ZERO, Vector3(cos(angle), sin(angle), 0.0) * 0.38, Vector3.BACK, [0.08, 0.055, 0.065][i], 0.012, 13))
	var banks := PackedVector2Array()
	for segment in source:
		var side: Vector3 = segment.side_a
		banks.append(Vector2(side.x, side.y))
		banks.append(-Vector2(side.x, side.y))
	var hull := Geometry2D.convex_hull(banks)
	if hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	var expected_area := absf(_hull_area(hull))
	for entry: Dictionary in [
		{"anchor": Vector3(0.0, 0.15, 1.0), "reach": 1.0, "label": "front root"},
		{"anchor": Vector3(0.99, 0.15, 1.0), "reach": 1.0, "label": "root crossing an actual crease"},
		{"anchor": Vector3(0.99, 0.15, 1.0), "reach": 3.2, "label": "long branches retain original hub width"},
	]:
		var wrapper = Wrap.new()
		wrapper.configure(_cube(), Vector3.ZERO)
		var anchors := {13: {"point": entry.anchor, "reference": Vector3.ZERO}}
		var output: Array[Dictionary] = wrapper.wrap(source, anchors, Vector3.BACK, entry.reach)
		var hubs: Array[Dictionary] = []
		var ordinary: Array[Dictionary] = []
		for row in output:
			if bool(row.get("junction", false)):
				hubs.append(row)
			else:
				ordinary.append(row)
		_check(not hubs.is_empty() and hubs.size() <= 4, entry.label + ": the hub is a bounded local surface patch")
		_check(absf(_surface_area(hubs) - expected_area) < 0.000005, entry.label + ": unfolded patch area is exactly the existing bank hull")
		var valid := true
		for row in hubs:
			valid = valid and not bool(row.has_centerline) and row.junction_source_indices == PackedInt32Array([0, 1, 2]) and row.ribbon.size() == hull.size()
			var triangle: PackedVector3Array = row.triangle
			for point: Vector3 in row.polygon:
				valid = valid and _inside_triangle(point, triangle[0], triangle[1], triangle[2])
		_check(valid, entry.label + ": every clipped hub vertex lies on its real triangle and contributes no new line")
		var coverage := true
		var repaired_samples := 0
		var tested := 0
		for x in range(-16, 17):
			for y in range(-16, 17):
				var point_2d := Vector2(x, y) * 0.005
				if not Geometry2D.is_point_in_polygon(point_2d, hull):
					continue
				var point: Vector3 = entry.anchor + Vector3(point_2d.x, point_2d.y, 0.0)
				if point.x > 1.0:
					point = Vector3(1.0, point.y, 2.0 - point.x)
				coverage = coverage and _covered_by_polygons(point, output)
				repaired_samples += 0 if _covered_by_polygons(point, ordinary) else 1
				tested += 1
		_check(tested > 100 and coverage, entry.label + ": the whole independent hull is continuously covered")
		_check(repaired_samples > 0, entry.label + ": the actual backwards root notch is filled")
		var unchanged := true
		var regular_count := 0
		for i in source.size():
			var one: Array[Dictionary] = [source[i]]
			var separately: Array[Dictionary] = wrapper.wrap(one, anchors, Vector3.BACK, entry.reach)
			for expected in separately:
				expected.source_index = i
				unchanged = unchanged and ordinary[regular_count] == expected
				regular_count += 1
		_check(unchanged and regular_count == ordinary.size(), entry.label + ": all pre-existing branch metadata and geometry are exactly unchanged")
		var combined: Array[Dictionary] = wrapper.coalesce(output)
		var combined_hubs: Array[Dictionary] = []
		for row in combined:
			if bool(row.get("junction", false)):
				combined_hubs.append(row)
		_check(combined_hubs == hubs, entry.label + ": coalescing cannot confuse the hub with a source ribbon")
	print("CRACK_JUNCTION_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _covered_by_polygons(point: Vector3, segments: Array[Dictionary]) -> bool:
	for row in segments:
		var polygon: PackedVector3Array = row.polygon
		for i in range(1, polygon.size() - 1):
			if _inside_triangle(point, polygon[0], polygon[i], polygon[i + 1]):
				return true
	return false


func _hull_area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in polygon.size():
		result += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return result * 0.5
