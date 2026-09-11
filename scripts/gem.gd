extends StaticBody3D
## Opaque cut crystals; the rock itself always occludes an undiscovered gem.

const COMMON := 0
const SPECIAL := 1
const LIGHT_COLORS := [Color("f3faff"), Color("64ff86"), Color("4896ff"), Color("ffe15b"), Color("be65ff"), Color("ff4c61")]
const LIGHT_NAMES := ["white", "green", "blue", "yellow", "purple", "red"]

var grade: int = COMMON
var variant: int = 0
var light_tier: int = 0
var collected: bool = false
var bound_radius: float = 0.38
var visual := Node3D.new()
var facets: MeshInstance3D

var _material: StandardMaterial3D
var _colliders: Array[CollisionShape3D] = []


func configure(new_grade: int, new_variant: int = 0) -> void:
	grade = SPECIAL if new_grade == SPECIAL else COMMON
	variant = posmod(new_variant, 5)
	light_tier = 5 if grade == SPECIAL else variant
	collected = false
	# Ready before insertion into the tree, for the caller's placement checks.
	bound_radius = 0.52 if grade == SPECIAL else _common_dimensions().w
	if is_node_ready():
		_build()


func _ready() -> void:
	visual.name = "Crystal"
	add_child(visual)
	_build()


func set_hovered(hovered: bool) -> void:
	if not is_instance_valid(_material):
		return
	var highlight := hovered and not collected
	_material.albedo_color = Color(1.12, 1.12, 1.08) if highlight else Color.WHITE
	_material.roughness = 0.17 if highlight else (0.20 if grade == SPECIAL else 0.25)


func begin_collection() -> bool:
	if collected:
		return false
	collected = true
	# The layer change takes effect immediately, including consecutive raycasts.
	collision_layer = 0
	collision_mask = 0
	for collider in _colliders:
		collider.set_deferred("disabled", true)
	set_hovered(false)
	return true


func _build() -> void:
	for child in visual.get_children():
		visual.remove_child(child)
		child.queue_free()
	for collider in _colliders:
		remove_child(collider)
		collider.queue_free()
	_colliders.clear()
	collision_layer = 0 if collected else 2
	collision_mask = 0
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.20 if grade == SPECIAL else 0.25
	_material.metallic = 0.32 if grade == SPECIAL else 0.16
	_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	# No light, transparency, bloom halo, or depth override can reveal a buried gem.
	_material.emission_enabled = false
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if grade == SPECIAL:
		_build_special(surface)
	else:
		_build_common(surface)
	facets = MeshInstance3D.new()
	facets.name = "SpecialCrown" if grade == SPECIAL else "CommonCut%d" % variant
	facets.mesh = surface.commit()
	facets.material_override = _material
	visual.add_child(facets)
	# Measure the finished geometry, so placement never relies on a loose estimate.
	bound_radius = 0.0
	var vertices: PackedVector3Array = facets.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		bound_radius = maxf(bound_radius, vertex.length())


func _common_dimensions() -> Vector4:
	# Width, table height, lower tip height, and conservative placement radius.
	match variant:
		1: return Vector4(0.305, 0.300, -0.390, 0.390)
		2: return Vector4(0.370, 0.215, -0.335, 0.380)
		3: return Vector4(0.345, 0.275, -0.360, 0.370)
		4: return Vector4(0.310, 0.315, -0.400, 0.400)
	return Vector4(0.335, 0.255, -0.380, 0.380)


func _common_palette() -> Array[Color]:
	match variant:
		1:
			return [Color("a6ffc2"), Color("28cf80"), Color("14885d"), Color("62ef97"), Color("d1ffe0"), Color("21af74"), Color("69dfab"), Color("16715c")]
		2:
			return [Color("a7d0ff"), Color("387ce5"), Color("224ba6"), Color("649dff"), Color("e0efff"), Color("2963ce"), Color("87b8ff"), Color("24418e")]
		3:
			return [Color("fff0a7"), Color("f3b635"), Color("b76c20"), Color("ffd867"), Color("fff6d2"), Color("de8c27"), Color("ffc775"), Color("a45d28")]
		4:
			return [Color("dbbcff"), Color("9d65e4"), Color("6740a9"), Color("bf86f7"), Color("f0e0ff"), Color("884bd0"), Color("c6a1ef"), Color("543a92")]
	return [Color("ffffff"), Color("d1e7f0"), Color("8ca9bb"), Color("e6f5ff"), Color("ffffff"), Color("bbd5e3"), Color("e6f0f5"), Color("718fa9")]


func _build_common(surface: SurfaceTool) -> void:
	var dimensions := _common_dimensions()
	var colors := _common_palette()
	var table := _ring(dimensions.x * 0.51, dimensions.y, 8, PI / 8.0)
	var upper := _ring(dimensions.x, 0.055, 8, PI / 8.0)
	var lower := _ring(dimensions.x * 0.975, 0.010, 8, PI / 8.0)
	var top := Vector3(0.0, dimensions.y + 0.025, 0.0)
	var bottom := Vector3(0.0, dimensions.z, 0.0)
	var bounds := PackedVector3Array([top, bottom])
	bounds.append_array(table)
	bounds.append_array(upper)
	bounds.append_array(lower)
	for i in range(8):
		var j := (i + 1) % 8
		_triangle(surface, top, table[i], table[j], colors[(i + 4) % 8].lightened(0.12))
		_triangle(surface, table[i], upper[i], upper[j], colors[i])
		_triangle(surface, table[i], upper[j], table[j], colors[i].lightened(0.08))
		_triangle(surface, upper[i], lower[i], lower[j], colors[(i + 4) % 8].lightened(0.10))
		_triangle(surface, upper[i], lower[j], upper[j], colors[(i + 4) % 8].lightened(0.10))
		_triangle(surface, lower[i], bottom, lower[j], colors[(i + 2) % 8].darkened(0.06))
	_add_convex(bounds)


func _build_special(surface: SurfaceTool) -> void:
	var colors: Array[Color] = [Color("ffc4cf"), Color("ff3657"), Color("be2449"), Color("f87d94"), Color("e84377"), Color("ffe1de"), Color("ff667b"), Color("a82248")]
	var top := Vector3(0.0, 0.52, 0.0)
	var bottom := Vector3(0.0, -0.50, 0.0)
	var top_crown := _ring(0.19, 0.295, 8, PI / 8.0)
	var upper := _ring(0.34, 0.065, 8, PI / 8.0)
	var lower := _ring(0.34, -0.035, 8, PI / 8.0)
	var bottom_crown := _ring(0.16, -0.315, 8, PI / 8.0)
	var bounds := PackedVector3Array([top, bottom])
	for ring in [top_crown, upper, lower, bottom_crown]:
		bounds.append_array(ring)
	for i in range(8):
		var j := (i + 1) % 8
		_triangle(surface, top, top_crown[i], top_crown[j], colors[(i + 5) % 8])
		_triangle(surface, top_crown[i], upper[i], upper[j], colors[i])
		_triangle(surface, top_crown[i], upper[j], top_crown[j], colors[i].lightened(0.12))
		_triangle(surface, upper[i], lower[i], lower[j], Color("ffb0bf").darkened(float(i % 3) * 0.09))
		_triangle(surface, upper[i], lower[j], upper[j], Color("ffb0bf").darkened(float(i % 3) * 0.09))
		_triangle(surface, lower[i], bottom_crown[i], bottom_crown[j], colors[(i + 1) % 8])
		_triangle(surface, lower[i], bottom_crown[j], lower[j], colors[(i + 1) % 8].darkened(0.07))
		_triangle(surface, bottom_crown[i], bottom, bottom_crown[j], colors[(i + 3) % 8])
	_add_convex(bounds)
	# Six solid satellite facets form a small star crown, without a floating halo.
	# Each shard has its own exact convex collider rather than filling the notches.
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var direction := 1.0 if i % 2 == 0 else -1.0
		var start := radial * 0.20 + Vector3.UP * (-0.08 * direction)
		var end := radial * 0.455 + Vector3.UP * (0.19 * direction)
		_add_crown_shard(surface, start, end, colors, i)


func _add_crown_shard(surface: SurfaceTool, start: Vector3, end: Vector3, colors: Array[Color], index: int) -> void:
	var axis := (end - start).normalized()
	var tangent := axis.cross(Vector3.UP).normalized()
	var bitangent := axis.cross(tangent).normalized()
	var center := start.lerp(end, 0.47)
	var ring := PackedVector3Array()
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		ring.append(center + (tangent * cos(angle) + bitangent * sin(angle)) * 0.078)
	var bounds := PackedVector3Array([start, end])
	bounds.append_array(ring)
	for i in range(4):
		var j := (i + 1) % 4
		_triangle(surface, start, ring[i], ring[j], colors[(index + i + 1) % 8].darkened(0.10), center)
		_triangle(surface, end, ring[j], ring[i], colors[(index + i + 5) % 8].lightened(0.08), center)
	_add_convex(bounds)


func _ring(radius: float, height: float, count: int, phase: float) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for i in range(count):
		var angle := TAU * float(i) / float(count) + phase
		ring.append(Vector3(cos(angle) * radius, height, sin(angle) * radius))
	return ring


func _add_convex(points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	shape.margin = 0.002
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.disabled = collected
	_colliders.append(collider)
	add_child(collider)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, center: Vector3 = Vector3.ZERO) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot((a + b + c) / 3.0 - center) < 0.0:
		var temporary := b
		b = c
		c = temporary
		normal = -normal
	surface.set_color(color)
	surface.set_normal(normal)
	# Clockwise winding is the outward face in Godot.
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
