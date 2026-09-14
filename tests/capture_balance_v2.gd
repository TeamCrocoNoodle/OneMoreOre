extends SceneTree
## Real-renderer scale and dense-ore checks; no save data or purchases are changed.
const Game = preload("res://scripts/main.gd")
var game: Node3D
var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(180).timeout.connect(func(): quit(2))

func _run() -> void:
	root.size = Vector2i(1280,900)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	game = Game.new()
	root.add_child(game)
	for node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.focused = true
	DirAccess.make_dir_recursive_absolute("res://artifacts/balance/v2")
	for stage in [0,2,4,6]:
		game.campaign.cleared = stage
		game.round_state.phase = game.RoundModel.Phase.READY
		var started := Time.get_ticks_usec()
		game._spawn_rock(12873)
		while game.ore_building:
			game._advance_ore_build()
			await process_frame
		var build_ms := (Time.get_ticks_usec()-started)/1000.0
		if game.spawn_tween != null: game.spawn_tween.kill()
		game.rock_motion.scale = Vector3.ONE
		game.spawn_time = 1.0
		game.hud.set_ore_progress(game.campaign.decorate_status(game.OreProgression.status(0,stage)))
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/balance/v2/stage_%d.png" % (stage+1))
		var frames: Array[float] = []
		var previous := Time.get_ticks_usec()
		for i in 60:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now-previous)/1000.0)
			previous = now
		frames.sort()
		var info := {"stage":stage+1,"pieces":game.chunks.size(),"build_ms":build_ms,"frame_median_ms":frames[30],"frame_p95_ms":frames[56],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		results.append(info)
		print("DENSE_ORE_RENDER ",JSON.stringify(info))
	# Prepare the next dense ore exactly as normal idle frames do, then time
	# the production transition. Its gems are rolled only after adoption.
	while not game._ore_preparation.complete:
		game._advance_ore_preparation()
		await process_frame
	var started := Time.get_ticks_usec()
	game._spawn_rock()
	while game.ore_building:
		game._advance_ore_build()
		await process_frame
	var ready_ms := (Time.get_ticks_usec()-started)/1000.0
	results.append({"prepared_transition_ms":ready_ms,"pieces":game.chunks.size()})
	print("PREPARED_ORE_TRANSITION ms=",ready_ms," pieces=",game.chunks.size())
	var file := FileAccess.open("res://artifacts/balance/v2/render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	game.queue_free()
	await process_frame
	print("BALANCE_V2_CAPTURE_OK")
	quit()
