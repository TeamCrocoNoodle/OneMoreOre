extends SceneTree
## Run with Godot --headless --path . --script res://tests/validate_mining.gd.
## Real raycasts verify hidden seeded gems, full excavation, and all input paths.

const Main = preload("res://scripts/main.gd")
const Gem = preload("res://scripts/gem.gd")
const TEST_SEED := 61477
const EXPECTED_CHUNKS := 322

var game: Main
var failures: Array[String] = []
var checks := 0
var impact_signal_count := 0
var impact_was_deferred := false
var hit_count_at_signal := -1
var traversed_layers: Array[int] = []
var initial_gem_count := 0
var cover_promotions := 0
var cover_exposures := 0


func _initialize() -> void:
	_run.call_deferred()
	create_timer(90.0).timeout.connect(func():
		push_error("MINING_TEST_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.size = Vector2i(1440, 1000)
	game = load("res://scenes/main.tscn").instantiate() as Main
	root.add_child(game)
	await _frames(4)
	await _validate_showcase()
	await _validate_seeded_layouts()
	initial_gem_count = game.gems.size()
	_check(game.chunks.size() == EXPECTED_CHUNKS, "A large fresh rock has 322 independently mineable chunks")
	_check(initial_gem_count > 1, "The rock contains multiple discoverable gems")
	_check(_count_gems(game) == initial_gem_count, "Seeded resets leave exactly the current gem population")
	var layer_counts := [0, 0, 0, 0, 0, 0]
	var all_solid := true
	for chunk in game.chunks:
		layer_counts[chunk.layer_index] += 1
		all_solid = all_solid and chunk.collision_layer == 1 and chunk.health > 0.0
	_check(not layer_counts.has(0) and all_solid, "All six layers contain solid, independently damageable stone")
	_validate_placement()
	var center := _center()
	var first_ray := game.ray_at(center)
	_check(not first_ray.is_empty(), "The screen center intersects the intact rock")
	if first_ray.is_empty():
		_finish()
		return
	var first: StaticBody3D = first_ray.collider
	_check(game.chunks.has(first) and first.layer_index == 0, "The outer shell blocks the initial central ray")
	var stone_ray := _masked_ray(center, 1)
	_check(not stone_ray.is_empty() and stone_ray.collider == first, "Stone-only physics query reaches the visible outer chunk")
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

	var old_gems: Array[WeakRef] = []
	for body in game.gems:
		old_gems.append(weakref(body))
	var starting_rock := game.rock_number
	var collected_before := game.collected_count
	var steps := 0
	# Deliberately find every gem before excavating the rest of the rock.
	while not game.gems.is_empty() and steps < 150:
		var target: StaticBody3D = game.gems[0]
		if not await _break_visible(game.camera.unproject_position(target.global_position)):
			break
		steps += 1
	_check(game.gems.is_empty() and game.gems_collected_this_rock == initial_gem_count, "Every randomly placed gem can be reached through ordinary mining rays")
	_check(game.collected_count == collected_before + initial_gem_count, "Each exposed gem awards exactly one collection")
	_check(cover_promotions > 0 and cover_exposures > 0, "Random excavation encounters and removes real high-health gem covers")
	_check(game.chunks.size() > 0, "Finding all gems leaves unrelated stone intact")
	if not game.gems.is_empty() or game.chunks.is_empty():
		_finish()
		return
	var remaining_stone := game.chunks.size()
	await create_timer(3.1).timeout
	await _frames(2)
	_check(game.rock_number == starting_rock and game.completion_time < 0.0, "Collecting all gems cannot respawn a partially excavated rock")
	_check(game.chunks.size() == remaining_stone, "Gem collection animations do not remove remaining stone")
	var gems_freed := true
	for previous in old_gems:
		gems_freed = gems_freed and previous.get_ref() == null
	_check(gems_freed and game.collecting_gems.is_empty() and _count_gems(game) == 0, "Collected gems and their transient animation nodes are freed")

	steps = 0
	while game.chunks.size() > 1 and steps < EXPECTED_CHUNKS * 2:
		var target: StaticBody3D = game.chunks[-1]
		if not await _break_visible(game.camera.unproject_position(target.global_position)):
			break
		steps += 1
	_check(game.chunks.size() == 1 and game.completion_time < 0.0, "Even one remaining stone chunk prevents completion")
	traversed_layers.sort()
	_check(traversed_layers == [0, 1, 2, 3, 4, 5], "Full excavation reaches every one of the six rock layers")
	if game.chunks.size() != 1:
		_finish()
		return
	var last_chunk: StaticBody3D = game.chunks[0]
	_send_mouse_button(MOUSE_BUTTON_LEFT, true, game.camera.unproject_position(last_chunk.global_position))
	_check(await _until(func(): return game.completion_time >= 0.0, 5.0), "A real held mouse press breaks the final chunk and completes excavation")
	_check(game.chunks.is_empty() and game.gems.is_empty(), "Completion requires both all stone and all gems to be cleared")
	_check(game.mouse_down, "The final mining press remains held through completion")
	var hits_at_completion := game.hit_count
	var completed_rock := game.rock_number
	_check(await _until(func(): return game.rock_number > completed_rock, 5.0), "Only full excavation starts the next rock")
	await _frames(4)
	_check(game.chunks.size() == EXPECTED_CHUNKS and game.gems.size() == initial_gem_count, "Respawn restores the complete rock and a fresh gem population")
	_check(_count_gems(game) == initial_gem_count and game.collecting_gems.is_empty(), "Respawn contains no previous gem or collection nodes")
	_check(game.gems_collected_this_rock == 0 and game.collected_count == collected_before + initial_gem_count, "Respawn resets per-rock progress while retaining the lifetime count")
	_check(await _until(func(): return game.hit_count > hits_at_completion), "Holding the same mouse press automatically mines the fresh rock")
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, _center())
	await _settle_swing()
	var hits_after_release := game.hit_count
	await create_timer(0.42).timeout
	_check(game.hit_count == hits_after_release and not game.mouse_down, "Releasing the mouse after respawn stops repeated mining")
	await _validate_inputs()
	_finish()


func _validate_showcase() -> void:
	game._spawn_rock(12873, true)
	await create_timer(0.75).timeout
	await _frames(2)
	_check(game.showcase_mode and game.showcase_covers.size() == game.gems.size(), "The first-rock showcase provides one stone cap for each gem")
	var preview_lights: Array[WeakRef] = []
	var tiers: Array[int] = []
	for cap in game.showcase_covers:
		var jewel: StaticBody3D = cap.cover_gem.get_ref()
		var screen: Vector2 = game.camera.unproject_position(jewel.global_position)
		var visible := game.ray_at(screen)
		var behind := _ray_without(screen, cap)
		_check(not visible.is_empty() and visible.collider == cap, "Every showcase gem is initially hidden by its selected front cap")
		_check(not behind.is_empty() and behind.collider == jewel, "Excluding a showcase cap exposes its gem rather than another stone")
		_check(cap.health == 16.0 and cap.max_health == 16.0, "Showcase caps have their high health before any hit")
		_check(not cap.light_node.visible and cap.light_node.pulse_count == 0, "Unstruck showcase caps give away no beam color")
		tiers.append(jewel.light_tier)
		preview_lights.append(weakref(cap.light_node))
	tiers.sort()
	_check(tiers == [0, 1, 2, 3, 4, 5], "All six final light colors are available on the first rock")
	var final_cap: StaticBody3D = game.showcase_covers[-1]
	var final_gem: StaticBody3D = final_cap.cover_gem.get_ref()
	var departing: WeakRef = weakref(final_cap.light_node)
	_check(await _break_visible(game.camera.unproject_position(final_gem.global_position)), "A showcase cap is removable through the normal mining path")
	_check(departing.get_ref() != null and departing.get_ref().get_parent() == game.effects, "The cover's final light flash survives its stone detachment")
	game._spawn_rock(TEST_SEED, false)
	await _frames(3)
	var all_lights_freed := true
	for previous in preview_lights:
		all_lights_freed = all_lights_freed and previous.get_ref() == null
	_check(all_lights_freed, "Reset clears both attached and detached lights from the previous rock")


func _validate_seeded_layouts() -> void:
	game._spawn_rock(TEST_SEED)
	await create_timer(0.75).timeout
	await _frames(2)
	var first := _layout_snapshot()
	_validate_placement()
	game._spawn_rock(TEST_SEED + 1)
	await create_timer(0.75).timeout
	await _frames(2)
	var different := _layout_snapshot()
	_check(first != different, "Different rock seeds change internal gem locations")
	_validate_placement()
	game._spawn_rock(TEST_SEED)
	await create_timer(0.75).timeout
	await _frames(2)
	_check(_layout_snapshot() == first, "Repeating a seed exactly reproduces its gem layout")


func _layout_snapshot() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for body in game.gems:
		positions.append(body.position)
	return positions


func _validate_placement() -> void:
	var positions: Array[Vector3] = []
	var bounds: Array[float] = []
	var inside := true
	var fully_covered := true
	var separated := true
	var off_center := true
	var correct_layers := true
	var common_count := 0
	var special_count := 0
	var leak_count := 0
	var ray_count := 0
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for i in range(24):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 24.0
		var angle := float(i) * 2.3999632297
		directions.append(Vector3(cos(angle) * sqrt(1.0 - y * y), y, sin(angle) * sqrt(1.0 - y * y)))
	for body in game.gems:
		if body.grade == Gem.COMMON:
			common_count += 1
		elif body.grade == Gem.SPECIAL:
			special_count += 1
		var center: Vector3 = game.shell.to_local(body.global_position)
		var points := _gem_hull_points(body)
		_check(not points.is_empty(), "Each hidden gem has an actual convex collision hull")
		if points.is_empty():
			continue
		var radius := 0.0
		var extrema: Array[Vector3] = [points[0], points[0], points[0], points[0], points[0], points[0]]
		for point in points:
			radius = maxf(radius, point.distance_to(center))
			inside = inside and point.length() < Main.ROCK_RADIUS - 0.15
			for axis in range(3):
				if point[axis] < extrema[axis * 2][axis]:
					extrema[axis * 2] = point
				if point[axis] > extrema[axis * 2 + 1][axis]:
					extrema[axis * 2 + 1] = point
		off_center = off_center and center.length() > 0.2
		fully_covered = fully_covered and center.length() + radius <= game.gem_cover_radius - 0.11
		correct_layers = correct_layers and body.collision_layer == 2
		for i in range(positions.size()):
			separated = separated and center.distance_to(positions[i]) >= radius + bounds[i] + 0.01
		positions.append(center)
		bounds.append(radius)
		extrema.append(center)
		for direction in directions:
			var origin: Vector3 = game.shell.to_global(direction * (Main.ROCK_RADIUS + 2.0))
			for point in extrema:
				var query := PhysicsRayQueryParameters3D.create(origin, game.shell.to_global(point), 3)
				var result: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
				ray_count += 1
				if result.is_empty() or not game.chunks.has(result.collider):
					leak_count += 1
	_check(inside, "Every gem hull lies safely inside the outer rock volume")
	_check(fully_covered, "Every gem's full bound stays inside the closed stone backing with clearance")
	_check(separated, "Random gem hull bounds do not overlap")
	_check(off_center, "Gem placement does not reserve the exact center")
	_check(correct_layers, "Uncollected gems use only the gem selection layer")
	_check(common_count == Main.COMMON_GEM_COUNT and special_count == Main.SPECIAL_GEM_COUNT, "Every seed creates the configured common and special gem populations")
	_check(leak_count == 0, "Fresh stone occludes all gem centers and hull extrema from %d exterior rays (leaks=%d)" % [ray_count, leak_count])


func _gem_hull_points(body: StaticBody3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			for point in child.shape.points:
				points.append(game.shell.to_local(child.to_global(point)))
	return points


func _break_visible(screen: Vector2) -> bool:
	var ray := game.ray_at(screen)
	if ray.is_empty():
		_check(false, "An excavation target must remain reachable by a physics ray")
		return false
	var body: StaticBody3D = ray.collider
	var stone := game.chunks.has(body)
	var gem := game.gems.has(body)
	_check(stone or gem, "Only remaining stone or uncollected gems can intercept mining rays")
	if not stone and not gem:
		return false
	var previous_stone := game.chunks.size()
	var previous_collected := game.collected_count
	var following := _ray_without(screen, body)
	var linked_gem: StaticBody3D = body.cover_gem.get_ref() as StaticBody3D if stone and body.cover_gem != null else null
	var originally_ordinary: bool = stone and body.max_health <= 4.0
	var previous_damage: float = maxf(body.max_health - body.health, 0.0) if stone else 0.0
	var strikes := 0
	if stone:
		if not traversed_layers.has(body.layer_index):
			traversed_layers.append(body.layer_index)
	# Designation happens on the first real strike. Read health after that hit,
	# so promoting a 2-4 HP stone to a 16 HP cover cannot fool this helper.
	while strikes < 32:
		if not game._mine_at(screen):
			_check(false, "A reachable body's mining hits must be accepted")
			return false
		strikes += 1
		if stone and strikes == 1:
			if body.is_gem_cover:
				linked_gem = body.cover_gem.get_ref() as StaticBody3D
				if originally_ordinary:
					cover_promotions += 1
					_check(body.max_health == 16.0 and body.health == 15.0 - previous_damage, "Main assigns 16 cover HP before the hit while preserving any prior damage")
					_check(not following.is_empty() and following.collider == linked_gem, "A promoted cover is the final physical obstruction before its linked gem")
					_check(body.get_revealed_tier() == 0 and body.light_node.current_tier == 0, "A newly identified cover starts with white light")
			elif originally_ordinary:
				_check(body.max_health >= 2.0 and body.max_health <= 4.0 and not is_instance_valid(body.light_node), "Ordinary overlying blockers stay soft and do not emit gem beams")
		if not stone or body.destroyed:
			break
	if stone:
		_check(body.collision_layer == 0 and body.destroyed and game.chunks.size() == previous_stone - 1, "Breaking one chunk disables its collision and removes exactly that chunk")
		if is_instance_valid(linked_gem) and not following.is_empty() and following.collider == linked_gem:
			var exposed := game.ray_at(screen)
			_check(not exposed.is_empty() and exposed.collider == linked_gem, "Removing the final cover immediately exposes its gem to the same mining ray")
			cover_exposures += 1
		await _frames(1)
		_check(not is_instance_valid(body), "A detached chunk's physics body is freed")
	else:
		_check(game.chunks.size() == previous_stone, "Collecting a gem preserves every remaining stone chunk")
		_check(body.collision_layer == 0 and not game.gems.has(body) and game.collected_count == previous_collected + 1, "Collected gem is removed from selection and awarded exactly once")
		var stale_links := false
		for remaining in game.chunks:
			if remaining.cover_gem != null and remaining.cover_gem.get_ref() == body:
				stale_links = true
		_check(not stale_links, "Collection releases every surviving cover linked to the gem")
		await _frames(1)
	return true


func _ray_without(screen: Vector2, excluded: StaticBody3D) -> Dictionary:
	var origin := game.camera.project_ray_origin(screen)
	var direction := game.camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 40.0, 3)
	query.exclude = [excluded.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_ray(query)


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
	_cleanup_and_quit.call_deferred(0 if failures.is_empty() else 1)


func _cleanup_and_quit(exit_code: int) -> void:
	# Let the last audio mix and queued node deletion finish before process exit.
	# Immediate quit can retain the final WAV/playback pair in the audio thread.
	for voice in game.audio.get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
			voice.stream = null
	game.queue_free()
	await _frames(8)
	game = null
	quit(exit_code)
