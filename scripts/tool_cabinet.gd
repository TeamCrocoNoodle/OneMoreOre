extends Node3D
## Actual joinery, shelves and existing tools share one lit three-dimensional scene.

const ToolModels = preload("res://scripts/tool_display_models.gd")
const UNIT := 0.01

var tag_anchors: Array[Vector3] = []
var tool_centers: Array[Vector3] = []
var _materials: Dictionary = {}
var _meshes: Dictionary = {}


func build(width: float, row_height: float, columns: int) -> void:
	name = "ModeledToolCabinet"
	set_meta("modeled_cabinet", true)
	process_mode = Node.PROCESS_MODE_DISABLED
	for child in get_children():
		remove_child(child)
		child.queue_free()
	tag_anchors.clear()
	tool_centers.clear()
	_meshes.clear()
	var catalog := ToolModels.get_catalog()
	var rows := ceili(float(catalog.size()) / columns)
	var height := row_height * rows + 38.0
	var span := width * UNIT
	var tall := height * UNIT
	var frame := _material("67482b")
	var frame_edge := _material("87623b")
	var board := _material("795738")
	var dark := _material("302216")
	var nail := _material("38332b", 0.45, 0.4)
	# Long back planks occupy real depth behind the tools and receive shadows.
	var plank_count := columns * 4
	var plank_width := (span - 0.34) / plank_count
	for plank in plank_count:
		var x := -span * 0.5 + 0.17 + (plank + 0.5) * plank_width
		var color: String = ["473322", "4d3825", "423120"][plank % 3]
		_box("BackPlank%d" % plank, Vector3(plank_width - 0.012, tall - 0.16, 0.13), Vector3(x, 0, -0.48), _material(color), 0.014, "back")
		for grain in 2:
			var grain_length := minf(tall * 0.36, 1.3 + 0.11 * (plank % 3))
			var grain_y := (0.5 - grain) * tall * 0.47 + (plank % 3 - 1) * 0.13
			var stroke := _box("Grain", Vector3(0.010, grain_length, 0.007), Vector3(x + plank_width * (0.18 if grain == 0 else -0.20), grain_y, -0.410), _material("3c2b1d"), 0.002, "grain")
			stroke.rotation.z = 0.010 if plank % 2 == 0 else -0.009
	# Side posts, a proud crown and a bottom rail make a deep cabinet silhouette.
	for side in [-1, 1]:
		var x: float = side * (span * 0.5 - 0.10)
		_box("SidePost", Vector3(0.20, tall, 0.97), Vector3(x, 0, -0.01), frame, 0.035, "frame")
		_box("PostMolding", Vector3(0.045, tall - 0.06, 0.055), Vector3(x - side * 0.046, 0, 0.494), frame_edge, 0.014, "trim")
		for y in [-tall * 0.5 + 0.21, tall * 0.5 - 0.23]:
			var rivet := MeshInstance3D.new()
			rivet.name = "IronPeg"
			var sphere := SphereMesh.new()
			sphere.radius = 0.026
			sphere.height = 0.026
			sphere.radial_segments = 10
			sphere.rings = 4
			rivet.mesh = sphere
			rivet.material_override = nail
			rivet.rotation.x = PI * 0.5
			rivet.position = Vector3(x + side * 0.01, y, 0.488)
			rivet.set_meta("cabinet_part", "peg")
			add_child(rivet)
	_box("Crown", Vector3(span + 0.14, 0.18, 1.12), Vector3(0, tall * 0.5 + 0.025, 0), frame, 0.035, "frame")
	_box("CrownLip", Vector3(span + 0.16, 0.045, 0.10), Vector3(0, tall * 0.5 + 0.10, 0.535), frame_edge, 0.014, "trim")
	_box("BottomRail", Vector3(span - 0.22, 0.16, 0.96), Vector3(0, -tall * 0.5 + 0.055, 0), dark, 0.025, "frame")
	var cell_width := (width - 48.0) / columns
	for row in rows:
		var surface_y := (height * 0.5 - (18.0 + (row + 1) * row_height - 68.0)) * UNIT
		_box("Shelf%d" % row, Vector3(span - 0.28, 0.19, 0.97), Vector3(0, surface_y - 0.095, 0), board, 0.025, "shelf")
		_box("ShelfLip%d" % row, Vector3(span - 0.25, 0.065, 0.06), Vector3(0, surface_y - 0.025, 0.50), frame_edge, 0.015, "trim")
		# A front apron adds thickness beneath the overhanging surface.
		_box("ShelfApron%d" % row, Vector3(span - 0.34, 0.12, 0.10), Vector3(0, surface_y - 0.22, 0.36), frame, 0.018, "apron")
		for column in columns:
			var index := row * columns + column
			if index >= catalog.size():
				break
			var x := (-width * 0.5 + 24.0 + (column + 0.5) * cell_width) * UNIT
			var thumbnail_size := minf(cell_width - 22.0, row_height - 68.0)
			var model := ToolModels.create_preview(index)
			var contact: Vector3 = model.get_meta("shelf_contact")
			var factor := thumbnail_size * UNIT / 4.4
			model.scale = Vector3.ONE * factor
			model.position = Vector3(x, surface_y - contact.y * factor + 0.012, 0.075)
			add_child(model)
			tool_centers.append(model.position)
			tag_anchors.append(Vector3(x, surface_y - 0.12, 0.57))


func _material(hex: String, roughness: float = 0.93, metal: float = 0.0) -> StandardMaterial3D:
	if _materials.has(hex):
		return _materials[hex]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = roughness
	material.metallic = metal
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Flat face normals retain hand-cut bevels at even the smallest UI scale.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_materials[hex] = material
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
