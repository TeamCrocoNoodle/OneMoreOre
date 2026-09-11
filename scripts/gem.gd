extends StaticBody3D

var visual := Node3D.new()
var facets: MeshInstance3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	add_child(visual)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors := [Color("91ffe5"), Color("1bd6bd"), Color("0a978e"), Color("46f6d2"), Color("cdfef0"), Color("12b4b0"), Color("51ddc3"), Color("157b91")]
	var top := PackedVector3Array()
	var rim := PackedVector3Array()
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + PI / 8.0
		top.append(Vector3(cos(angle) * 0.37, 0.53, sin(angle) * 0.37))
		rim.append(Vector3(cos(angle) * 0.72, 0.11, sin(angle) * 0.72))
	for i in range(8):
		var j := (i + 1) % 8
		_triangle(surface, Vector3(0, 0.56, 0), top[j], top[i], colors[(i + 4) % 8].lightened(0.2))
		_triangle(surface, top[i], top[j], rim[j], colors[i])
		_triangle(surface, top[i], rim[j], rim[i], colors[i].darkened(0.08))
		_triangle(surface, rim[i], rim[j], Vector3(0, -0.83, 0), colors[(i + 2) % 8].darkened(0.1))
	surface.generate_normals()
	var mesh := surface.commit()
	facets = MeshInstance3D.new()
	facets.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.22
	material.metallic = 0.18
	material.emission_enabled = true
	material.emission = Color(0.03, 0.19, 0.14)
	material.emission_energy_multiplier = 0.4
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	facets.material_override = material
	visual.add_child(facets)
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_convex_shape()
	add_child(collider)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
