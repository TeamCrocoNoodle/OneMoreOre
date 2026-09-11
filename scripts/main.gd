extends Node3D
## The prototype contains only the rock, the pickaxe, and their physical feedback.

const Geometry = preload("res://scripts/rock_geometry.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Pickaxe = preload("res://scripts/pickaxe.gd")
const MiningAudio = preload("res://scripts/mining_audio.gd")
const Effects = preload("res://scripts/mining_effects.gd")
const Gem = preload("res://scripts/gem.gd")

var camera := Camera3D.new()
var rock_motion := Node3D.new()
var shell := Node3D.new()
var effects := Effects.new()
var audio := MiningAudio.new()
var pickaxe := Pickaxe.new()
var gem: StaticBody3D
var marker := MeshInstance3D.new()
var chunks: Array[StaticBody3D] = []
var hovered: StaticBody3D
var aim_position := Vector2.ZERO
var pending_aim := Vector2.ZERO
var mouse_down := false
var dragging := false
var touch_id := -1
var touch_start := Vector2.ZERO
var touch_rotating := false
var touch_time := 0.0
var using_controller := false
var controller_id := -1
var impact_pending := false
var swing_cooldown := 0.0
var idle_time := 0.0
var elapsed := 0.0
var camera_shake := 0.0
var hit_stop := 0.0
var wobble := Vector3.ZERO
var wobble_velocity := Vector3.ZERO
var squash := 0.0
var reveal_time := -1.0
var rock_number := 0
var hit_count := 0
var broken_count := 0
var collected_count := 0
var focused := true
var camera_rest := Vector3(0, 1.35, 11.5)
var rng := RandomNumberGenerator.new()
var capture_mode := false
var capture_stage := 0
var capture_clock := 0.0
var capture_hit_clock := 0.0
var spawn_time := 1.0

func _ready() -> void:
	rng.seed = 1729
	_create_actions()
	_create_stage()
	add_child(audio)
	add_child(effects)
	add_child(rock_motion)
	rock_motion.add_child(shell)
	_spawn_rock()
	add_child(pickaxe)
	pickaxe.setup(camera)
	pickaxe.impacted.connect(func(): impact_pending = true)
	pickaxe.swing_started.connect(audio.play_swing)
	get_viewport().size_changed.connect(_resize)
	_resize()
	aim_position = get_viewport().get_visible_rect().size * Vector2(0.48, 0.46)
	pickaxe.set_target(aim_position)
	capture_mode = "--capture-sequence" in OS.get_cmdline_user_args()
	if capture_mode:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	Input.joy_connection_changed.connect(_controller_connection)
	for device in Input.get_connected_joypads():
		controller_id = device

func _create_actions() -> void:
	_bind_key("mine", KEY_SPACE)
	_bind_button("mine", JOY_BUTTON_A)
	_bind_button("mine", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_axis("mine", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_key("orbit_left", KEY_A)
	_bind_key("orbit_left", KEY_LEFT)
	_bind_key("orbit_right", KEY_D)
	_bind_key("orbit_right", KEY_RIGHT)
	_bind_key("orbit_up", KEY_W)
	_bind_key("orbit_up", KEY_UP)
	_bind_key("orbit_down", KEY_S)
	_bind_key("orbit_down", KEY_DOWN)
	_bind_button("orbit_left", JOY_BUTTON_DPAD_LEFT)
	_bind_button("orbit_right", JOY_BUTTON_DPAD_RIGHT)
	_bind_button("orbit_up", JOY_BUTTON_DPAD_UP)
	_bind_button("orbit_down", JOY_BUTTON_DPAD_DOWN)
	_bind_axis("orbit_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("orbit_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("orbit_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("orbit_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)

func _action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)

func _bind_key(action: String, key: Key) -> void:
	_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func _bind_button(action: String, button: JoyButton) -> void:
	_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func _bind_axis(action: String, axis: JoyAxis, value: float) -> void:
	_action(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)

func _create_stage() -> void:
	var backdrop := CanvasLayer.new()
	backdrop.layer = -10
	add_child(backdrop)
	var canvas := ColorRect.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = preload("res://shaders/backdrop.gdshader")
	canvas.material = backdrop_material
	backdrop.add_child(canvas)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CANVAS
	settings.background_canvas_max_layer = -10
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("bad6e0")
	settings.ambient_light_energy = 0.40
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.tonemap_exposure = 1.0
	environment.environment = settings
	add_child(environment)
	add_child(camera)
	camera.position = camera_rest
	camera.look_at(Vector3(0, -0.08, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.3
	camera.near = 0.05
	camera.far = 60.0
	camera.current = true
	_light(Vector3(-42, -32, 0), Color("fff1d9"), 2.2, true)
	_light(Vector3(-18, 142, 0), Color("a1daef"), 0.30)
	_light(Vector3(35, 30, 0), Color("7394b0"), 0.18)
	var shadow := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(6.0, 1.1)
	shadow.mesh = plane
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = preload("res://shaders/soft_shadow.gdshader")
	shadow.material_override = shadow_material
	shadow.position = Vector3(0, -3.0, -0.2)
	shadow.rotation = camera.rotation
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	var target_mesh := TorusMesh.new()
	target_mesh.inner_radius = 0.025
	target_mesh.outer_radius = 0.041
	target_mesh.rings = 16
	target_mesh.ring_segments = 4
	marker.mesh = target_mesh
	var target_material := StandardMaterial3D.new()
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_material.albedo_color = Color("fff0be")
	marker.material_override = target_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)

func _light(angles: Vector3, color: Color, energy: float, shadows: bool = false) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.directional_shadow_max_distance = 24.0
	light.shadow_bias = 0.035
	light.shadow_normal_bias = 0.8
	add_child(light)

func _spawn_rock() -> void:
	if is_instance_valid(gem) and gem.get_parent() != shell:
		gem.queue_free()
	for child in shell.get_children():
		child.queue_free()
	chunks.clear()
	hovered = null
	broken_count = 0
	shell.rotation = Vector3(0.12, 0.24, -0.06)
	rock_motion.scale = Vector3.ONE
	rock_motion.position = Vector3.ZERO
	for layer in range(3):
		var radius := 2.62 - float(layer) * 0.59
		var cells: Array[Dictionary] = Geometry.build_layer(radius, layer, 461 + rock_number * 37)
		for data in cells:
			var chunk := Chunk.new()
			shell.add_child(chunk)
			chunk.configure(data, layer)
			chunk.set_meta("stone_color", data.color)
			chunk.set_meta("outward", data.direction)
			chunks.append(chunk)
	gem = Gem.new()
	shell.add_child(gem)
	gem.rotation_degrees = Vector3(8, 18, -12)
	rock_number += 1
	reveal_time = -1.0
	if rock_number > 1:
		audio.play_respawn()
		spawn_time = 0.0
		rock_motion.scale = Vector3.ONE * 0.01
		create_tween().tween_property(rock_motion, "scale", Vector3.ONE, 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1)
	# KEEP_HEIGHT retains landscape composition; portrait increases height to fit the rock.
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(8.3, 7.2 / aspect)
	if aim_position != Vector2.ZERO:
		aim_position = aim_position.clamp(Vector2.ZERO, viewport_size)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		using_controller = false
		aim_position = event.position
		if dragging:
			_orbit(event.relative * 0.007)
	elif event is InputEventMouseButton:
		using_controller = false
		aim_position = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_down = event.pressed
			if mouse_down:
				_request_swing()
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_orbit(Vector2(-0.14, 0))
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_orbit(Vector2(0.14, 0))
	elif event is InputEventPanGesture:
		_orbit(event.delta * 0.065)
	elif event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			touch_id = event.index
			touch_start = event.position
			aim_position = event.position
			touch_rotating = false
			touch_time = 0.0
			using_controller = false
		elif not event.pressed and event.index == touch_id:
			if not touch_rotating and touch_time < 0.18:
				_request_swing()
			touch_id = -1
			touch_rotating = false
	elif event is InputEventScreenDrag and event.index == touch_id:
		aim_position = event.position
		if event.position.distance_to(touch_start) > 14.0:
			touch_rotating = true
		if touch_rotating:
			_orbit(event.relative * 0.007)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadButton or absf(event.axis_value) > 0.22:
			using_controller = true
			controller_id = event.device
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			_reset_rock()
		elif event.physical_keycode == KEY_F11:
			var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("mine"):
		_request_swing()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		mouse_down = false
		dragging = false
		touch_id = -1
		touch_rotating = false
		touch_time = 0.0
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func _controller_connection(device: int, connected: bool) -> void:
	if connected:
		controller_id = device
	elif controller_id == device:
		controller_id = -1
		using_controller = false

func _orbit(amount: Vector2) -> void:
	if reveal_time >= 0.0:
		return
	shell.quaternion = Quaternion(Vector3.UP, amount.x) * Quaternion(Vector3.RIGHT, amount.y) * shell.quaternion
	idle_time = 0.0

func _request_swing() -> void:
	if not focused or reveal_time >= 0.0 or swing_cooldown > 0.0 or pickaxe.is_swinging or dragging or touch_rotating:
		return
	pending_aim = aim_position
	pickaxe.set_target(pending_aim)
	var contact := ray_at(pending_aim)
	if not contact.is_empty():
		pickaxe.set_contact_point(contact.position)
	pickaxe.swing()
	swing_cooldown = 0.30
	idle_time = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	spawn_time += delta
	idle_time += delta
	swing_cooldown = maxf(0.0, swing_cooldown - delta)
	if touch_id >= 0:
		touch_time += delta
	if focused:
		var orbit := Input.get_vector("orbit_left", "orbit_right", "orbit_up", "orbit_down")
		if orbit.length() > 0.05:
			_orbit(orbit * delta * 1.65)
		if using_controller:
			var aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
			aim_position += aim * get_viewport().get_visible_rect().size.y * delta * 0.65
			aim_position = aim_position.clamp(Vector2.ONE * 30.0, get_viewport().get_visible_rect().size - Vector2.ONE * 30.0)
		if mouse_down or Input.is_action_pressed("mine") or (touch_id >= 0 and touch_time >= 0.18 and not touch_rotating):
			_request_swing()
	if not pickaxe.is_swinging:
		pickaxe.set_target(aim_position)
	hit_stop = maxf(0.0, hit_stop - delta)
	if hit_stop <= 0.0:
		wobble_velocity += (-wobble * 170.0 - wobble_velocity * 15.0) * delta
		wobble += wobble_velocity * delta
		rock_motion.rotation = wobble
		if reveal_time < 0.0:
			rock_motion.position.y = sin(elapsed * 1.2) * 0.055
			if idle_time > 3.0:
				shell.rotate_y(delta * 0.055)
	squash = move_toward(squash, 0.0, delta * 0.5)
	if reveal_time < 0.0 and spawn_time > 0.68:
		rock_motion.scale = Vector3(1.0 + squash * 0.4, 1.0 - squash, 1.0 + squash * 0.4)
	camera_shake = move_toward(camera_shake, 0.0, delta * 0.8)
	camera.position = camera_rest + Vector3(sin(elapsed * 143.0), sin(elapsed * 117.0), 0) * camera_shake
	if reveal_time >= 0.0:
		reveal_time += delta
		gem.rotation.y += delta * 1.3
		gem.position = Vector3(0, 0.25 + sin(elapsed * 2.0) * 0.08, 2.1)
		gem.scale = Vector3.ONE * (1.0 + smoothstep(0.0, 0.7, reveal_time) * 0.55)
		if reveal_time > 2.8:
			_spawn_rock()
	if capture_mode:
		_capture_tick(delta)

func _physics_process(_delta: float) -> void:
	if impact_pending:
		impact_pending = false
		_mine_at(pending_aim)
	var result := ray_at(aim_position)
	var next_hover: StaticBody3D = result.get("collider") as StaticBody3D
	if next_hover != hovered:
		if is_instance_valid(hovered) and hovered.has_method("set_hovered"):
			hovered.set_hovered(false)
		hovered = next_hover
		if is_instance_valid(hovered) and hovered.has_method("set_hovered"):
			hovered.set_hovered(true)
	marker.visible = not result.is_empty() and reveal_time < 0.0 and not dragging and touch_id < 0
	if marker.visible:
		marker.position = result.position + result.normal * 0.025
		marker.quaternion = Quaternion(Vector3.UP, result.normal.normalized())

func ray_at(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 40.0, 3)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _mine_at(screen_position: Vector2) -> bool:
	if reveal_time >= 0.0:
		return false
	var result := ray_at(screen_position)
	if result.is_empty():
		return false
	var body: StaticBody3D = result.collider
	if body == gem:
		_reveal_gem()
		return true
	if not body.has_method("hit"):
		return false
	hit_count += 1
	var point: Vector3 = result.position
	var normal: Vector3 = result.normal
	var layer: int = body.layer_index
	var color: Color = body.get_meta("stone_color")
	var placement: Transform3D = body.mesh_instance.global_transform
	var broken: bool = body.hit(1.0, point)
	effects.impact(point, normal, broken, color)
	audio.play_hit(1.15 if broken else 0.9, layer)
	if broken:
		audio.play_break(layer)
		effects.shed_chunk(body.mesh_instance.mesh, body.mesh_instance.material_override, placement, normal)
		chunks.erase(body)
		body.queue_free()
		broken_count += 1
	camera_shake = 0.075 if broken else 0.035
	hit_stop = 0.055 if broken else 0.025
	squash = 0.045 if broken else 0.022
	wobble_velocity += Vector3(normal.y * 0.8, -normal.x * 0.7, -normal.x * 0.6) + Vector3(0.3, 0.1, -0.12)
	if controller_id >= 0 and using_controller:
		Input.start_joy_vibration(controller_id, 0.28 if broken else 0.1, 0.52 if broken else 0.25, 0.10 if broken else 0.055)
	return true

func _reveal_gem() -> void:
	reveal_time = 0.0
	collected_count += 1
	audio.play_reveal()
	effects.gem_burst(Vector3(0, 0.1, 1.4))
	camera_shake = 0.12
	marker.hide()
	var shown := 0
	for chunk in chunks:
		if is_instance_valid(chunk):
			if shown < 16 and chunk.global_position.z > -0.5:
				effects.shed_chunk(chunk.mesh_instance.mesh, chunk.mesh_instance.material_override, chunk.mesh_instance.global_transform, chunk.global_position.normalized() * 1.4)
				shown += 1
			chunk.collision_layer = 0
			chunk.hide()
			chunk.queue_free()
	chunks.clear()
	hovered = null
	gem.reparent(rock_motion)
	gem.collision_layer = 0
	# Reparenting keeps the extracted gem independent of the rock's current rotation.
	gem.rotation = Vector3(0.12, 0.0, -0.16)
	if controller_id >= 0 and using_controller:
		Input.start_joy_vibration(controller_id, 0.5, 0.7, 0.22)

func _reset_rock() -> void:
	if is_instance_valid(gem) and gem.get_parent() != shell:
		gem.queue_free()
	_spawn_rock()

func _capture_tick(delta: float) -> void:
	# Reproducible rendered interaction, available only through the explicit CLI flag.
	capture_clock += delta
	if capture_stage == 0 and capture_clock > 1.0:
		_capture("01_intact")
		capture_stage = 1
		capture_clock = 0.0
	elif capture_stage == 1 and capture_clock > 0.25:
		aim_position = camera.unproject_position(Vector3(0.25, 0.35, 0))
		_request_swing()
		capture_stage = 2
		capture_clock = 0.0
	elif capture_stage == 2 and capture_clock > 0.43:
		_capture("02_first_hit")
		capture_stage = 3
		capture_clock = 0.0
	elif capture_stage == 3:
		capture_hit_clock += delta
		if capture_hit_clock > 0.38:
			capture_hit_clock = 0.0
			_request_swing()
		if broken_count >= 1:
			capture_stage = 30
			capture_clock = 0.0
	elif capture_stage == 30 and capture_clock > 0.45:
		_capture("03_open_shell")
		capture_stage = 4
		capture_clock = 0.0
	elif capture_stage == 4:
		capture_hit_clock += delta
		if capture_hit_clock > 0.38:
			capture_hit_clock = 0.0
			_request_swing()
		if reveal_time >= 0.6:
			_capture("04_gem")
			capture_stage = 5
			capture_clock = 0.0
	elif capture_stage == 5 and capture_clock > 3.0:
		_capture("05_fresh_rock")
		capture_stage = 6
		capture_clock = 0.0
	elif capture_stage == 6 and capture_clock > 0.3:
		get_window().size = Vector2i(1280, 720)
		capture_stage = 7
		capture_clock = 0.0
	elif capture_stage == 7 and capture_clock > 0.7:
		_capture("06_wide")
		capture_stage = 8
		capture_clock = 0.0
	elif capture_stage == 8 and capture_clock > 0.3:
		get_window().size = Vector2i(600, 900)
		capture_stage = 9
		capture_clock = 0.0
	elif capture_stage == 9 and capture_clock > 0.7:
		_capture("07_portrait")
		capture_stage = 10
		capture_clock = 0.0
	elif capture_stage == 10 and capture_clock > 0.3:
		print("CAPTURE_OK hits=", hit_count, " gems=", collected_count)
		get_tree().quit()
	if elapsed > 40.0:
		push_error("Capture sequence timed out")
		get_tree().quit(1)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/" + label + ".png")
