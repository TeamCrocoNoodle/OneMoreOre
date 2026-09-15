extends Node3D
## Tools turn inward across the ore; hand tools swing around their leather grip.
const ToolVisual = preload("res://scripts/tool_visual.gd")
const Tools = preload("res://scripts/main_tools.gd")

signal impacted
signal swing_started

var is_swinging: bool = false
var speed_multiplier := 1.0
var tool_id := "pickaxe"
var impact_index := 0
var _tip := Vector3(-1.44, -0.36, 0)
var _visual: Node3D
var _machine := false
var _strike_times := PackedFloat32Array([0.12])
var _cycle := 0.34

const STRIKE_TIME := 0.12
const SWING_DURATION := 0.34
const PICK_TIP := Vector3(-1.44, -0.36, 0.0)
const HANDLE_GRIP := Vector3(-0.04, -1.60, 0.0)
const RECOIL := Vector3(0.055, 0.09, 0.13)
const VERTICAL_FACING_LIMIT := deg_to_rad(65.0)

var _camera: Camera3D
var _target := Vector2.ZERO
var _elapsed := 0.0
var _idle_time := 0.0
var _impact_sent := false
var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3(0.08, 0.0, -0.70)
var _contact_position := Vector3.ZERO
var _contact_rotation := Vector3(0.12, 0.0, 0.52)
var _contact_override := Vector3.ZERO
var _has_contact_override := false
var _wind_rotation := Vector3.ZERO
var _grip_position := Vector3.ZERO
var _tool_scale := 0.88
var _ore_center := Vector3.ZERO
var _ore_radius := 2.8
var _facing_basis := Basis.IDENTITY
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
	_set_pose_rotation(_rest_rotation)
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


func set_tool(id: String) -> void:
	if Tools.definition(id).is_empty() or (_built and tool_id == id):
		return
	cancel_swing()
	tool_id = id
	_machine = id in ["jackhammer", "drill"]
	_rest_rotation = Vector3(0.08, 0.0, -0.70)
	_contact_rotation = Vector3(0.12, 0.0, 0.52)
	_tip = PICK_TIP
	_cycle = 0.46 if id == "jackhammer" else SWING_DURATION
	_strike_times = PackedFloat32Array([0.08,0.18,0.28]) if id == "jackhammer" else PackedFloat32Array([0.09 if id == "drill" else STRIKE_TIME])
	match id:
		"axe":
			_tip = Vector3(-1.31,-0.10,0)
			_rest_rotation.z = -0.85
		"hammer":
			_tip = Vector3(-1.19,0.03,0)
			_rest_rotation.z = -0.82
		"jackhammer", "drill":
			_tip = Vector3(0,-2.30 if id == "jackhammer" else -2.27,0)
			_rest_rotation = Vector3(-0.10,0.0,-0.42)
			_contact_rotation = Vector3(-0.05,0.0,-0.32)
	if is_instance_valid(_visual):
		remove_child(_visual)
		_visual.queue_free()
	_build_tool()
	if is_instance_valid(_camera):
		_refresh_rest()
		position = _rest_position
		_set_pose_rotation(_rest_rotation)


func get_tip_local() -> Vector3:
	return _tip


func get_grip_local() -> Vector3:
	# Model-space grip centers. Keep the authored meshes (and shop previews)
	# in their original coordinates; the animation supplies the pivot offset.
	if tool_id == "jackhammer":
		return Vector3(0, 0.13, 0)
	if tool_id == "drill":
		return Vector3(0.64, -0.73, 0)
	return HANDLE_GRIP


func get_cycle_duration() -> float:
	return _cycle


func set_target(screen_position: Vector2) -> void:
	if screen_position != _target:
		_has_contact_override = false
	_target = screen_position


func get_target_screen() -> Vector2:
	return _target


func set_ore_bounds(center: Vector3, radius: float) -> void:
	_ore_center = center
	_ore_radius = maxf(radius, 0.1)


func _refresh_facing() -> void:
	# Project both ore axes, keeping the same turn on larger ores and narrow
	# viewports. Reuse the camera; no extra mining raycast is needed.
	var center := _camera.unproject_position(_ore_center)
	var right := _camera.unproject_position(_ore_center + _camera.global_basis.x * _ore_radius)
	var top := _camera.unproject_position(_ore_center + _camera.global_basis.y * _ore_radius)
	var lateral := clampf((_target.x - center.x) / maxf(absf(right.x - center.x), 1.0), -1.0, 1.0)
	var vertical := clampf((_target.y - center.y) / maxf(absf(top.y - center.y), 1.0), -1.0, 1.0)
	# The negative half-turn points the blade into the screen at the center.
	# Easing to the side poses avoids a snap at either edge of the ore.
	var yaw := lerpf(-PI, 0.0, smoothstep(-1.0, 1.0, lateral))
	var tilt := lerpf(VERTICAL_FACING_LIMIT, -VERTICAL_FACING_LIMIT, smoothstep(-1.0, 1.0, vertical))
	# Tilt in the turned frame so diagonal aim also inclines toward the ore.
	# A bounded tilt keeps the hand tool from folding over at the bottom edge.
	_facing_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt)


func _pose_basis(pose: Vector3) -> Basis:
	return _facing_basis * Basis.from_euler(pose)


func _set_pose_rotation(pose: Vector3) -> void:
	basis = _pose_basis(pose).scaled(Vector3.ONE * _tool_scale)


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
	_elapsed = 0.0
	impact_index = 0
	_impact_sent = false
	is_swinging = true
	swing_started.emit()


func cancel_swing() -> void:
	is_swinging = false
	_impact_sent = true
	_elapsed = 0.0
	if is_instance_valid(_visual) and is_instance_valid(_visual.piston):
		_visual.piston.position.y = 0.0
	if is_instance_valid(_trail):
		_trail.hide()


func _refresh_swing_poses() -> void:
	# Solve the hand position once from the desired contact pose. The hand
	# follows the live cursor, but stays in place while the head swings.
	var contact_depth := 5.7
	if _has_contact_override:
		contact_depth = clampf(-_camera.to_local(_contact_override).z - 0.10, 1.0, 5.7)
	# Keep the cursor tool in front of the stone instead of burying its handle
	# during the strike. Fresh projection also prevents camera shake from
	# dragging the tip away from the cursor between physics ray updates.
	var contact := _camera.to_local(_camera.project_position(_target, contact_depth))
	var contact_basis := _pose_basis(_contact_rotation)
	_contact_position = contact - contact_basis * (_tip * _tool_scale)
	_wind_rotation = _rest_rotation + Vector3(-0.04, 0.0, -0.42)
	_grip_position = _contact_position + contact_basis * (get_grip_local() * _tool_scale)
	if not _machine:
		_rest_position = _position_about_grip(_rest_rotation)


func _position_about_grip(pose: Vector3, displacement: Vector3 = Vector3.ZERO) -> Vector3:
	return _grip_position + _facing_basis * displacement - _pose_basis(pose) * (get_grip_local() * _tool_scale)


func _pose_about_grip(pose: Vector3, displacement: Vector3 = Vector3.ZERO) -> void:
	_set_pose_rotation(pose)
	position = _position_about_grip(pose, displacement)


func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	_idle_time += delta
	_refresh_rest()
	if is_instance_valid(_visual):
		_visual.animate(delta * speed_multiplier, is_swinging)
	if _machine:
		_process_machine(delta)
		if is_instance_valid(_trail):
			_trail.hide()
		return
	if is_swinging:
		_elapsed += delta * speed_multiplier
		if _elapsed < 0.065:
			var t := smoothstep(0.0, 0.065, _elapsed)
			_pose_about_grip(_rest_rotation.lerp(_wind_rotation, t))
		elif _elapsed < STRIKE_TIME:
			var t := _strike_fraction(_elapsed)
			_pose_about_grip(_wind_rotation.lerp(_contact_rotation, t))
		elif _elapsed < 0.153:
			# A short exact hold gives the strike weight before the spring recoil.
			position = _contact_position
			_set_pose_rotation(_contact_rotation)
		elif _elapsed < 0.185:
			var t := smoothstep(0.153, 0.185, _elapsed)
			_pose_about_grip(_contact_rotation + Vector3(0.0, -0.025, -0.095) * t, RECOIL * _tool_scale * t)
		else:
			var t := clampf((_elapsed - 0.185) / (SWING_DURATION - 0.185), 0.0, 1.0)
			var settle := smoothstep(0.0, 1.0, t)
			var pose := (_contact_rotation + Vector3(0.0, -0.025, -0.095)).lerp(_rest_rotation, settle)
			pose.z -= sin(t * PI) * 0.10
			_pose_about_grip(pose, RECOIL * _tool_scale * (1.0 - settle))
		if _elapsed >= STRIKE_TIME and not _impact_sent:
			_impact_sent = true
			impact_index = 1
			# Fast upgrades or a slow frame may skip the hold interval. Emit the
			# contact at the exact strike pose, just as the powered tools do.
			position = _contact_position
			_set_pose_rotation(_contact_rotation)
			impacted.emit()
		if _elapsed >= SWING_DURATION:
			is_swinging = false
	else:
		_pose_about_grip(_rest_rotation + Vector3(0.0, 0.0, sin(_idle_time * 1.5) * 0.009), Vector3(0.0, sin(_idle_time * 1.8) * 0.022, 0.0))
	_update_trail()


func _process_machine(delta: float) -> void:
	if is_instance_valid(_visual.piston):
		_visual.piston.position.y = 0.0
	if not is_swinging:
		position = _rest_position + Vector3(0,sin(_idle_time*2.0)*0.012,0)
		_set_pose_rotation(_rest_rotation)
		return
	_elapsed += delta * speed_multiplier
	var first := float(_strike_times[0])
	var last := float(_strike_times[-1])
	if _elapsed < first:
		var t := smoothstep(0,first,_elapsed)
		position = _rest_position.lerp(_contact_position,t)
		_set_pose_rotation(_rest_rotation.lerp(_contact_rotation,t))
	elif _elapsed <= last + 0.035:
		var phase := fposmod(_elapsed-first,0.10)/0.10
		position = _contact_position + _facing_basis * Vector3(0,0.11,0.08)*sin(phase*PI)
		_set_pose_rotation(_contact_rotation)
		if is_instance_valid(_visual.piston):
			_visual.piston.position.y = 0.10 * sin(phase*PI)
	else:
		var t := smoothstep(last+0.035,_cycle,_elapsed)
		position = _contact_position.lerp(_rest_position,t)
		_set_pose_rotation(_contact_rotation.lerp(_rest_rotation,t))
	while impact_index < _strike_times.size() and _elapsed >= _strike_times[impact_index]:
		# Even a long frame preserves all three pulses; Main queues physics work.
		position = _contact_position
		_set_pose_rotation(_contact_rotation)
		if is_instance_valid(_visual.piston):
			_visual.piston.position.y = 0.0
		impact_index += 1
		impacted.emit()
	if _elapsed >= _cycle:
		is_swinging = false


func _refresh_rest() -> void:
	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var half_height := _camera.size * 0.5
	var half_width := half_height * aspect
	if _camera.keep_aspect == Camera3D.KEEP_WIDTH:
		half_width = _camera.size * 0.5
		half_height = half_width / aspect
	_tool_scale = clampf(half_width / 4.6, 0.60, 0.92)
	if _machine:
		_tool_scale *= 0.84
	scale = Vector3.ONE * _tool_scale
	_refresh_facing()
	if _machine:
		# Powered tools approach along their bit instead of winding up a swing.
		var cursor := _camera.to_local(_camera.project_position(_target, 5.7))
		_rest_position = cursor - _pose_basis(_rest_rotation) * (_tip * _tool_scale) + _facing_basis * Vector3(0.13, 0.22, 0.0) * _tool_scale
	_refresh_swing_poses()


func _strike_fraction(time: float) -> float:
	return pow(clampf((time - 0.065) / 0.055, 0.0, 1.0), 1.25)


func _stroke_position(t: float) -> Vector3:
	# Sample the same grip-centered rotation for both the model and its trail.
	return _position_about_grip(_wind_rotation.lerp(_contact_rotation, t))


func _stroke_tip(time: float) -> Vector3:
	var t := _strike_fraction(time)
	var tip_basis := _pose_basis(_wind_rotation.lerp(_contact_rotation, t))
	return _stroke_position(t) + tip_basis * (_tip * _tool_scale)


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
	_visual = ToolVisual.new()
	_visual.build(tool_id)
	add_child(_visual)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color = Color.WHITE) -> void:
	var normal := (b - a).cross(c - a).normalized()
	surface.set_color(color)
	surface.set_normal(normal)
	# Godot uses clockwise front faces, the opposite of the geometric normal.
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
