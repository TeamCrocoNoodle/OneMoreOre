extends Node3D
## A camera-mounted pickaxe whose poses stay anchored to the current cursor.

signal impacted
signal swing_started

var is_swinging: bool = false

const STRIKE_TIME := 0.12
const SWING_DURATION := 0.34
const PICK_TIP := Vector3(-1.44, -0.36, 0.0)

var _camera: Camera3D
var _target := Vector2.ZERO
var _elapsed := 0.0
var _idle_time := 0.0
var _impact_sent := false
var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3(0.08, -0.18, -0.70)
var _contact_position := Vector3.ZERO
var _contact_rotation := Vector3(0.12, -0.12, 0.52)
var _contact_override := Vector3.ZERO
var _has_contact_override := false
var _wind_position := Vector3.ZERO
var _wind_rotation := Vector3.ZERO
var _tool_scale := 0.88
var _built := false
var _trail: MeshInstance3D
var _trail_material: StandardMaterial3D


func setup(camera: Camera3D) -> void:
	_camera = camera
	if get_parent() != camera:
		if get_parent() != null:
			reparent(camera, false)
		else:
			camera.add_child(self)
	if not _built:
		_build_tool()
	_target = camera.get_viewport().get_visible_rect().size * 0.5
	_refresh_rest()
	position = _rest_position
	rotation = _rest_rotation
	if not is_instance_valid(_trail):
		_trail = MeshInstance3D.new()
		_trail.name = "PickaxeArc"
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_camera.add_child(_trail)
		_trail_material = StandardMaterial3D.new()
		_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_material.vertex_color_use_as_albedo = true
		_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


func _ready() -> void:
	if not _built:
		_build_tool()


func set_target(screen_position: Vector2) -> void:
	if screen_position != _target:
		_has_contact_override = false
	_target = screen_position


func get_target_screen() -> Vector2:
	return _target


func clear_contact_point() -> void:
	_has_contact_override = false


func set_contact_point(world_position: Vector3) -> void:
	# The caller already raycasts for mining. Reuse that point for physical depth.
	_contact_override = world_position
	_has_contact_override = true


func swing() -> void:
	if is_swinging or not is_instance_valid(_camera):
		return
	_refresh_rest()
	_refresh_swing_poses()
	_elapsed = 0.0
	_impact_sent = false
	is_swinging = true
	swing_started.emit()


func _refresh_swing_poses() -> void:
	# Rebuild around the live cursor, including wind-up and recoil. There is
	# no screen-corner destination to travel from or return to between hits.
	var contact_depth := 5.7
	if _has_contact_override:
		contact_depth = clampf(-_camera.to_local(_contact_override).z - 0.10, 1.0, 5.7)
	# Keep the cursor tool in front of the stone instead of burying its handle
	# during the strike. Fresh projection also prevents camera shake from
	# dragging the tip away from the cursor between physics ray updates.
	var contact := _camera.to_local(_camera.project_position(_target, contact_depth))
	var contact_basis := Basis.from_euler(_contact_rotation)
	_contact_position = contact - contact_basis * (PICK_TIP * _tool_scale)
	_wind_rotation = _rest_rotation + Vector3(-0.04, -0.04, -0.42)
	var wind_tip := _camera.to_local(_camera.project_position(_target, 5.7)) + Vector3(-0.18, 0.62, 0.1) * _tool_scale
	_wind_position = wind_tip - Basis.from_euler(_wind_rotation) * (PICK_TIP * _tool_scale)


func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	_idle_time += delta
	_refresh_rest()
	if is_swinging:
		_refresh_swing_poses()
		_elapsed += delta
		if _elapsed < 0.065:
			var t := smoothstep(0.0, 0.065, _elapsed)
			position = _rest_position.lerp(_wind_position, t)
			rotation = _rest_rotation.lerp(_wind_rotation, t)
		elif _elapsed < STRIKE_TIME:
			var t := _strike_fraction(_elapsed)
			position = _stroke_position(t)
			rotation = _wind_rotation.lerp(_contact_rotation, t)
		elif _elapsed < 0.153:
			# A short exact hold gives the strike weight before the spring recoil.
			position = _contact_position
			rotation = _contact_rotation
		elif _elapsed < 0.185:
			var t := smoothstep(0.153, 0.185, _elapsed)
			position = _contact_position + Vector3(0.055, 0.09, 0.13) * t
			rotation = _contact_rotation + Vector3(0.0, -0.025, -0.095) * t
		else:
			var t := clampf((_elapsed - 0.185) / (SWING_DURATION - 0.185), 0.0, 1.0)
			var settle := smoothstep(0.0, 1.0, t)
			position = (_contact_position + Vector3(0.055, 0.09, 0.13)).lerp(_rest_position, settle)
			rotation = (_contact_rotation + Vector3(0.0, -0.025, -0.095)).lerp(_rest_rotation, settle)
			rotation.z -= sin(t * PI) * 0.10
		if _elapsed >= STRIKE_TIME and not _impact_sent:
			_impact_sent = true
			impacted.emit()
		if _elapsed >= SWING_DURATION:
			is_swinging = false
	else:
		position = _rest_position + Vector3(0.0, sin(_idle_time * 1.8) * 0.022, 0.0)
		rotation = _rest_rotation + Vector3(0.0, 0.0, sin(_idle_time * 1.5) * 0.009)
	_update_trail()


func _refresh_rest() -> void:
	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var half_height := _camera.size * 0.5
	var half_width := half_height * aspect
	if _camera.keep_aspect == Camera3D.KEEP_WIDTH:
		half_width = _camera.size * 0.5
		half_height = half_width / aspect
	_tool_scale = clampf(half_width / 4.6, 0.60, 0.92)
	scale = Vector3.ONE * _tool_scale
	var cursor := _camera.to_local(_camera.project_position(_target, 5.7))
	# Keep the striking end just above the pointer so its target stays clear.
	_rest_position = cursor - Basis.from_euler(_rest_rotation) * (PICK_TIP * _tool_scale) + Vector3(0.13, 0.22, 0.0) * _tool_scale


func _strike_fraction(time: float) -> float:
	return pow(clampf((time - 0.065) / 0.055, 0.0, 1.0), 1.25)


func _stroke_position(t: float) -> Vector3:
	var first_control := _wind_position + Vector3(-0.10, 0.20, 0.0)
	var second_control := _contact_position + Vector3(0.55, 0.65, 0.15)
	return _wind_position.bezier_interpolate(first_control, second_control, _contact_position, t)


func _stroke_tip(time: float) -> Vector3:
	var t := _strike_fraction(time)
	var tip_basis := Basis.from_euler(_wind_rotation.lerp(_contact_rotation, t))
	return _stroke_position(t) + tip_basis * (PICK_TIP * _tool_scale)


func _update_trail() -> void:
	if not is_instance_valid(_trail):
		return
	if not is_swinging or _elapsed <= 0.069 or _elapsed > 0.19:
		_trail.visible = false
		return
	_trail.visible = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_trail_material)
	var start := maxf(0.065, _elapsed - 0.07)
	var finish := minf(_elapsed, STRIKE_TIME)
	for i in range(12):
		var time_a := lerpf(start, finish, float(i) / 12.0)
		var time_b := lerpf(start, finish, float(i + 1) / 12.0)
		var a := _stroke_tip(time_a)
		var b := _stroke_tip(time_b)
		var direction := (b - a).normalized()
		var age := _elapsed - time_b
		var width := 0.012 + float(i + 1) / 12.0 * 0.038
		var perpendicular := Vector3(-direction.y, direction.x, 0.0) * width
		var alpha := clampf(1.0 - age / 0.07, 0.0, 1.0) * 0.33
		var color := Color(0.73, 0.95, 1.0, alpha)
		_triangle(surface, a - perpendicular, b - perpendicular, b + perpendicular, color)
		_triangle(surface, a - perpendicular, b + perpendicular, a + perpendicular, color)
	_trail.mesh = surface.commit()


func _build_tool() -> void:
	_built = true
	var wood := _material(Color("a76032"), 0.86)
	var wood_edge := _material(Color("e8a15c"), 0.82)
	var wood_side := _material(Color("633624"), 0.95)
	var steel := _material(Color("344957"), 0.48, 0.34)
	var steel_edge := _material(Color("b5e0e1"), 0.28, 0.52)
	var steel_side := _material(Color("172a3b"), 0.62, 0.25)
	var brass := _material(Color("dfa64e"), 0.40, 0.46)
	var brass_light := _material(Color("ffda80"), 0.34, 0.43)
	var brass_dark := _material(Color("84562c"), 0.70, 0.26)
	var leather := _material(Color("2b3037"), 0.94)
	var leather_edge := _material(Color("56616b"), 0.87)
	var head_outline := PackedVector2Array([
		Vector2(-1.44, -0.36), Vector2(-1.26, -0.02), Vector2(-0.98, 0.21),
		Vector2(-0.60, 0.32), Vector2(-0.25, 0.26), Vector2(0.02, 0.21),
		Vector2(0.34, 0.30), Vector2(0.65, 0.30), Vector2(0.96, 0.15),
		Vector2(1.20, -0.10), Vector2(1.36, -0.45), Vector2(1.08, -0.26),
		Vector2(0.79, -0.08), Vector2(0.53, 0.02), Vector2(0.26, -0.01),
		Vector2(0.02, -0.12), Vector2(-0.31, -0.02), Vector2(-0.72, 0.015),
		Vector2(-1.08, -0.14)
	])
	var handle_outline := PackedVector2Array([
		Vector2(-0.13, 0.16), Vector2(0.12, 0.16), Vector2(0.13, -0.43),
		Vector2(0.07, -1.05), Vector2(0.095, -1.43), Vector2(0.16, -1.84),
		Vector2(0.10, -1.96), Vector2(-0.10, -1.98), Vector2(-0.18, -1.85),
		Vector2(-0.23, -1.32), Vector2(-0.17, -0.91), Vector2(-0.12, -0.40)
	])
	_prism("HickoryHandle", handle_outline, 0.15, 0.035, wood, wood_edge, wood_side)
	_prism("ForgedSteelHead", head_outline, 0.19, 0.042, steel, steel_edge, steel_side)
	# Narrow hand-cut highlights and grain are actual geometry, avoiding texture blur.
	_flat_shape("WoodGrain", PackedVector2Array([
		Vector2(-0.065, -0.29), Vector2(-0.035, -0.40), Vector2(-0.055, -0.82),
		Vector2(-0.090, -1.18), Vector2(-0.10, -1.25), Vector2(-0.082, -0.81)
	]), 0.154, wood_side)
	_flat_shape("WoodGlint", PackedVector2Array([
		Vector2(0.035, -0.31), Vector2(0.065, -0.35), Vector2(0.040, -0.82),
		Vector2(0.005, -1.06), Vector2(0.015, -0.68)
	]), 0.155, wood_edge)
	var mount := PackedVector2Array([
		Vector2(-0.19, 0.22), Vector2(-0.11, 0.30), Vector2(0.13, 0.30),
		Vector2(0.21, 0.21), Vector2(0.18, -0.22), Vector2(0.10, -0.28),
		Vector2(-0.12, -0.28), Vector2(-0.19, -0.19)
	])
	_prism("BronzeSocket", mount, 0.225, 0.035, brass, brass_light, brass_dark)
	_prism("SocketInset", _rectangle(Vector2(-0.095, -0.14), Vector2(0.105, 0.19)), 0.253, 0.017, steel_side, brass_dark, brass_dark)
	for y in [-0.08, 0.12]:
		var rivet := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.040
		sphere.height = 0.046
		sphere.radial_segments = 8
		sphere.rings = 3
		rivet.mesh = sphere
		rivet.material_override = brass_light
		rivet.position = Vector3(0.005, y, 0.277)
		rivet.rotation.x = PI * 0.5
		add_child(rivet)
	# Individual slanted leather turns leave a slim gold seam between wraps.
	for i in range(7):
		var y := -1.13 - float(i) * 0.10
		var x := -0.07 + maxf(0.0, -y - 1.25) * 0.15
		var wrap_outline := PackedVector2Array([
			Vector2(x - 0.154, y + 0.04), Vector2(x + 0.153, y + 0.075),
			Vector2(x + 0.163, y - 0.005), Vector2(x - 0.150, y - 0.055)
		])
		_prism("LeatherWrap%d" % i, wrap_outline, 0.173, 0.012, leather, leather_edge, leather)
	_prism("GripUpperFerrule", _rectangle(Vector2(-0.228, -1.11), Vector2(0.084, -1.015)), 0.176, 0.015, brass, brass_light, brass_dark)
	_prism("Pommel", PackedVector2Array([
		Vector2(-0.13, -1.78), Vector2(0.145, -1.79), Vector2(0.175, -1.91),
		Vector2(0.085, -2.02), Vector2(-0.092, -2.02), Vector2(-0.18, -1.90)
	]), 0.18, 0.028, brass, brass_light, brass_dark)
	# Small upper facet makes the forged metal catch the light as it swings.
	_flat_shape("LeftSteelFacet", PackedVector2Array([
		Vector2(-1.17, -0.025), Vector2(-0.94, 0.15), Vector2(-0.59, 0.255),
		Vector2(-0.28, 0.203), Vector2(-0.54, 0.16), Vector2(-0.93, 0.095)
	]), 0.193, _material(Color("668998"), 0.44, 0.30))
	_flat_shape("RightSteelFacet", PackedVector2Array([
		Vector2(0.31, 0.234), Vector2(0.63, 0.24), Vector2(0.91, 0.10),
		Vector2(1.12, -0.13), Vector2(0.88, 0.015), Vector2(0.59, 0.17)
	]), 0.194, _material(Color("597b8d"), 0.44, 0.30))


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return material


func _rectangle(low: Vector2, high: Vector2) -> PackedVector2Array:
	return PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])


func _prism(mesh_name: String, polygon: PackedVector2Array, depth: float, bevel: float,
		face_material: Material, bevel_material: Material, side_material: Material) -> void:
	# Each bevel has its own hard normal: highlights remain graphic and readable.
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	center /= float(polygon.size())
	var inner := PackedVector2Array()
	for point in polygon:
		inner.append(point.move_toward(center, bevel))
	var triangles := Geometry2D.triangulate_polygon(inner)
	var mesh := ArrayMesh.new()
	var faces := SurfaceTool.new()
	faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	faces.set_material(face_material)
	for i in range(0, triangles.size(), 3):
		var a := inner[triangles[i]]
		var b := inner[triangles[i + 1]]
		var c := inner[triangles[i + 2]]
		_front_triangle(faces, Vector3(a.x, a.y, depth), Vector3(b.x, b.y, depth), Vector3(c.x, c.y, depth))
		_back_triangle(faces, Vector3(a.x, a.y, -depth), Vector3(b.x, b.y, -depth), Vector3(c.x, c.y, -depth))
	faces.commit(mesh)
	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	edges.set_material(bevel_material)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.set_material(side_material)
	for i in range(polygon.size()):
		var j := (i + 1) % polygon.size()
		var a := Vector3(inner[i].x, inner[i].y, depth)
		var b := Vector3(inner[j].x, inner[j].y, depth)
		var c := Vector3(polygon[j].x, polygon[j].y, depth - bevel)
		var d := Vector3(polygon[i].x, polygon[i].y, depth - bevel)
		_quad_outward(edges, a, b, c, d, Vector3(center.x, center.y, 0.0))
		_quad_outward(edges, Vector3(a.x, a.y, -depth), Vector3(b.x, b.y, -depth), Vector3(c.x, c.y, -depth + bevel), Vector3(d.x, d.y, -depth + bevel), Vector3(center.x, center.y, 0.0))
		_quad_outward(sides, d, c, Vector3(c.x, c.y, -depth + bevel), Vector3(d.x, d.y, -depth + bevel), Vector3(center.x, center.y, 0.0))
	edges.commit(mesh)
	sides.commit(mesh)
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	add_child(instance)


func _flat_shape(mesh_name: String, polygon: PackedVector2Array, z: float, material: Material) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for i in range(0, triangles.size(), 3):
		var a := polygon[triangles[i]]
		var b := polygon[triangles[i + 1]]
		var c := polygon[triangles[i + 2]]
		_front_triangle(surface, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z))
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = surface.commit()
	add_child(instance)


func _quad_outward(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3) -> void:
	if (b - a).cross(c - a).dot((a + b + c + d) * 0.25 - center) >= 0.0:
		_triangle(surface, a, b, c)
		_triangle(surface, a, c, d)
	else:
		_triangle(surface, a, c, b)
		_triangle(surface, a, d, c)


func _front_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).z > 0.0:
		_triangle(surface, a, b, c)
	else:
		_triangle(surface, a, c, b)


func _back_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).z < 0.0:
		_triangle(surface, a, b, c)
	else:
		_triangle(surface, a, c, b)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color = Color.WHITE) -> void:
	var normal := (b - a).cross(c - a).normalized()
	surface.set_color(color)
	surface.set_normal(normal)
	# Godot uses clockwise front faces, the opposite of the geometric normal.
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
