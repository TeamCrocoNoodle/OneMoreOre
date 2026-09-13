extends Node3D
## Two deep iron bays and three tiers, framed like the cabinet reference.

const ToolModels = preload("res://scripts/tool_display_models.gd")
const UNIT := 0.01
const HEIGHT_PAD := 52.0

var tag_anchors: Array[Vector3] = []
var tool_centers: Array[Vector3] = []
var tag_corners: Array[PackedVector3Array] = []
var item_corners: Array[PackedVector3Array] = []
var _materials: Dictionary = {}
var _meshes: Dictionary = {}


func build(width: float, row_height: float, columns: int, kind: String = "main") -> void:
	name = "ModeledToolCabinet"
	set_meta("modeled_cabinet", true)
	process_mode = Node.PROCESS_MODE_DISABLED
	for child in get_children():
		remove_child(child)
		child.queue_free()
	tag_anchors.clear()
	tool_centers.clear()
	tag_corners.clear()
	item_corners.clear()
	_meshes.clear()
	var catalog := ToolModels.get_catalog(kind)
	var rows := ceili(float(catalog.size()) / columns)
	var height := row_height * rows + HEIGHT_PAD
	var span := width * UNIT
	var tall := height * UNIT
	var depth := minf(1.45, span * 0.19)
	var front := depth * 0.5
	var frame := _material("414951", 0.62, 0.45)
	var edge := _material("697680", 0.46, 0.55)
	var board := _material("454f58", 0.64, 0.45)
	var inner := _material("2a333d", 0.78, 0.35)
	var dark := _material("1c252d", 0.74, 0.38)
	var back_colors := ["29343d", "2e3841", "273139"]
	var bay_width := span * 0.5 - 0.48
	# Broad iron sheets replace wood grain; narrow welded seams sit at the back.
	for bay in 2:
		var x := (-0.25 if bay == 0 else 0.25) * span
		for sheet in 3:
			var sheet_width := (span * 0.5 - 0.18) / 3.0
			var sheet_x := x + (sheet - 1) * sheet_width
			_box("BackSheet", Vector3(sheet_width - 0.006, tall - 0.12, 0.075), Vector3(sheet_x, 0, -front - 0.05), _material(back_colors[sheet], 0.79, 0.30), 0.008, "back")
			if sheet < 2:
				_box("FoldedBackSeam", Vector3(0.016, tall - 0.18, 0.024), Vector3(sheet_x + sheet_width * 0.5, 0, -front + 0.007), inner, 0.004, "back")
	# The reference's substantial central stile separates two complete cabinets.
	for side in [-1, 1]:
		var x: float = side * (span * 0.5 - 0.11)
		_box("OuterSideWall", Vector3(0.13, tall, depth + 0.16), Vector3(x, 0, -0.035), inner, 0.018, "frame")
		_box("FrontUpright", Vector3(0.23, tall, 0.18), Vector3(x, 0, front + 0.015), frame, 0.027, "frame")
		_box("UprightFold", Vector3(0.025, tall - 0.03, 0.036), Vector3(x - side * 0.072, 0, front + 0.112), edge, 0.007, "trim")
	_box("CenterPartition", Vector3(0.20, tall, depth + 0.11), Vector3(0, 0, -0.035), inner, 0.02, "frame")
	_box("CentralDoubleStile", Vector3(0.42, tall + 0.03, 0.18), Vector3(0, 0, front + 0.025), frame, 0.028, "frame")
	_box("CentralJoin", Vector3(0.025, tall - 0.01, 0.012), Vector3(0, 0, front + 0.12), dark, 0.002, "trim")
	for side in [-1, 1]:
		_box("CenterFold", Vector3(0.024, tall - 0.03, 0.03), Vector3(side * 0.17, 0, front + 0.123), edge, 0.006, "trim")
	_box("TopCap", Vector3(span + 0.25, 0.23, depth + 0.27), Vector3(0, tall * 0.5 + 0.015, -0.02), frame, 0.03, "frame")
	_box("TopRolledEdge", Vector3(span + 0.28, 0.045, 0.06), Vector3(0, tall * 0.5 + 0.09, front + 0.135), edge, 0.013, "trim")
	_box("TopUnderRail", Vector3(span - 0.21, 0.10, 0.15), Vector3(0, tall * 0.5 - 0.15, front - 0.025), dark, 0.016, "frame")
	_box("BasePlinth", Vector3(span + 0.04, 0.18, depth + 0.13), Vector3(0, -tall * 0.5 + 0.02, -0.015), dark, 0.022, "frame")
	for row in rows:
		var surface_y := (height * 0.5 - 28.0 - (row + 1) * row_height) * UNIT
		for column in columns:
			var index := row * columns + column
			if index >= catalog.size():
				break
			var x := (-0.25 if column == 0 else 0.25) * span
			_box("ShelfDeck", Vector3(bay_width, 0.13, depth - 0.035), Vector3(x, surface_y - 0.065, -0.005), board, 0.013, "shelf")
			_box("ShelfFoldedApron", Vector3(bay_width + 0.015, 0.23, 0.06), Vector3(x, surface_y - 0.115, front + 0.012), frame, 0.012, "apron")
			_box("ShelfRolledEdge", Vector3(bay_width + 0.018, 0.026, 0.04), Vector3(x, surface_y - 0.015, front + 0.047), edge, 0.008, "trim")
			_box("ShelfReturnFold", Vector3(bay_width, 0.03, 0.13), Vector3(x, surface_y - 0.235, front - 0.02), dark, 0.008, "trim")
			var thumbnail_size := minf((bay_width - 0.22) / UNIT, row_height * 0.77)
			var model := ToolModels.create_preview(index,kind)
			var contact: Vector3 = model.get_meta("shelf_contact")
			var factor := thumbnail_size * UNIT / 4.4
			model.scale = Vector3.ONE * factor
			model.position = Vector3(x, surface_y - contact.y * factor + 0.008, front * 0.15)
			add_child(model)
			tool_centers.append(model.position)
			var plate_width := minf(1.68, bay_width - 0.10)
			var plate_height := 0.43
			var plate := Vector3(x, surface_y - 0.165, front + 0.094)
			_box("IronPricePlate", Vector3(plate_width, plate_height, 0.038), plate, dark, 0.013, "tag")
			tag_anchors.append(plate)
			tag_corners.append(_front_corners(plate + Vector3(0, 0, 0.022), plate_width - 0.026, plate_height - 0.014))
			var top_y := surface_y + row_height * UNIT - 0.22
			var bottom_y := surface_y - plate_height
			item_corners.append(_front_corners(Vector3(x, (top_y + bottom_y) * 0.5, front + 0.07), bay_width, top_y - bottom_y))
			for side in [-1, 1]:
				_bolt(Vector3(x + side * (plate_width * 0.5 - 0.065), plate.y + 0.13, plate.z + 0.029), 0.018, edge)
		for x in [-span * 0.5 + 0.11, -0.10, 0.10, span * 0.5 - 0.11]:
			_bolt(Vector3(x, surface_y - 0.12, front + 0.129), 0.026, edge)
	set_meta("framing_bounds", AABB(Vector3(-span * 0.5 - 0.15, -tall * 0.5 - 0.18, -front - 0.16), Vector3(span + 0.30, tall + 0.34, depth + 0.34)))


func _front_corners(center: Vector3, width: float, height: float) -> PackedVector3Array:
	return PackedVector3Array([center + Vector3(-width, height, 0) * 0.5, center + Vector3(width, height, 0) * 0.5, center + Vector3(width, -height, 0) * 0.5, center + Vector3(-width, -height, 0) * 0.5])


func _bolt(location: Vector3, radius: float, material: Material) -> void:
	var bolt := MeshInstance3D.new()
	bolt.name = "HexBolt"
	var key := "bolt" + str(radius)
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = 0.018
		mesh.radial_segments = 6
		_meshes[key] = mesh
	bolt.mesh = _meshes[key]
	bolt.material_override = material
	bolt.rotation.x = PI * 0.5
	bolt.position = location
	bolt.set_meta("cabinet_part", "peg")
	add_child(bolt)


func _material(hex: String, roughness: float = 0.93, metal: float = 0.0) -> StandardMaterial3D:
	var key := hex + str(roughness) + str(metal)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = roughness
	material.metallic = metal
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	material.metallic_specular = 0.18
	# Flat face normals retain hand-cut bevels at even the smallest UI scale.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_materials[key] = material
	return material


func _box(label: String, dimensions: Vector3, location: Vector3, material: Material, bevel: float, part: String) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.name = label
	var key := str(dimensions) + ":" + str(bevel)
	if not _meshes.has(key):
		_meshes[key] = _beveled_box(dimensions, bevel)
	box.mesh = _meshes[key]
	box.material_override = material
	box.position = location
	box.set_meta("cabinet_part", part)
	add_child(box)
	return box


func _beveled_box(dimensions: Vector3, amount: float) -> ArrayMesh:
	var half := dimensions * 0.5
	var bevel := minf(amount, minf(half.x, minf(half.y, half.z)) * 0.8)
	var inner := half - Vector3.ONE * bevel
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1, 1]:
			var corners := PackedVector3Array()
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = sign_value * half[axis]
				p[u] = uv.x * inner[u]
				p[v] = uv.y * inner[v]
				corners.append(p)
			_face(corners, vertices, normals)
	# Twelve long bevel faces, each joining the central faces of two axes.
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su in [-1, 1]:
			for sv in [-1, 1]:
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				a[axis] = -inner[axis]
				b[axis] = -inner[axis]
				a[u] = su * half[u]
				a[v] = sv * inner[v]
				b[u] = su * inner[u]
				b[v] = sv * half[v]
				var c := b
				var d := a
				c[axis] = inner[axis]
				d[axis] = inner[axis]
				_face(PackedVector3Array([a, b, c, d]), vertices, normals)
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				_face(PackedVector3Array([Vector3(sx * half.x, sy * inner.y, sz * inner.z), Vector3(sx * inner.x, sy * half.y, sz * inner.z), Vector3(sx * inner.x, sy * inner.y, sz * half.z)]), vertices, normals)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _face(points: PackedVector3Array, vertices: PackedVector3Array, normals: PackedVector3Array) -> void:
	var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var center := Vector3.ZERO
	for point in points:
		center += point
	var reverse := normal.dot(center) >= 0.0
	if not reverse:
		normal = -normal
	# Godot uses clockwise front faces. Keep winding and outward normals in
	# agreement on every face, including the negative sides and corner bevels.
	for i in range(1, points.size() - 1):
		var triangle := [points[0], points[i + 1], points[i]] if reverse else [points[0], points[i], points[i + 1]]
		for point in triangle:
			vertices.append(point)
			normals.append(normal)
