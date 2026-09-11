extends SceneTree
## Run with Godot --headless --path . --script res://tests/validate_mining.gd.
## Exercises the playable scene through real physics queries and input dispatch.

const Main = preload("res://scripts/main.gd")
const Gem = preload("res://scripts/gem.gd")

var game: Main
var failures: Array[String] = []
var checks := 0
var impact_signal_count := 0
var impact_was_deferred := false
var hit_count_at_signal := -1


func _initialize() -> void:
	_run.call_deferred()
	create_timer(35.0).timeout.connect(func():
		push_error("MINING_TEST_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.size = Vector2i(1440, 1000)
	game = load("res://scenes/main.tscn").instantiate() as Main
	root.add_child(game)
	await _frames(4)
	_check(game.chunks.size() == 92, "A fresh rock has 92 independently mineable chunks")
	var layer_counts := [0, 0, 0]
	var all_solid := true
	for chunk in game.chunks:
		layer_counts[chunk.layer_index] += 1
		all_solid = all_solid and chunk.collision_layer == 1 and chunk.health > 0.0
	_check(layer_counts[0] > 0 and layer_counts[1] > 0 and layer_counts[2] > 0, "All three shells contain solid chunks")
	_check(all_solid and game.gem.collision_layer == 2, "Stone and gem use separate selectable collision layers")
	var center := _center()
	var first_ray := game.ray_at(center)
	_check(not first_ray.is_empty(), "The screen center intersects the rock")
	if first_ray.is_empty():
		_finish()
		return
	var first: StaticBody3D = first_ray.collider
	_check(first != game.gem and first.layer_index == 0, "The outer shell blocks the central gem")
	var stone_ray := _masked_ray(center, 1)
	var gem_ray := _masked_ray(center, 2)
	_check(not stone_ray.is_empty() and stone_ray.collider == first, "Stone-only physics query reaches the visible outer chunk")
	_check(not gem_ray.is_empty() and gem_ray.collider == game.gem, "Gem-only query confirms the gem is physically inside the shells")
	if not gem_ray.is_empty():
		_check(game.camera.global_position.distance_to(first_ray.position) < game.camera.global_position.distance_to(gem_ray.position), "The gem is farther away than its blocking shell")
	game.pickaxe.impacted.connect(_on_impact)
	var initial_health: float = first.health
	var initial_hits := game.hit_count
	_send_mouse_button(MOUSE_BUTTON_LEFT, true, center)
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, center)
	_check(game.pickaxe.is_swinging and game.hit_count == initial_hits, "Mouse press begins a swing without applying damage during input")
	_check(await _until(func(): return game.hit_count > initial_hits), "Mouse swing delivers a physics impact")
	_check(impact_signal_count > 0 and impact_was_deferred and hit_count_at_signal == initial_hits, "Pickaxe impact queues damage until the physics callback")
	_check(is_instance_valid(first) and first.health < initial_health and first.health > 0.0, "The first impact damages the outer chunk without detaching it")
	if is_instance_valid(first):
		var crack_mesh: MeshInstance3D = first.get("_crack_mesh")
		_check(crack_mesh != null and crack_mesh.mesh != null and crack_mesh.mesh.get_surface_count() > 0, "Damage creates visible crack geometry")
	await _settle_swing()

	var traversed: Array[int] = [0]
	var detached := 0
	var attempts := 0
	while game.reveal_time < 0.0 and attempts < 100:
		center = _center()
		var ray := game.ray_at(center)
		if ray.is_empty():
			await _frames(2)
			attempts += 1
			continue
		var body: StaticBody3D = ray.collider
		var body_is_gem := body == game.gem
		if body_is_gem:
			# Keep a real mouse press held from extraction through the next rock.
			_send_mouse_button(MOUSE_BUTTON_LEFT, true, center)
			_check(await _until(func(): return game.reveal_time >= 0.0), "A held mouse strike extracts the exposed gem")
			break
		if not body_is_gem and not traversed.has(body.layer_index):
			traversed.append(body.layer_index)
		var count_before := game.chunks.size()
		_check(game._mine_at(center), "The central mining ray hits a selectable body")
		if not body_is_gem and game.chunks.size() < count_before:
			detached += 1
			_check(body.collision_layer == 0 and body.destroyed, "A broken chunk stops blocking rays immediately")
			await _frames(2)
			_check(not is_instance_valid(body), "A detached chunk's physics body is freed")
		else:
			await _frames(2)
		attempts += 1
	_check(traversed == [0, 1, 2], "Central drilling must traverse outer, middle, and inner shells in order")
	_check(detached >= 3, "Drilling detaches at least one chunk from each shell")
	_check(game.reveal_time >= 0.0 and game.collected_count == 1, "Reaching and striking the gem collects it once")
	if game.reveal_time < 0.0:
		_finish()
		return
	_check(game.chunks.is_empty(), "Gem reveal clears remaining mineable stone")
	_check(game.mouse_down, "A held mouse remains held through gem extraction")
	_check(game.gem.collision_layer == 0 and game.gem.get_parent() == game.rock_motion, "Extracted gem is displayed independently and cannot be collected again")
	_check(not game._mine_at(_center()) and game.collected_count == 1, "Additional reveal-time strikes cannot award duplicate gems")
	await _frames(2)
	_check(game.ray_at(_center()).is_empty(), "Destroyed shells and the collected gem leave no selectable collision")
	var previous_gem: WeakRef = weakref(game.gem)
	var previous_rock_number := game.rock_number
	var hits_at_reveal := game.hit_count
	_check(await _until(func(): return game.rock_number > previous_rock_number, 3.8), "A fresh rock appears after the reveal finishes")
	await _frames(4)
	_check(previous_gem.get_ref() == null, "Respawn frees the previously extracted gem")
	_check(_count_gems(game) == 1, "Exactly one gem exists after respawn")
	_check(game.chunks.size() == 92 and game.reveal_time < 0.0 and game.collected_count == 1, "Respawn restores full stone layers while retaining the collection count")
	_check(await _until(func(): return game.hit_count > hits_at_reveal), "Holding the same mouse press automatically mines the fresh rock")
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, _center())
	await _settle_swing()
	var hits_after_release := game.hit_count
	await create_timer(0.42).timeout
	_check(game.hit_count == hits_after_release and not game.mouse_down, "Releasing the mouse after respawn stops repeated mining")
	await _frames(2)

	await _validate_inputs()
	_finish()


func _validate_inputs() -> void:
	var before := game.hit_count
	var center := _center()
	_send_touch(true, center)
	_send_touch(false, center)
	_check(game.hit_count == before and game.pickaxe.is_swinging, "A touch tap queues a swing without an immediate hit")
	_check(await _until(func(): return game.hit_count > before), "Touch tap mines through the same physics path")
	await _settle_swing()
	before = game.hit_count
	_send_touch(true, _center())
	_check(await _until(func(): return game.hit_count > before), "Holding a touch automatically mines")
	_send_touch(false, _center())
	await _settle_swing()
	var released_hits := game.hit_count
	await create_timer(0.38).timeout
	_check(game.hit_count == released_hits, "Releasing touch stops automatic mining")

	before = game.hit_count
	var rotation_before := game.shell.quaternion
	center = _center()
	_send_touch(true, center)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(60, 18)
	drag.relative = Vector2(60, 18)
	_send(drag)
	_check(game.touch_rotating and game.shell.quaternion.angle_to(rotation_before) > 0.05, "A touch drag rotates the stone")
	_send_touch(false, drag.position)
	await create_timer(0.20).timeout
	_check(game.hit_count == before and not game.pickaxe.is_swinging, "A rotation drag does not accidentally mine")

	# Losing focus during a touch orbit must not leave mouse/keyboard/controller blocked.
	_send_touch(true, _center())
	_send(drag)
	_check(game.touch_rotating, "A touch orbit is active before focus loss")
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_send_touch(false, drag.position)
	_check(not game.focused and game.touch_id == -1 and not game.touch_rotating, "Focus loss clears the complete touch gesture state")
	before = game.hit_count
	_send_key(KEY_SPACE, true)
	_send_key(KEY_SPACE, false)
	await create_timer(0.20).timeout
	_check(game.hit_count == before and not game.pickaxe.is_swinging, "Unfocused input cannot begin a new mining swing")
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_send_mouse_button(MOUSE_BUTTON_LEFT, true, _center())
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, _center())
	_check(await _until(func(): return game.hit_count > before), "Mouse mining works after focus returns from an interrupted touch drag")
	await _settle_swing()

	rotation_before = game.shell.quaternion
	_send_mouse_button(MOUSE_BUTTON_RIGHT, true, center)
	var motion := InputEventMouseMotion.new()
	motion.position = center + Vector2(40, -12)
	motion.relative = Vector2(40, -12)
	_send(motion)
	_send_mouse_button(MOUSE_BUTTON_RIGHT, false, motion.position)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.05 and not game.dragging, "Mouse drag orbits and release ends dragging")
	rotation_before = game.shell.quaternion
	var pan := InputEventPanGesture.new()
	pan.position = center
	pan.delta = Vector2(2, 1)
	_send(pan)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.04, "Touchpad pan gestures orbit the stone")

	game.aim_position = _center()
	before = game.hit_count
	_send_joy_button(JOY_BUTTON_A, true)
	_send_joy_button(JOY_BUTTON_A, false)
	_check(game.using_controller and game.hit_count == before and game.pickaxe.is_swinging, "Controller face-button input queues a swing")
	_check(await _until(func(): return game.hit_count > before), "Controller button delivers a mining impact")
	await _settle_swing()
	rotation_before = game.shell.quaternion
	_send_joy_axis(JOY_AXIS_LEFT_X, 0.85)
	await create_timer(0.12).timeout
	_send_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.04, "Controller left stick orbits the stone")
	var aim_before := game.aim_position
	_send_joy_axis(JOY_AXIS_RIGHT_X, 0.85)
	await create_timer(0.12).timeout
	_send_joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check(game.aim_position.x > aim_before.x + 8.0, "Controller right stick moves the mining aim")
	game.aim_position = _center()
	before = game.hit_count
	_send_key(KEY_SPACE, true)
	_send_key(KEY_SPACE, false)
	_check(await _until(func(): return game.hit_count > before), "Keyboard space delivers a mining impact")
	await _settle_swing()
	rotation_before = game.shell.quaternion
	_send_key(KEY_A, true)
	await create_timer(0.12).timeout
	_send_key(KEY_A, false)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.04, "Keyboard direction input orbits the stone")


func _on_impact() -> void:
	impact_signal_count += 1
	impact_was_deferred = game.impact_pending
	hit_count_at_signal = game.hit_count


func _center() -> Vector2:
	return game.camera.unproject_position(Vector3.ZERO)


func _masked_ray(screen: Vector2, mask: int) -> Dictionary:
	var origin := game.camera.project_ray_origin(screen)
	var direction := game.camera.project_ray_normal(screen)
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * 40.0, mask))


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _until(predicate: Callable, timeout_seconds: float = 1.5) -> bool:
	var started := Time.get_ticks_msec()
	while not predicate.call():
		if Time.get_ticks_msec() - started > timeout_seconds * 1000.0:
			return false
		await _frames(1)
	return true


func _settle_swing() -> void:
	await _until(func(): return not game.pickaxe.is_swinging and game.swing_cooldown <= 0.0)
	await _frames(2)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _send_mouse_button(button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	_send(event)


func _send_touch(pressed: bool, position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	_send(event)


func _send_joy_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	_send(event)


func _send_joy_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	_send(event)


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	_send(event)


func _count_gems(node: Node) -> int:
	var count := 1 if node.get_script() == Gem else 0
	for child in node.get_children():
		count += _count_gems(child)
	return count


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("MINING_CHECK_FAILED: " + description)


func _finish() -> void:
	print("MINING_INTEGRATION checks=%d failures=%d hits=%d gems=%d rocks=%d" % [checks, failures.size(), game.hit_count, game.collected_count, game.rock_number])
	game.queue_free()
	quit(0 if failures.is_empty() else 1)
