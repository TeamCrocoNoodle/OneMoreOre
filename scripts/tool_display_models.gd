extends RefCounted
## Shop models share the actual equipped tool geometry. Ownership is held by MainTools.

const Visual = preload("res://scripts/tool_visual.gd")
const Tools = preload("res://scripts/main_tools.gd")
const AuxTools = preload("res://scripts/aux_tools.gd")
const AuxVisual = preload("res://scripts/aux_tool_visual.gd")
const DISPLAY_ANGLES := [-0.48, -0.42, -0.46, -0.12, -0.24, -0.48]


static func get_catalog(kind: String = "main") -> Array[Dictionary]:
	return AuxTools.new().get_catalog() if kind == "aux" else Tools.new().get_catalog()


static func create_preview(index: int, kind: String = "main") -> Node3D:
	var catalog: Array[Dictionary] = AuxTools.CATALOG if kind == "aux" else Tools.CATALOG
	var variant := clampi(index, 0, catalog.size() - 1)
	var entry: Dictionary = catalog[variant]
	var preview := Node3D.new()
	preview.name = "ToolPreview_" + str(entry.id)
	preview.process_mode = Node.PROCESS_MODE_DISABLED
	preview.set_meta("tool_id", entry.id)
	preview.set_meta("variant_index", variant)
	var pose := Node3D.new()
	pose.name = "DisplayPose"
	preview.add_child(pose)
	var tool: Node3D = AuxVisual.new() if kind == "aux" else Visual.new()
	tool.build(str(entry.id))
	pose.add_child(tool)
	pose.rotation = Vector3(-0.16,0.32,-0.08) if kind == "aux" else Vector3(-0.12, 0.26, float(DISPLAY_ANGLES[variant]))
	var parts: Array[AABB] = []
	var vertices: Array[Vector3] = []
	_collect_bounds(preview, Transform3D.IDENTITY, parts, vertices)
	if not parts.is_empty():
		var bounds := parts[0]
		for i in range(1, parts.size()):
			bounds = bounds.merge(parts[i])
		# A 300x280 viewport at orthographic size 4.4 has room for both
		# pointed ends and the complete grip, including its metal pommel.
		var fit := minf(3.80 / maxf(bounds.size.x, 0.001), 3.55 / maxf(bounds.size.y, 0.001))
		pose.scale = Vector3.ONE * fit
		pose.position = -bounds.get_center() * fit
		preview.set_meta("preview_bounds", AABB((bounds.position - bounds.get_center()) * fit, bounds.size * fit))
		var contact := Vector3.ZERO
		var contact_count := 0
		for vertex in vertices:
			if absf(vertex.y - bounds.position.y) <= 0.00001:
				contact += vertex
				contact_count += 1
		if contact_count > 0:
			contact /= float(contact_count)
			preview.set_meta("shelf_contact", (contact - bounds.get_center()) * fit)
	return preview


static func _collect_bounds(node: Node, placement: Transform3D, result: Array[AABB], vertices: Array[Vector3]) -> void:
	for child in node.get_children():
		var child_placement := placement
		if child is Node3D:
			child_placement = placement * child.transform
		if child is MeshInstance3D and child.mesh != null:
			var has_point := false
			var bounds := AABB()
			for surface in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for position in positions:
					var point: Vector3 = child_placement * position
					vertices.append(point)
					bounds = bounds.expand(point) if has_point else AABB(point, Vector3.ZERO)
					has_point = true
			if has_point:
				result.append(bounds)
		_collect_bounds(child, child_placement, result, vertices)
