extends "res://tests/capture_tools.gd"
## Explicit earned-gold fixtures; production geometry, materials, HUD and loot.
const Progress = preload("res://scripts/ore_progression.gd")
var stages: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(120).timeout.connect(func():
		if not finished: _fail("Ore progression capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	game = CaptureGame.new()
	# Gold/geometry showcase; the campaign's boss gates are tested separately.
	game.campaign_enabled = false
	root.add_child(game)
	for node: Node in [game,game.hud,game.pickaxe,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.focused = true
	for stage: Dictionary in Progress.STAGES:
		game.round_state.phase = game.RoundModel.Phase.COMPLETE
		game.round_state.lifetime_mining_gold = stage.gold
		game._next_round()
		var batch_times: Array[float] = []
		while game.ore_building:
			var begin := Time.get_ticks_usec()
			game._advance_ore_build()
			batch_times.append((Time.get_ticks_usec()-begin)/1000.0)
			if batch_times.size() == 16: await _save("ore_progression_build_"+stage.id)
			await process_frame
		if game.spawn_tween != null: game.spawn_tween.kill()
		game.rock_motion.scale = Vector3.ONE
		game.spawn_time = 1.0
		game.effects._process(2)
		game._process(0)
		game.hud._process(1)
		game.aim_position = root.get_visible_rect().size*Vector2(0.62,0.68)
		game.pickaxe.set_target(game.aim_position)
		game.pickaxe._process(0)
		await physics_frame
		await _save("ore_progression_"+stage.id)
		var counts := [0,0,0,0,0,0]
		for jewel in game.gems: counts[jewel.grade] += 1
		batch_times.sort()
		stages.append({"id":stage.id,"test_earned_gold_injected":stage.gold,"radius":game.active_rock_radius,"pieces":game.chunks.size(),"gems":counts,"build_frames":batch_times.size(),"build_p95_ms":batch_times[int(batch_times.size()*0.95)] if not batch_times.is_empty() else 0,"build_max_ms":batch_times.back() if not batch_times.is_empty() else 0})
		# Rotate the actual stone to inspect the theme beyond its initial face.
		game.shell.rotate_y(PI*0.8)
		await physics_frame
		await _save("ore_progression_"+stage.id+"_back")
		game.shell.rotate_y(-PI*0.8)
		var targets: Array = []
		for chunk in game.chunks:
			var direction: Vector3 = game.shell.global_basis*chunk.direction
			if chunk.layer_index < 2 and direction.dot(game.camera.global_basis.z) > 0.35: targets.append(chunk)
		game.remove_with_auxiliary(targets)
		await create_timer(0.4).timeout
		game.effects._process(2)
		game._process(0)
		game.hud._process(0.5)
		await _save("ore_progression_"+stage.id+"_excavated")
	# The highest stage must still fit both real constrained window layouts.
	game.round_state.phase = game.RoundModel.Phase.COMPLETE
	game._next_round()
	while game.ore_building:
		game._advance_ore_build()
		await process_frame
	for dimensions: Vector2i in [Vector2i(360,800),Vector2i(800,450)]:
		await _resize(dimensions)
		game.aim_position = root.get_visible_rect().size*Vector2(0.55,0.62)
		game.pickaxe.set_target(game.aim_position)
		game.pickaxe._process(0)
		game.hud._process(1)
		await _save("ore_progression_largest_%dx%d" % [dimensions.x,dimensions.y])
	# A real one-gold threshold crossing and settlement announcement.
	await _resize(Vector2i(1152,800))
	game.round_state.phase = game.RoundModel.Phase.COMPLETE
	game.round_state.lifetime_mining_gold = 199
	game._next_round()
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	game._start_round()
	game.round_state.record_stone()
	game.round_state.advance(100)
	game._process(0)
	game.hud._process(12)
	await _save("ore_progression_unlock_settlement")
	var output := FileAccess.open("res://artifacts/ore_progression_report.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"stages":stages,"captures":files,"snapshots":snapshots},"\t"))
	output.close()
	finished = true
	print("ORE_PROGRESSION_CAPTURE_OK files=",files.size())
	_stop_audio(game)
	var deadline := Time.get_ticks_msec()+100
	while Time.get_ticks_msec() < deadline: await process_frame
	game.queue_free()
	await process_frame
	quit()
