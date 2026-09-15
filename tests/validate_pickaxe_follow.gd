extends SceneTree
## Project the real tool through real cameras, including an in-progress swing.
const Pickaxe = preload("res://scripts/pickaxe.gd")
const Main = preload("res://scripts/main.gd")

var checks := 0
var failures: Array[String] = []
var game: Node3D
var impact_count := 0
var start_count := 0


func _initialize() -> void:
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func():
		push_error("PICKAXE_FOLLOW_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	await _validate_camera_motion()
	await _validate_main_impacts()
	if is_instance_valid(game):
		_stop_audio(game)
		game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PICKAXE_FOLLOW checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _validate_camera_motion() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 1000)
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0.8, 2.5, 10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var pick := Pickaxe.new()
	pick.setup(camera)
	pick.set_process(false)
	pick.impacted.connect(func(): impact_count += 1)
	pick.swing_started.connect(func(): start_count += 1)
	for dimensions: Vector2i in [Vector2i(1440, 1000), Vector2i(360, 800), Vector2i(1600, 900)]:
		viewport.size = dimensions
		for keep_aspect in [Camera3D.KEEP_HEIGHT, Camera3D.KEEP_WIDTH]:
			camera.keep_aspect = keep_aspect
			await process_frame
			var a := Vector2(dimensions) * Vector2(0.30, 0.42)
			# Both axes now turn the pose. Returning to an earlier target must
			# restore the same pose at unchanged animation time, without drift.
			var b := Vector2(dimensions) * Vector2(0.57, 0.30)
			var c := Vector2(dimensions) * Vector2(0.72, 0.62)
			pick.set_target(a)
			pick._process(0.0)
			var idle_a := pick.transform
			pick.set_target(b)
			pick._process(0.0)
			_check(not pick.transform.is_equal_approx(idle_a), "Idle tool follows the moved cursor at %s / aspect %d" % [dimensions, keep_aspect])
			pick.set_target(a)
			pick._process(0.0)
			_check(pick.transform.is_equal_approx(idle_a), "Returning the cursor restores the idle pose immediately")
			var impacts_before := impact_count
			var starts_before := start_count
			pick.set_target(a)
			pick.set_contact_point(camera.project_position(a, 9.3))
			pick.swing()
			pick.swing()
			_check(start_count == starts_before + 1 and pick.is_swinging, "An active swing rejects a duplicate start")
			var time := 0.0
			for phase: float in [0.04, 0.09, Pickaxe.STRIKE_TIME, 0.24]:
				pick.set_target(a)
				pick.set_contact_point(camera.project_position(a, 9.3))
				pick._process(phase - time)
				time = phase
				var pose_a := pick.transform
				pick.set_target(b)
				pick.set_contact_point(camera.project_position(b, 9.3))
				pick._process(0.0)
				_check(not pick.transform.is_equal_approx(pose_a) and is_equal_approx(pick._elapsed, phase), "Wind-up, strike and recoil follow a newly moved cursor without restarting")
				pick.set_target(a)
				pick.set_contact_point(camera.project_position(a, 9.3))
				pick._process(0.0)
				_check(pick.transform.is_equal_approx(pose_a), "Aim changes during a swing cannot accumulate rotation or position drift")
				pick.set_target(b)
				pick.set_contact_point(camera.project_position(b, 9.3))
				pick._process(0.0)
				if is_equal_approx(phase, Pickaxe.STRIKE_TIME):
					var tip := camera.unproject_position(pick.to_global(Pickaxe.PICK_TIP))
					_check(tip.distance_to(b) < 0.2, "The rendered pick tip reaches the latest cursor at the exact strike pose")
			pick.set_target(c)
			pick.set_contact_point(camera.project_position(c, 9.3))
			pick._process(Pickaxe.SWING_DURATION - time + 0.01)
			pick._process(0.1)
			_check(impact_count == impacts_before + 1 and not pick.is_swinging, "A complete moving swing emits exactly one impact")
			var final_c := pick.transform
			pick.set_target(a)
			pick._process(0.0)
			_check(not pick.transform.is_equal_approx(final_c), "Recovery returns to the current cursor's idle pose")
			pick.set_target(c)
			pick._process(0.0)
			_check(pick.transform.is_equal_approx(final_c), "Recovered pose stays attached to its target without drift")
	# A large frame delta still crosses the strike exactly once.
	var impacts_before := impact_count
	pick.swing()
	pick._process(0.8)
	pick._process(0.8)
	_check(impact_count == impacts_before + 1, "A frame that crosses the entire swing still emits one impact")
	viewport.queue_free()
	await process_frame


func _validate_main_impacts() -> void:
	game = Main.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game._spawn_rock(61477)
	if game.spawn_tween != null:
		game.spawn_tween.kill()
	game.spawn_time = 1.0
	game.rock_motion.scale = Vector3.ONE
	_check(is_equal_approx(game.pickaxe._ore_radius, game.active_rock_radius), "Facing uses the actual ore radius after spawning")
	await physics_frame
	await process_frame
	var targets := _visible_targets()
	_check(targets.size() >= 2, "Two distinct real stones are visible outside the HUD")
	if targets.size() < 2:
		return
	var first: Dictionary = targets[0]
	var second: Dictionary = targets[1]
	var first_health := float(first.body.health)
	var second_health := float(second.body.health)
	var hits_before := int(game.hit_count)
	game.aim_position = first.screen
	game._request_swing()
	game._process(0.04)
	game.pickaxe._process(0.04)
	var motion := InputEventMouseMotion.new()
	motion.position = second.screen
	motion.relative = Vector2(second.screen) - Vector2(first.screen)
	game._input(motion)
	game._process(0.0)
	game.pickaxe._process(Pickaxe.STRIKE_TIME - 0.04)
	var actual_tip: Vector2 = game.camera.unproject_position(game.pickaxe.to_global(Pickaxe.PICK_TIP))
	_check(actual_tip.distance_to(second.screen) < 0.3, "Main updates the animated contact point to the latest mouse position during wind-up")
	game._physics_process(0.0)
	_check(game.hit_count == hits_before + 1 and first.body.health == first_health and second.body.health == second_health - 1.0, "The strike mines the stone currently under the cursor rather than its swing-start target")
	game.pickaxe._process(0.4)
	game._physics_process(0.0)
	_check(game.hit_count == hits_before + 1, "The same completed animation cannot apply damage twice")

	# Moving into a protected HUD after wind-up must not damage a stale target.
	game.swing_cooldown = 0.0
	game.aim_position = first.screen
	game._request_swing()
	game._process(0.04)
	game.pickaxe._process(0.04)
	motion.position = game.hud.gem_target_screen(0)
	game._input(motion)
	game._process(0.0)
	game.pickaxe._process(Pickaxe.STRIKE_TIME - 0.04)
	game._physics_process(0.0)
	_check(game.hit_count == hits_before + 1 and game.hovered == null and not game.marker.visible, "Moving a live swing over the HUD cannot mine its previous stone or leave a hover marker")
	game.pickaxe._process(0.4)

	game.swing_cooldown = 0.0
	game.aim_position = first.screen
	game._request_swing()
	game.round_state.remaining = 0.05
	game._physics_process(0.05)
	game.pickaxe._process(0.4)
	game._physics_process(0.0)
	_check(game.round_state.remaining == 0.0 and game.hit_count == hits_before + 1 and not game.impact_pending, "Round expiry still discards a later moving-pickaxe impact")


func _visible_targets() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for body in game.chunks:
		if body.is_gem_cover:
			continue
		var point: Vector2 = game.camera.unproject_position(body.mesh_instance.to_global(body.face_center))
		if game.hud.is_pointer_blocked(point):
			continue
		if game.ray_at(point).get("collider") == body:
			found.append({"body": body, "screen": point})
	return found


func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("PICKAXE_FOLLOW_FAILED: " + description)
