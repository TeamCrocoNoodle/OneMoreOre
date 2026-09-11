extends RefCounted
## Static shop illustrations made from the same model used during mining.
## Catalog prices are display data; this helper cannot purchase or equip tools.

const Pickaxe = preload("res://scripts/pickaxe.gd")

const CATALOG: Array[Dictionary] = [
	{"id": "base", "title": "강철 곡괭이", "price": 0, "color": Color("b5e0e1"), "owned": true},
	{"id": "copper", "title": "구리 곡괭이", "price": 80, "color": Color("eaa074"), "owned": false},
	{"id": "silver", "title": "은빛 곡괭이", "price": 150, "color": Color("e8eef6"), "owned": false},
	{"id": "cobalt", "title": "코발트 곡괭이", "price": 240, "color": Color("77b5ec"), "owned": false},
	{"id": "dark_iron", "title": "흑철 곡괭이", "price": 360, "color": Color("a89ac2"), "owned": false},
	{"id": "gold", "title": "황금 곡괭이", "price": 520, "color": Color("f7d477"), "owned": false},
]

# Face, bevel, side, and the two existing hand-cut highlights.
const HEAD_PALETTES := [
	["344957", "b5e0e1", "172a3b", "668998", "597b8d"],
	["a96541", "f4c6a0", "583626", "d68f65", "c17c55"],
	["879baa", "eff9ff", "3d515e", "c1d1db", "a6bac8"],
	["326893", "a7dcf7", "1a354f", "6098c0", "477fa7"],
	["40384e", "b5a4cd", "211d2d", "746781", "60546f"],
	["c19036", "ffedb5", "63471d", "e9bd65", "d8a84d"],
]
const ORIGINAL_HEAD_COLORS := ["344957", "b5e0e1", "172a3b", "668998", "597b8d"]
const DISPLAY_ANGLES := [-0.48, -0.53, -0.44, -0.56, -0.46, -0.51]


static func get_catalog() -> Array[Dictionary]:
	return CATALOG.duplicate(true)


static func create_preview(index: int) -> Node3D:
	var variant := clampi(index, 0, CATALOG.size() - 1)
	var entry: Dictionary = CATALOG[variant]
	var preview := Node3D.new()
	preview.name = "ToolPreview_" + str(entry.id)
	preview.process_mode = Node.PROCESS_MODE_DISABLED
	preview.set_meta("tool_id", entry.id)
	preview.set_meta("variant_index", variant)
	var pose := Node3D.new()
	pose.name = "DisplayPose"
	preview.add_child(pose)
	var tool := Pickaxe.new()
	tool.name = "OriginalPickaxe"
	tool.set_process(false)
	tool.process_mode = Node.PROCESS_MODE_DISABLED
	# Build synchronously so a caller can frame the thumbnail before entering
	# the scene tree. _ready() sees _built and never creates a second model.
	tool._build_tool()
	pose.add_child(tool)
	var material_copies: Dictionary = {}
	_recolor(tool, variant, material_copies)
	pose.rotation = Vector3(-0.12, 0.26, float(DISPLAY_ANGLES[variant]))
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


static func _recolor(node: Node, variant: int, copies: Dictionary) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.material_override != null:
			instance.material_override = _copy_material(instance.material_override, variant, copies)
		if instance.mesh != null:
			for surface in instance.mesh.get_surface_count():
				var material: Material = instance.mesh.surface_get_material(surface)
				if material != null:
					instance.set_surface_override_material(surface, _copy_material(material, variant, copies))
	for child in node.get_children():
		_recolor(child, variant, copies)


static func _copy_material(source: Material, variant: int, copies: Dictionary) -> Material:
	var key := source.get_instance_id()
	if copies.has(key):
		return copies[key]
	var copy: Material = source.duplicate()
	copies[key] = copy
	if copy is StandardMaterial3D and variant != 0:
		var standard := copy as StandardMaterial3D
		var shade := ORIGINAL_HEAD_COLORS.find(standard.albedo_color.to_html(false))
		if shade >= 0:
			standard.albedo_color = Color(HEAD_PALETTES[variant][shade])
	# Roughness, toon lighting, warm wooden grain, wrapped grip and fittings
	# retain the original artist-authored values.
	return copy


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
