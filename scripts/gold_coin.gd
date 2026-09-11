extends Node3D
## A solid minted coin: bevelled edge, recessed field and raised gold emblem.

const SEGMENTS := 32
var _built := false


func _ready() -> void:
	if not _built:
		_build()
	set_process(false)
	set_physics_process(false)


func _build() -> void:
	_built = true
	var face := _material(Color("c5963c"), 0.48, 0.42)
	var bright := _material(Color("efc876"), 0.43, 0.46)
	var edge := _material(Color("875b27"), 0.56, 0.35)
	var recess := _material(Color("ac782a"), 0.56, 0.33)
	var emblem := _material(Color("eecc7c"), 0.46, 0.40)
	var materials: Array[Material] = [face, bright, edge, recess]
	var surfaces: Array[SurfaceTool] = []
	for material in materials:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		surfaces.append(surface)
	# Radius/depth profile runs from the back centre around the edge to the
	# recessed face. Revolving it closes both faces and gives real thickness.
	var profile := PackedVector2Array([
		Vector2(0.0, -0.14), Vector2(0.91, -0.14),
		Vector2(1.0, -0.065), Vector2(1.0, 0.065),
		Vector2(0.93, 0.15), Vector2(0.82, 0.15),
		Vector2(0.78, 0.095), Vector2(0.0, 0.095),
	])
	var bands := [0, 2, 2, 1, 1, 3, 0]
	for ring in profile.size() - 1:
		var surface := surfaces[bands[ring]]
		for i in SEGMENTS:
			var angle := TAU * float(i) / float(SEGMENTS)
			var next_angle := TAU * float(i + 1) / float(SEGMENTS)
			var a := _ring_point(profile[ring], angle)
			var b := _ring_point(profile[ring], next_angle)
			var c := _ring_point(profile[ring + 1], next_angle)
			var d := _ring_point(profile[ring + 1], angle)
			_triangle(surface, a, b, c)
			_triangle(surface, a, c, d)
	var body_mesh := ArrayMesh.new()
	for surface in surfaces:
		surface.commit(body_mesh)
	var body := MeshInstance3D.new()
	body.name = "MintedCoinBody"
	body.mesh = body_mesh
	add_child(body)
	# An extruded G, rather than text or a flat image, catches a narrow bevel
	# highlight independently of the field under it.
	var outline := PackedVector2Array([
		Vector2(0.40, 0.36), Vector2(0.19, 0.50),
		Vector2(-0.17, 0.50), Vector2(-0.45, 0.25),
		Vector2(-0.45, -0.23), Vector2(-0.19, -0.49),
		Vector2(0.19, -0.49), Vector2(0.43, -0.28),
		Vector2(0.43, 0.04), Vector2(0.03, 0.04),
		Vector2(0.03, -0.15), Vector2(0.22, -0.15),
		Vector2(0.22, -0.22), Vector2(0.10, -0.29),
		Vector2(-0.10, -0.29), Vector2(-0.24, -0.15),
		Vector2(-0.24, 0.16), Vector2(-0.10, 0.29),
		Vector2(0.11, 0.29), Vector2(0.25, 0.21),
	])
	var inner := PackedVector2Array()
	for point in outline:
		inner.append(point.move_toward(Vector2.ZERO, 0.013))
	var raised := SurfaceTool.new()
	raised.begin(Mesh.PRIMITIVE_TRIANGLES)
	raised.set_material(emblem)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	walls.set_material(bright)
	var indices := Geometry2D.triangulate_polygon(inner)
	for i in range(0, indices.size(), 3):
		var a := Vector3(inner[indices[i]].x, inner[indices[i]].y, 0.228)
		var b := Vector3(inner[indices[i + 1]].x, inner[indices[i + 1]].y, 0.228)
		var c := Vector3(inner[indices[i + 2]].x, inner[indices[i + 2]].y, 0.228)
		_triangle_facing(raised, a, b, c, Vector3.BACK)
	var back_indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, back_indices.size(), 3):
		var low_a := Vector3(outline[back_indices[i]].x, outline[back_indices[i]].y, 0.085)
		var low_b := Vector3(outline[back_indices[i + 1]].x, outline[back_indices[i + 1]].y, 0.085)
		var low_c := Vector3(outline[back_indices[i + 2]].x, outline[back_indices[i + 2]].y, 0.085)
		_triangle_facing(raised, low_a, low_b, low_c, Vector3.FORWARD)
	for i in outline.size():
		var j := (i + 1) % outline.size()
		var a := Vector3(outline[i].x, outline[i].y, 0.085)
		var b := Vector3(outline[j].x, outline[j].y, 0.085)
		var c := Vector3(outline[j].x, outline[j].y, 0.205)
		var d := Vector3(outline[i].x, outline[i].y, 0.205)
		var edge_normal := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		_triangle_facing(walls, a, b, c, edge_normal)
		_triangle_facing(walls, a, c, d, edge_normal)
		var top_a := Vector3(inner[i].x, inner[i].y, 0.228)
		var top_b := Vector3(inner[j].x, inner[j].y, 0.228)
		_triangle_facing(walls, d, c, top_b, (edge_normal + Vector3.BACK).normalized())
		_triangle_facing(walls, d, top_b, top_a, (edge_normal + Vector3.BACK).normalized())
	var emblem_mesh := ArrayMesh.new()
	raised.commit(emblem_mesh)
	walls.commit(emblem_mesh)
	var stamp := MeshInstance3D.new()
	stamp.name = "RaisedGoldEmblem"
	stamp.mesh = emblem_mesh
	add_child(stamp)


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	# Small UI models need the minted relief to survive downsampling. Keep
	# subdued metal glints instead of a broad white toon-specular patch.
	material.metallic = metallic * 0.55
	material.metallic_specular = 0.12
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return material


func _ring_point(profile: Vector2, angle: float) -> Vector3:
	return Vector3(cos(angle) * profile.x, sin(angle) * profile.x, profile.y)


func _triangle_facing(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) >= 0.0:
		_triangle(surface, a, b, c)
	else:
		_triangle(surface, a, c, b)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000000001:
		return
	surface.set_normal(normal.normalized())
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
