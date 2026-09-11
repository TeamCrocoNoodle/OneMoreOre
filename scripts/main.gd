extends Node3D
## The prototype contains only the rock, the pickaxe, and their physical feedback.

const Geometry = preload("res://scripts/rock_geometry.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Pickaxe = preload("res://scripts/pickaxe.gd")
const MiningAudio = preload("res://scripts/mining_audio.gd")
const Effects = preload("res://scripts/mining_effects.gd")
const Gem = preload("res://scripts/gem.gd")
const GemLight = preload("res://scripts/gem_light.gd")
const ROCK_RADIUS := 4.9
const LAYER_COUNT := 6
const LAYER_COUNTS := [100, 80, 60, 42, 26, 14]
const COMMON_GEM_COUNT := 5
const SPECIAL_GEM_COUNT := 1

var camera := Camera3D.new()
var rock_motion := Node3D.new()
var shell := Node3D.new()
var effects := Effects.new()
var audio := MiningAudio.new()
var pickaxe := Pickaxe.new()
var gems: Array[StaticBody3D] = []
var collecting_gems: Array[Dictionary] = []
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
var completion_time := -1.0
var rock_number := 0
var rock_seed := 0
var showcase_mode := false
var showcase_covers: Array[StaticBody3D] = []
var light_pulse_history: Array[int] = []
var gems_collected_this_rock := 0
var special_collected_count := 0
var pending_rock_number := -1
var hit_count := 0
var broken_count := 0
var collected_count := 0
var focused := true
var camera_rest := Vector3(0, 2.0, 18.0)
var rng := RandomNumberGenerator.new()
var capture_mode := false
var capture_stage := 0
var capture_clock := 0.0
var capture_saved_tier := -1
var capture_impact_points: Array[Vector3] = []
var capture_fracture_center := Vector3.ZERO
var capture_fracture_count := 0
var capture_plain_count := 0
var capture_plain: StaticBody3D
var spawn_time := 1.0
var spawn_tween: Tween
var capture_gem: StaticBody3D
var capture_seed := 12873

func _ready() -> void:
	capture_mode = "--capture-sequence" in OS.get_cmdline_user_args()
	rng.seed = capture_seed if capture_mode else int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	_create_actions()
	_create_stage()
	add_child(audio)
	add_child(effects)
	add_child(rock_motion)
	rock_motion.add_child(shell)
	_spawn_rock(capture_seed, true)
	add_child(pickaxe)
	pickaxe.setup(camera)
	pickaxe.impacted.connect(func(): impact_pending = true)
	pickaxe.swing_started.connect(audio.play_swing)
	get_viewport().size_changed.connect(_resize)
	_resize()
	aim_position = get_viewport().get_visible_rect().size * Vector2(0.48, 0.46)
	if showcase_covers.size() == 6 and is_instance_valid(showcase_covers[5]):
		aim_position = camera.unproject_position(showcase_covers[5].to_global(showcase_covers[5].face_center))
	pickaxe.set_target(aim_position)
	if capture_mode:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	Input.joy_connection_changed.connect(_controller_connection)
	for device in Input.get_connected_joypads():
		controller_id = device
	_warm_gem_renderer.call_deferred()

func _warm_gem_renderer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Compatibility compiles rendering variants on their first actual draw.
	# Submit hidden gems and hit effects during startup in an offscreen world,
	# so the first hit/discovery does not have to do it. Real gems stay sealed.
	var warmup := SubViewport.new()
	warmup.name = "GemRenderWarmup"
	warmup.size = Vector2i(96, 96)
	warmup.msaa_3d = get_viewport().msaa_3d
	warmup.world_3d = World3D.new()
	warmup.world_3d.environment = get_world_3d().environment
	warmup.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(warmup)
	var warm_camera := Camera3D.new()
	warm_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	warm_camera.size = 4.0
	warm_camera.position = Vector3(0, 0, 5)
	warm_camera.current = true
	warmup.add_child(warm_camera)
	for child in get_children():
		if child is DirectionalLight3D:
			warmup.add_child(child.duplicate(0))
	for i in gems.size():
		var source: MeshInstance3D = gems[i].facets
		var proxy := MeshInstance3D.new()
		proxy.mesh = source.mesh
		proxy.material_override = source.material_override
		proxy.cast_shadow = source.cast_shadow
		proxy.position = Vector3((float(i % 3) - 1.0) * 1.15, 0.70 if i < 3 else -0.70, 0)
		warmup.add_child(proxy)
	var warm_effects := Node3D.new()
	warm_effects.position.z = 1.2
	warmup.add_child(warm_effects)
	effects.append_render_warmup(warm_effects)
	var warm_light := GemLight.new()
	warm_effects.add_child(warm_light)
	warm_light.position.z = 1.2
	warm_light.configure(PackedVector3Array(), Vector3.ZERO, Vector3.BACK, 0)
	var seam: Array[Dictionary] = [{"a": Vector3(-0.5, 0, 0), "b": Vector3(0.5, 0.1, 0), "width": 0.024}]
	warm_light.set_cracks(seam, Vector3.ZERO)
	warm_light.pulse(0, 0.5)
	warm_light.set_process(false)
	# The dark stone ribbon has a different unshaded, two-sided material.
	var dark_crack := MeshInstance3D.new()
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in [Vector3(-0.5, -0.02, 0), Vector3(0.5, -0.02, 0), Vector3(0.5, 0.02, 0)]:
		ribbon.set_normal(Vector3.BACK)
		ribbon.add_vertex(vertex)
	dark_crack.mesh = ribbon.commit()
	dark_crack.material_override = chunks[0]._crack_mesh.material_override
	dark_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dark_crack.position = Vector3(0, -1.5, 1.2)
	warm_effects.add_child(dark_crack)
	await RenderingServer.frame_post_draw
	if is_instance_valid(warmup):
		warmup.queue_free()

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
	camera.size = 12.0
	camera.near = 0.05
	camera.far = 60.0
	camera.current = true
	_light(Vector3(-42, -32, 0), Color("fff1d9"), 2.2, true)
	_light(Vector3(-18, 142, 0), Color("a1daef"), 0.30)
	_light(Vector3(35, 30, 0), Color("7394b0"), 0.18)
	var shadow := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(10.6, 1.8)
	shadow.mesh = plane
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = preload("res://shaders/soft_shadow.gdshader")
	shadow.material_override = shadow_material
	shadow.position = Vector3(0, -5.35, -0.2)
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
	light.directional_shadow_max_distance = 34.0
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 0.8
	add_child(light)

func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
	effects.clear_fragments()
	for remnant in effects.get_children():
		if remnant.has_meta("gem_light_pulse") or remnant.get_script() == preload("res://scripts/gem_light.gd"):
			remnant.hide()
			remnant.queue_free()
	if spawn_tween != null and spawn_tween.is_valid():
		spawn_tween.kill()
	for extraction in collecting_gems:
		if is_instance_valid(extraction.node):
			extraction.node.queue_free()
	collecting_gems.clear()
	for child in shell.get_children():
		if child is CollisionObject3D:
			child.collision_layer = 0
		child.hide()
		child.queue_free()
	chunks.clear()
	gems.clear()
	showcase_covers.clear()
	light_pulse_history.clear()
	showcase_mode = showcase
	hovered = null
	broken_count = 0
	gems_collected_this_rock = 0
	impact_pending = false
	rock_seed = seed_override if seed_override >= 0 else int(rng.randi())
	shell.rotation = Vector3(0.12, 0.24, -0.06)
	rock_motion.scale = Vector3.ONE
	rock_motion.position = Vector3.ZERO
	wobble = Vector3.ZERO
	wobble_velocity = Vector3.ZERO
	rock_motion.rotation = Vector3.ZERO
	squash = 0.0
	for layer in range(LAYER_COUNT):
		var radius := ROCK_RADIUS - float(layer) * 0.78
		var cells: Array[Dictionary] = Geometry.build_layer(radius, layer, rock_seed, LAYER_COUNTS[layer], 0.86)
		for data in cells:
			var chunk := Chunk.new()
			shell.add_child(chunk)
			chunk.configure(data, layer)
			chunk.set_meta("stone_color", data.color)
			chunk.set_meta("outward", data.direction)
			chunks.append(chunk)
	_place_gems(rock_seed)
	rock_number += 1
	completion_time = -1.0
	if rock_number > 1:
		audio.play_respawn()
		spawn_time = 0.0
		rock_motion.scale = Vector3.ONE * 0.01
		spawn_tween = create_tween()
		spawn_tween.tween_property(rock_motion, "scale", Vector3.ONE, 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _place_gems(seed_value: int) -> void:
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = seed_value ^ 0x5F3759DF
	# Each gem belongs to one stone volume. Shuffle the occupied layers so a
	# rarity never implies a particular depth in a randomly generated rock.
	var bands: Array[int] = [0, 1, 2, 3, 4, 5]
	for i in range(bands.size() - 1, 0, -1):
		var j := layout_rng.randi_range(0, i)
		var swap := bands[i]
		bands[i] = bands[j]
		bands[j] = swap
	for i in range(COMMON_GEM_COUNT + SPECIAL_GEM_COUNT):
		var jewel := Gem.new()
		jewel.configure(Gem.COMMON if i < COMMON_GEM_COUNT else Gem.SPECIAL, i % COMMON_GEM_COUNT)
		jewel.rotation = Vector3(layout_rng.randf_range(-0.5, 0.5), layout_rng.randf_range(-PI, PI), layout_rng.randf_range(-0.5, 0.5))
		shell.add_child(jewel)
		gems.append(jewel)
	if showcase_mode:
		_place_showcase_gems()
		return
	for i in range(gems.size()):
		var candidates: Array[StaticBody3D] = []
		var largest_socket := 0.0
		for chunk in chunks:
			if chunk.layer_index == bands[i]:
				largest_socket = maxf(largest_socket, chunk.gem_socket_radius)
		for chunk in chunks:
			if chunk.layer_index == bands[i] and chunk.gem_socket_radius >= largest_socket * 0.72:
				candidates.append(chunk)
		assert(not candidates.is_empty(), "Every depth needs a solid stone that can contain a gem")
		var host: StaticBody3D = candidates[layout_rng.randi_range(0, candidates.size() - 1)]
		var contained: bool = host.contain_gem(gems[i])
		assert(contained, "The selected stone must contain its gem")

func _place_showcase_gems() -> void:
	# Six front stones contain one gem each for testing all the light tiers.
	# R and subsequent rocks distribute the host stones over all six depths.
	var slots := [Vector2(-0.42, 0.30), Vector2(0.0, 0.38), Vector2(0.42, 0.30), Vector2(-0.42, -0.28), Vector2(0.0, -0.38), Vector2(0.42, -0.28)]
	showcase_covers.resize(gems.size())
	var used: Array[StaticBody3D] = []
	# Place the larger red crystal first; it needs the widest face aperture.
	for i in range(gems.size() - 1, -1, -1):
		var jewel: StaticBody3D = gems[i]
		var slot: Vector2 = slots[i]
		var world_direction := (camera.global_basis.z + camera.global_basis.x * slot.x + camera.global_basis.y * slot.y).normalized()
		var local_direction := shell.basis.inverse() * world_direction
		var best: StaticBody3D
		var best_score := -INF
		for chunk in chunks:
			if chunk.layer_index != 0 or used.has(chunk):
				continue
			if _face_inradius(chunk) < jewel.bound_radius + 0.07:
				continue
			if chunk.gem_socket_radius <= 0.1:
				continue
			var score: float = chunk.direction.dot(local_direction)
			if score > best_score:
				best = chunk
				best_score = score
		assert(best != null, "No sufficiently wide stone cap for light showcase")
		if best == null:
			continue
		var contained: bool = best.contain_gem(jewel)
		assert(contained, "The showcase stone must contain its gem")
		showcase_covers[i] = best
		used.append(best)

func _face_inradius(chunk: StaticBody3D) -> float:
	var points: PackedVector3Array = chunk.face_points
	var radius := INF
	for i in range(points.size()):
		var a: Vector3 = points[i] - chunk.face_center
		var b: Vector3 = points[(i + 1) % points.size()] - chunk.face_center
		radius = minf(radius, a.cross(b).length() / maxf((b - a).length(), 0.00001))
	return radius

func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1)
	# KEEP_HEIGHT retains landscape composition; portrait increases height to fit the rock.
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(12.0, 11.6 / aspect)
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
		elif event.physical_keycode == KEY_G:
			_spawn_rock(capture_seed, true)
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
	if completion_time >= 0.0:
		return
	shell.quaternion = Quaternion(Vector3.UP, amount.x) * Quaternion(Vector3.RIGHT, amount.y) * shell.quaternion
	idle_time = 0.0

func _request_swing() -> void:
	if (not focused and not capture_mode) or completion_time >= 0.0 or spawn_time < 0.68 or swing_cooldown > 0.0 or pickaxe.is_swinging or dragging or touch_rotating:
		return
	pending_aim = aim_position
	pending_rock_number = rock_number
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
		if completion_time < 0.0:
			rock_motion.position.y = sin(elapsed * 1.2) * 0.055
			if idle_time > 3.0:
				shell.rotate_y(delta * 0.055)
	squash = move_toward(squash, 0.0, delta * 0.5)
	if completion_time < 0.0 and spawn_time > 0.68:
		rock_motion.scale = Vector3(1.0 + squash * 0.4, 1.0 - squash, 1.0 + squash * 0.4)
	camera_shake = move_toward(camera_shake, 0.0, delta * 0.8)
	camera.position = camera_rest + Vector3(sin(elapsed * 143.0), sin(elapsed * 117.0), 0) * camera_shake
	_update_collections(delta)
	if completion_time >= 0.0:
		completion_time += delta
		if completion_time > 2.4:
			_spawn_rock()
	if capture_mode:
		_capture_tick(delta)

func _physics_process(_delta: float) -> void:
	if impact_pending:
		impact_pending = false
		if pending_rock_number == rock_number:
			_mine_at(pending_aim)
	var result := ray_at(aim_position)
	var next_hover: StaticBody3D = result.get("collider") as StaticBody3D
	if next_hover != hovered:
		if is_instance_valid(hovered) and hovered.has_method("set_hovered"):
			hovered.set_hovered(false)
		hovered = next_hover
		if is_instance_valid(hovered) and hovered.has_method("set_hovered"):
			hovered.set_hovered(true)
	marker.visible = not result.is_empty() and completion_time < 0.0 and not dragging and touch_id < 0
	if marker.visible:
		marker.position = result.position + result.normal * 0.025
		marker.quaternion = Quaternion(Vector3.UP, result.normal.normalized())

func ray_at(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 40.0, 3)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _mine_at(screen_position: Vector2) -> bool:
	if completion_time >= 0.0 or spawn_time < 0.68:
		return false
	var result := ray_at(screen_position)
	if result.is_empty():
		return false
	var body: StaticBody3D = result.collider
	if gems.has(body):
		return _collect_gem(body)
	if not body.has_method("hit"):
		return false
	hit_count += 1
	var point: Vector3 = result.position
	var normal: Vector3 = result.normal
	var layer: int = body.layer_index
	var color: Color = body.get_meta("stone_color")
	var placement: Transform3D = body.mesh_instance.global_transform
	var broken: bool = body.hit(1.0, point)
	var auto_collected := false
	if body.is_gem_cover and body.light_node != null:
		var tier: int = body.light_node.current_tier
		light_pulse_history.append(tier)
		if light_pulse_history.size() > 128:
			light_pulse_history.pop_front()
		if not broken:
			audio.play_resonance(tier, 1.0 - body.health / body.max_health)
	effects.impact(point, normal, broken, color, body.is_gem_cover)
	if not broken and not body.is_gem_cover:
		audio.play_hit(0.9, layer)
	if broken:
		body.set_process(false)
		if is_instance_valid(body.light_node):
			# Extinguish the fissures in this same impact. The light remains
			# owned by the stone and is freed with it, without a detached tail.
			body.light_node.clear()
		if body.cover_gem != null:
			var contained_gem: StaticBody3D = body.cover_gem.get_ref()
			if is_instance_valid(contained_gem) and contained_gem.is_embedded:
				# Emerge through the freshly struck opening, including side/back hits.
				var exit_point: Vector3 = point - camera.project_ray_normal(screen_position) * (contained_gem.bound_radius + 0.16)
				if contained_gem.release_from_chunk(self, to_local(exit_point)):
					auto_collected = _collect_gem(contained_gem, exit_point)
		# The discovery recording includes its own contact. Ordinary fractures,
		# or a failed gem release, still receive the stone destruction sound.
		if not auto_collected:
			audio.play_break(layer)
		var fracture_started := Time.get_ticks_usec() if capture_mode else 0
		var fragments: Array[Dictionary] = body.build_fracture_fragments()
		effects.shed_fragments(fragments, body.mesh_instance.material_override, placement, normal, point)
		if capture_mode:
			print("FRACTURE_CAPTURE pieces=", fragments.size(), " build_and_spawn_ms=", float(Time.get_ticks_usec() - fracture_started) / 1000.0)
			capture_fracture_center = placement * body.face_center
			if body == capture_plain:
				capture_plain_count = fragments.size()
				_capture_fracture_motion("fracture_plain")
			elif capture_stage == 4:
				capture_fracture_count = fragments.size()
				_capture_fracture_motion("fracture_gem")
		chunks.erase(body)
		body.queue_free()
		broken_count += 1
		_check_exhausted()
	camera_shake = maxf(camera_shake, 0.075 if broken else 0.035)
	hit_stop = 0.055 if broken else 0.025
	squash = 0.045 if broken else 0.022
	wobble_velocity += Vector3(normal.y * 0.8, -normal.x * 0.7, -normal.x * 0.6) + Vector3(0.3, 0.1, -0.12)
	if controller_id >= 0 and using_controller and not auto_collected:
		Input.start_joy_vibration(controller_id, 0.28 if broken else 0.1, 0.52 if broken else 0.25, 0.10 if broken else 0.055)
	return true

func _collect_gem(jewel: StaticBody3D, discovery_position: Vector3 = Vector3.INF) -> bool:
	if not gems.has(jewel) or not jewel.begin_collection():
		return false
	var special: bool = jewel.grade == Gem.SPECIAL
	var location := jewel.global_position
	gems.erase(jewel)
	gems_collected_this_rock += 1
	collected_count += 1
	if special:
		special_collected_count += 1
	audio.play_discovery(special, jewel.variant)
	effects.gem_burst(discovery_position if discovery_position.is_finite() else location, special, jewel.light_tier)
	camera_shake = 0.10 if special else 0.045
	if jewel.get_parent() != self:
		jewel.reparent(self)
	collecting_gems.append({"node": jewel, "start": jewel.position, "age": 0.0, "life": 1.65 if special else 1.15, "special": special, "emerging": jewel.is_emerging})
	hovered = null
	if controller_id >= 0 and using_controller:
		Input.start_joy_vibration(controller_id, 0.45 if special else 0.2, 0.65 if special else 0.35, 0.18 if special else 0.10)
	_check_exhausted()
	return true

func _update_collections(delta: float) -> void:
	for i in range(collecting_gems.size() - 1, -1, -1):
		var extraction: Dictionary = collecting_gems[i]
		var jewel: StaticBody3D = extraction.node
		# The award has already happened. Let the presentation finish before
		# moving this non-interactive visual into its collection flight.
		if jewel.is_emerging:
			continue
		if extraction.emerging:
			extraction.emerging = false
			extraction.start = jewel.position
		extraction.age += delta
		if extraction.age >= extraction.life:
			jewel.queue_free()
			collecting_gems.remove_at(i)
			continue
		var age: float = extraction.age
		var approach := smoothstep(0.0, 0.24, age)
		jewel.position = extraction.start + camera.global_basis.z * approach * 2.2 + Vector3.UP * age * 1.1
		jewel.rotation.y += delta * 2.4
		var grow := 1.0 + sin(minf(age / 0.45, 1.0) * PI) * 0.35
		var shrink := 1.0 - smoothstep(extraction.life - 0.35, extraction.life, age)
		jewel.scale = Vector3.ONE * maxf(0.001, grow * shrink)

func _check_exhausted() -> void:
	# A find never removes unmined stone. Both excavation and collection must finish.
	if completion_time < 0.0 and chunks.is_empty() and gems.is_empty():
		completion_time = 0.0
		marker.hide()

func _reset_rock() -> void:
	_spawn_rock()

func _capture_tick(delta: float) -> void:
	# Move between three parts of one cap while demonstrating all six colors.
	capture_clock += delta
	idle_time = 0.0
	if capture_stage == 0 and capture_clock > 1.1:
		_capture("lights_00_intact")
		capture_gem = gems[5]
		if not capture_gem.is_embedded or capture_gem.visible or capture_gem.collision_layer != 0 or capture_gem.get_parent() != showcase_covers[5].mesh_instance:
			push_error("Capture gem must start sealed inside its owning stone")
			get_tree().quit(1)
			return
		capture_stage = 1
		capture_clock = 0.0
	elif capture_stage == 1 and capture_clock > 0.60:
		var cap: StaticBody3D = showcase_covers[5]
		if cap.impact_count >= 1 and cap.impact_count <= 3:
			_capture("impacts_%02d_settled_cracks" % cap.impact_count)
		aim_position = _capture_cap_target(cap)
		_request_swing()
		capture_stage = 2
		capture_clock = 0.0
	elif capture_stage == 2 and capture_clock > 0.30:
		var cap: StaticBody3D = showcase_covers[5]
		var tier: int = cap.get_revealed_tier()
		if cap.impact_count >= 1 and cap.impact_count <= 3:
			_capture("impacts_%02d_light" % cap.impact_count)
			capture_impact_points.append(cap.latest_impact_local)
		if tier > capture_saved_tier:
			_capture("lights_%02d_%s" % [tier + 1, Gem.LIGHT_NAMES[tier]])
			capture_saved_tier = tier
		capture_stage = 3 if cap.health <= 1.0 else 1
		capture_clock = 0.0
	elif capture_stage == 3 and capture_clock > 0.85:
		var cap: StaticBody3D = showcase_covers[5]
		capture_fracture_center = cap.mesh_instance.to_global(cap.face_center)
		_capture("fracture_gem_00_before")
		aim_position = _capture_cap_target(cap)
		_request_swing()
		capture_stage = 4
		capture_clock = 0.0
	elif capture_stage == 4 and capture_clock > 0.30:
		_capture("lights_07_cap_break")
		if not capture_gem.collected or capture_gem.is_embedded or capture_gem.get_parent() != self or not capture_gem.visible or gems.has(capture_gem) or special_collected_count != 1:
			push_error("Breaking the owning stone must immediately award its gem")
			get_tree().quit(1)
			return
		capture_stage = 5
		capture_clock = 0.0
	elif capture_stage == 5 and capture_clock > 0.48:
		if capture_gem.is_emerging or capture_gem.collision_layer != 0 or not capture_gem.collected:
			push_error("The automatically acquired gem must remain non-interactive during its presentation")
			get_tree().quit(1)
			return
		aim_position = camera.unproject_position(capture_gem.global_position)
		_capture("lights_08_auto_acquired")
		capture_stage = 7
		capture_clock = 0.0
	elif capture_stage == 7 and capture_clock > 0.50:
		_capture("lights_09_collection")
		capture_stage = 8
		capture_clock = 0.0
	elif capture_stage == 8 and capture_clock > 1.8:
		capture_plain = _capture_plain_target()
		if capture_plain == null:
			push_error("No ordinary front stone for fracture capture")
			get_tree().quit(1)
			return
		capture_stage = 11
		capture_clock = 0.0
	elif capture_stage == 9 and capture_clock > 0.75:
		_capture("lights_10_portrait")
		capture_stage = 10
		capture_clock = 0.0
	elif capture_stage == 10 and capture_clock > 0.25:
		var observed: Array[int] = []
		for tier in light_pulse_history:
			if not observed.has(tier):
				observed.append(tier)
		var sealed_gems := 0
		for jewel in gems:
			if jewel.is_embedded:
				sealed_gems += 1
		if observed != [0, 1, 2, 3, 4, 5] or special_collected_count != 1 or sealed_gems != 5:
			push_error("Light capture did not demonstrate all six tiers and extraction: " + str(observed))
			get_tree().quit(1)
			return
		if capture_impact_points.size() != 3 or capture_impact_points[0].distance_to(capture_impact_points[1]) < 0.15 or capture_impact_points[1].distance_to(capture_impact_points[2]) < 0.15 or capture_impact_points[0].distance_to(capture_impact_points[2]) < 0.15:
			push_error("Impact capture did not strike three distinct positions: " + str(capture_impact_points))
			get_tree().quit(1)
			return
		if capture_fracture_count < 2 or capture_plain_count < 2:
			push_error("Both ordinary and gem stones must separate into multiple crack fragments")
			get_tree().quit(1)
			return
		print("LIGHT_CAPTURE_OK tiers=", observed, " hits=", hit_count, " gems=", collected_count, " still_embedded=", sealed_gems, " impact_positions=", capture_impact_points, " fragments_gem/plain=", capture_fracture_count, "/", capture_plain_count)
		get_tree().quit()
	elif capture_stage == 11 and capture_clock > 0.60:
		capture_fracture_center = capture_plain.mesh_instance.to_global(capture_plain.face_center)
		if capture_plain.health <= 1.0:
			_capture("fracture_plain_00_before")
		aim_position = _capture_cap_target(capture_plain)
		_request_swing()
		capture_stage = 12
		capture_clock = 0.0
	elif capture_stage == 12 and capture_clock > 0.40:
		capture_stage = 11 if is_instance_valid(capture_plain) else 13
		capture_clock = 0.0
	elif capture_stage == 13 and capture_clock > 1.0:
		get_window().size = Vector2i(600, 900)
		capture_stage = 9
		capture_clock = 0.0
	if elapsed > 65.0:
		push_error("Light capture timed out")
		get_tree().quit(1)

func _capture_plain_target() -> StaticBody3D:
	var best: StaticBody3D
	var best_distance := INF
	var center := get_viewport().get_visible_rect().size * 0.5
	for chunk in chunks:
		if chunk.is_gem_cover or chunk.layer_index != 0 or chunk.health < 3.0:
			continue
		var screen := camera.unproject_position(chunk.mesh_instance.to_global(chunk.face_center))
		if ray_at(screen).get("collider") != chunk:
			continue
		var distance := screen.distance_squared_to(center)
		if distance < best_distance:
			best = chunk
			best_distance = distance
	return best

func _capture_fracture_motion(prefix: String) -> void:
	await get_tree().create_timer(0.04).timeout
	_capture(prefix + "_01_opening")
	await get_tree().create_timer(0.10).timeout
	_capture(prefix + "_02_separating")
	await get_tree().create_timer(0.22).timeout
	_capture(prefix + "_03_falling")

func _capture_cap_target(cap: StaticBody3D) -> Vector2:
	var edge := int(float(cap.impact_count % 3) * float(cap.face_points.size()) / 3.0)
	var edge_midpoint: Vector3 = (cap.face_points[edge] + cap.face_points[(edge + 1) % cap.face_points.size()]) * 0.5
	var target: Vector3 = cap.face_center.lerp(edge_midpoint, 0.52)
	return camera.unproject_position(cap.mesh_instance.to_global(target))

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png("res://artifacts/" + label + ".png")
	var light_tier_shot := label.begins_with("lights_") and label.get_slice("_", 1).to_int() >= 1 and label.get_slice("_", 1).to_int() <= 6
	if label.begins_with("impacts_") or light_tier_shot:
		var cap: StaticBody3D = showcase_covers[5]
		var center := camera.unproject_position(cap.mesh_instance.to_global(cap.face_center))
		var pixel_scale := Vector2(screenshot.get_size()) / get_viewport().get_visible_rect().size
		var detail_size := Vector2i(680, 560) if light_tier_shot else Vector2i(400, 360)
		var region := Rect2i(Vector2i(center * pixel_scale) - detail_size / 2, detail_size)
		region = region.intersection(Rect2i(Vector2i.ZERO, screenshot.get_size()))
		screenshot.get_region(region).save_png("res://artifacts/" + label + "_detail.png")
	elif label.begins_with("fracture_"):
		var center := camera.unproject_position(capture_fracture_center)
		var pixel_scale := Vector2(screenshot.get_size()) / get_viewport().get_visible_rect().size
		var region := Rect2i(Vector2i(center * pixel_scale) - Vector2i(230, 200), Vector2i(460, 400))
		region = region.intersection(Rect2i(Vector2i.ZERO, screenshot.get_size()))
		screenshot.get_region(region).save_png("res://artifacts/" + label + "_detail.png")
