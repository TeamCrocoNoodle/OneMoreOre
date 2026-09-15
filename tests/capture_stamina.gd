extends "res://tests/capture_tools.gd"
## Real Main clock/health values, with deterministic UI review states only.

func _initialize() -> void:
	_run.call_deferred()
	create_timer(60).timeout.connect(func():
		if not finished: _fail("Stamina capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/stamina"))
	game = CaptureGame.new()
	root.add_child(game)
	for node: Node in [game, game.pickaxe, game.hud]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	while game._ore_builder != null: game._advance_ore_build()
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.spawn_time = 1.0
	game.rock_motion.scale = Vector3.ONE
	game.focused = true
	await _state("ready")
	game.round_state.start()
	game.round_state.advance(0.1)
	await _state("299")
	game.round_state.advance(0.9)
	await _state("290")
	game._apply_skill_reward({"heal": 0.35}, root.get_visible_rect().size * Vector2(0.5, 0.35))
	await _state("recovery")
	# Configuring a ready ledger gives this capture the fully upgraded capacity.
	game.round_state.phase = game.RoundModel.Phase.READY
	game.round_state.apply_stats({"duration": 52.0, "drain_rate": 0.82})
	game.round_state.start()
	game.round_state.advance(10.0)
	game.hud._skill_notices.clear()
	await _state("upgraded")
	for dimensions: Vector2i in [Vector2i(360, 800), Vector2i(640, 360), Vector2i(3840, 2160)]:
		root.size = dimensions
		await process_frame
		game._resize()
		await _state("%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1152, 800)
	await process_frame
	game._resize()
	game.focused = false
	await _state("paused")
	game.focused = true
	game.round_state.remaining = 2.9
	await _state("low")
	game.round_state.advance(game.round_state.seconds_remaining())
	await _state("empty")
	finished = true
	print("STAMINA_CAPTURE_OK files=", files.size())
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await process_frame
	quit()

func _state(label: String) -> void:
	game.aim_position = root.get_visible_rect().size * Vector2(0.5, 0.45)
	game._process(0)
	game.pickaxe._process(0)
	game.hud._process(0.016)
	await _save("stamina/" + label)
