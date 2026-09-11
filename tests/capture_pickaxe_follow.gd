extends SceneTree
## Real Main cursor input and swing signal routing, driven at exact capture times.
const Pickaxe = preload("res://scripts/pickaxe.gd")

class CaptureGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var game: CaptureGame
var finished := false
var screenshots: Array[Dictionary] = []
var start_hits := 0
var pressed_screen := Vector2.ZERO
var strike_screen := Vector2.ZERO
var strike_world := Vector3.ZERO

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func():
		if not finished:
			_fail("Capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	game = CaptureGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.hud._process(0.5)
	await physics_frame
	await create_timer(0.25).timeout
	var view := game.get_viewport().get_visible_rect().size
	_move_cursor(view * Vector2(0.31, 0.43))
	await _save("pickaxe_follow_left")
	_move_cursor(view * Vector2(0.50, 0.45))
	await _save("pickaxe_follow_center")
	_move_cursor(view * Vector2(0.68, 0.37))
	await _save("pickaxe_follow_right")
	strike_screen = _front_target()
	if strike_screen == Vector2.INF:
		_fail("No real visible stone for the cursor swing")
		return
	_move_cursor(strike_screen)
	pressed_screen = strike_screen
	var ray: Dictionary = game.ray_at(strike_screen)
	strike_world = ray.position
	start_hits = game.hit_count
	game._request_swing()
	if not game.pickaxe.is_swinging:
		_fail("Main rejected the valid cursor swing")
		return
	_step(Pickaxe.STRIKE_TIME * 0.45)
	await _save("pickaxe_follow_windup")
	# Move during wind-up: the real strike must follow the latest cursor target.
	_move_cursor(view * Vector2(0.36, 0.35))
	strike_screen = game.aim_position
	var moved_ray: Dictionary = game.ray_at(strike_screen)
	if moved_ray.is_empty():
		_fail("Moved wind-up cursor must still point at a real stone")
		return
	strike_world = moved_ray.position
	_step(Pickaxe.STRIKE_TIME * 0.40)
	await _save("pickaxe_follow_windup_moved")
	_step(Pickaxe.STRIKE_TIME * 0.15 + 0.001)
	if game.hit_count != start_hits + 1:
		_fail("Crossing the strike time must route exactly one real Main hit")
		return
	await _save("pickaxe_follow_impact")
	_move_cursor(view * Vector2(0.67, 0.42))
	_step((Pickaxe.SWING_DURATION - Pickaxe.STRIKE_TIME) * 0.52)
	await _save("pickaxe_follow_recovery_moved")
	_step(Pickaxe.SWING_DURATION)
	if game.pickaxe.is_swinging or game.hit_count != start_hits + 1:
		_fail("Recovery must finish without an extra mining impact")
		return
	await _save("pickaxe_follow_recovered")
	# Preserve production expand stretch; this is a physical window resize only.
	root.size = Vector2i(600, 1000)
	await process_frame
	game._resize()
	view = game.get_viewport().get_visible_rect().size
	_move_cursor(view * Vector2(0.30, 0.44))
	await _save("pickaxe_follow_portrait_left")
	_move_cursor(view * Vector2(0.69, 0.43))
	await _save("pickaxe_follow_portrait_right")
	strike_screen = _front_target()
	if strike_screen == Vector2.INF:
		_fail("No real visible portrait stone")
		return
	_move_cursor(strike_screen)
	pressed_screen = strike_screen
	strike_world = game.ray_at(strike_screen).position
	game._request_swing()
	_step(Pickaxe.STRIKE_TIME + 0.001)
	if game.hit_count != start_hits + 2:
		_fail("Portrait swing did not route the second real hit")
		return
	await _save("pickaxe_follow_portrait_impact")
	_step(Pickaxe.SWING_DURATION)
	var report := {"seed": game.rock_seed, "round_enabled": game.round_enabled, "strike_time": Pickaxe.STRIKE_TIME, "swing_duration": Pickaxe.SWING_DURATION, "real_hits": game.hit_count - start_hits, "snapshots": screenshots}
	var file := FileAccess.open("res://artifacts/pickaxe_follow_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	finished = true
	print("PICKAXE_FOLLOW_CAPTURE_OK files=", screenshots.size(), " actual_hits=", game.hit_count - start_hits, " swing_duration=", Pickaxe.SWING_DURATION)
	# Captures exit immediately after impact; let the audio mixer release that
	# still-playing reference sample instead of exiting while it owns the stream.
	for voice in game.audio._players:
		voice.stop()
		voice.stream = null
	game.reward_audio.stop_all()
	game.queue_free()
	await process_frame
	await process_frame
	var release_deadline := Time.get_ticks_usec() + 30000
	while Time.get_ticks_usec() < release_deadline:
		await process_frame
	quit()

func _move_cursor(screen: Vector2) -> void:
	game.focused = true
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.relative = screen - game.aim_position
	game._input(motion)
	game._process(0.0)
	game.pickaxe._process(0.0)
	game._physics_process(0.0)
	game.hud._process(0.0)

func _step(duration: float) -> void:
	# Small stable Main steps preserve the actual recoil springs and aim plumbing.
	var remaining := duration
	while remaining > 0.000001:
		var delta := minf(remaining, 1.0 / 240.0)
		game.focused = true
		game._process(delta)
		game.pickaxe._process(delta)
		game._physics_process(delta)
		game.hud._process(delta)
		remaining -= delta

func _front_target() -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	var screen_center := game.get_viewport().get_visible_rect().size * Vector2(0.50, 0.44)
	for chunk in game.chunks:
		if chunk.is_gem_cover or chunk.destroyed:
			continue
		var screen: Vector2 = game.camera.unproject_position(chunk.mesh_instance.to_global(chunk.face_center))
		if game.ray_at(screen).get("collider") != chunk or game.hud.is_pointer_blocked(screen):
			continue
		var distance := screen.distance_squared_to(screen_center)
		if distance < best_distance:
			best_distance = distance
			best = screen
	return best

func _save(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := "res://artifacts/" + label + ".png"
	if picture.save_png(ProjectSettings.globalize_path(path)) != OK:
		_fail("Cannot save " + label)
		return
	var tip: Vector3 = game.pickaxe.to_global(Pickaxe.PICK_TIP)
	var projected_tip: Vector2 = game.camera.unproject_position(tip)
	var logical_size := game.get_viewport().get_visible_rect().size
	screenshots.append({"file": path, "aim": _v2(game.aim_position), "pending_aim": _v2(game.pending_aim), "pressed_screen": _v2(pressed_screen), "tip_screen": _v2(projected_tip), "tip_world": _v3(tip), "tool_position": _v3(game.pickaxe.position), "tool_rotation": _v3(game.pickaxe.rotation), "tool_scale": _v3(game.pickaxe.scale), "swing_elapsed": game.pickaxe._elapsed, "swinging": game.pickaxe.is_swinging, "hit_count": game.hit_count, "strike_screen": _v2(strike_screen), "strike_world": _v3(strike_world), "physical_size": [picture.get_width(), picture.get_height()], "logical_size": _v2(logical_size)})

func _v2(value: Vector2) -> Array:
	return [value.x, value.y]

func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _fail(message: String) -> void:
	finished = true
	push_error("PICKAXE_FOLLOW_CAPTURE_FAILED: " + message)
	quit(1)
