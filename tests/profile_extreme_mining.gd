extends SceneTree
## Real renderer stress test. Samples include deferred deletion / driver work.
## No image readback or file writes during measured frames; no saved progress.
const Game = preload("res://scripts/main.gd")
var game: Node3D
var tag := "before"
var results: Dictionary = {}
var errors: Array[String] = []
var phase := "startup"
var samples: Dictionary = {}
var draw_calls: Dictionary = {}
var previous := 0
var finished := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=").validate_filename()
	_run.call_deferred()
	create_timer(300).timeout.connect(func():
		if not finished: errors.append("Watchdog: " + phase); _finish()
	)

func _check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); push_error(message)

func _sample() -> void:
	var now := Time.get_ticks_usec()
	if previous > 0:
		if not samples.has(phase): samples[phase] = []
		samples[phase].append((now-previous)/1000.0)
		if not draw_calls.has(phase): draw_calls[phase] = []
		draw_calls[phase].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	previous = now

func _maintenance() -> void:
	# Destruction retirement is production work and belongs in frame timings.
	if game.has_method("_advance_bulk_breaks"): game._advance_bulk_breaks()
	if game.has_method("_advance_damage_visuals"): game._advance_damage_visuals()
	if game.has_method("_advance_ore_retirement"): game._advance_ore_retirement()
	game._update_collections(1.0/120.0)

func _frames(count: int) -> void:
	for i in count:
		_maintenance()
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280,900)
	root.content_scale_size = Vector2i(1440,1000)
	root.title = "OneMoreOre extreme mining " + tag
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	AudioServer.set_bus_mute(0,true)
	game = Game.new()
	root.add_child(game)
	for node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.focused = true
	var budget := 1000000000
	for sweep in 30:
		for node in game.upgrades.get_nodes():
			if game.upgrades.can_purchase(node.id,budget): budget = int(game.upgrades.purchase(node.id,budget).gold)
	game.main_tools.acquire("gold_pickaxe",100000000)
	for entry in game.aux_tools.CATALOG: game.aux_tools.acquire(entry.id,100000000)
	game._apply_upgrade_stats()
	game.campaign.cleared = 6
	process_frame.connect(_sample)
	phase = "cold_load"
	var started := Time.get_ticks_usec()
	game._spawn_rock(12873)
	while game.ore_building:
		game._advance_ore_build()
		_maintenance()
		await process_frame
	results.cold_load_ms = (Time.get_ticks_usec()-started)/1000.0
	print("EXTREME_COLD_READY ms=",results.cold_load_ms)
	_ready_to_mine()
	_check(game.chunks.size() == 4736,"All 4,736 physical stones were built")
	_check(game.gems.size() == 68,"Full-upgrade extreme contains all 68 gems")
	phase = "idle"
	await _frames(60)
	if DisplayServer.get_name() != "headless":
		phase = "capture"
		DirAccess.make_dir_recursive_absolute("res://artifacts/performance")
		root.get_texture().get_image().save_png("res://artifacts/performance/extreme_"+tag+"_ore.png")
		previous = 0
	results.initial_objects = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	results.initial_memory = Performance.get_monitor(Performance.MEMORY_STATIC)
	# Time the whole activation plus the frames in which deleted GPU / physics
	# resources and all 68 collection flights are actually processed.
	phase = "detonate_4736"
	started = Time.get_ticks_usec()
	var gems_before: int = game.collected_count
	var stones_before: int = game.round_state.ordinary_stones
	var receipt: Dictionary = game.remove_with_auxiliary(game.chunks.duplicate(),1.0,false,10000000.0)
	results.detonate_call_ms = (Time.get_ticks_usec()-started)/1000.0
	while game._bulk_job != null: await _frames(1)
	results.detonate_commit_ms = (Time.get_ticks_usec()-started)/1000.0
	if receipt.get("pending",false): receipt = game.last_bulk_receipt
	results.detonate_receipt = receipt
	print("EXTREME_BLAST ms=",results.detonate_call_ms," receipt=",receipt)
	_check(game.chunks.is_empty() and game.collected_count-gems_before == 68,"Extreme blast destroys all stones and credits 68 gems exactly once")
	_check(game.round_state.ordinary_stones-stones_before == 4668,"Ordinary stone accounting survives full-ore destruction")
	await _frames(180)
	# Run preparation using the same budget as live play, then measure ready to
	# mine, not merely returning from the spawn function.
	phase = "prepare_next"
	started = Time.get_ticks_usec()
	while not game._ore_preparation.complete:
		game._advance_ore_preparation()
		_maintenance()
		await process_frame
	results.prepare_wall_ms = (Time.get_ticks_usec()-started)/1000.0
	print("EXTREME_PREPARED ms=",results.prepare_wall_ms)
	phase = "prepared_load"
	started = Time.get_ticks_usec()
	game._spawn_rock()
	while game.ore_building:
		game._advance_ore_build()
		_maintenance()
		await process_frame
	_ready_to_mine()
	await _frames(2)
	results.prepared_load_ms = (Time.get_ticks_usec()-started)/1000.0
	print("EXTREME_SWAPPED ms=",results.prepared_load_ms)
	_check(game.chunks.size() == 4736 and game.gems.size() == 68,"Prepared ore preserves geometry and current upgraded loot")
	phase = "wide_strikes"
	var calls: Array[float] = []
	for batch in 30:
		var targets: Array = game.chunks.filter(func(c): return c.layer_index == 0 and c.visible).slice(0,9)
		var context := {"secondary":false,"count":9,"reaction_marks":{},"reaction_budget":{"used":0}}
		started = Time.get_ticks_usec()
		game.audio.begin_impact()
		for chunk in targets:
			if not is_instance_valid(chunk) or chunk.destroyed: continue
			chunk.set_meta("special_kind","resonance")
			var point: Vector3 = chunk.mesh_instance.to_global(chunk.face_center)
			game._damage_chunk({"collider":chunk,"position":point,"normal":(chunk.global_basis*chunk.direction).normalized()},game.camera.unproject_position(point),context,10000000.0)
		game._drain_reactions()
		game.audio.end_impact()
		calls.append((Time.get_ticks_usec()-started)/1000.0)
		await _frames(1)
	results.wide_strike_cpu_ms = _stats(calls)
	print("EXTREME_WIDE ",results.wide_strike_cpu_ms)
	if DisplayServer.get_name() != "headless":
		phase = "capture"
		root.get_texture().get_image().save_png("res://artifacts/performance/extreme_"+tag+"_strikes.png")
		previous = 0
	phase = "chain_tail"
	for i in 100:
		game._drain_reactions()
		await _frames(1)
	phase = "partial_blast"
	var survivors: int = game.chunks.size()
	started = Time.get_ticks_usec()
	game.remove_with_auxiliary(game.chunks.duplicate(),1.0,false,.01)
	results.partial_call_ms = (Time.get_ticks_usec()-started)/1000.0
	while game._bulk_job != null: await _frames(1)
	_check(game.chunks.size() == survivors,"Partial blast never deletes surviving stones")
	await _frames(30)
	phase = "crusher_remaining"
	started = Time.get_ticks_usec()
	receipt = game.remove_with_auxiliary(game.chunks.duplicate(),.5,true,10000000.0)
	results.crusher_call_ms = (Time.get_ticks_usec()-started)/1000.0
	while game._bulk_job != null: await _frames(1)
	results.crusher_commit_ms = (Time.get_ticks_usec()-started)/1000.0
	if receipt.get("pending",false): receipt = game.last_bulk_receipt
	results.crusher_receipt = receipt
	await _frames(180)
	_check(game.chunks.is_empty() and game.gems.is_empty(),"Repeated destruction leaves no unclaimed gems")
	results.final_objects = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	results.final_memory = Performance.get_monitor(Performance.MEMORY_STATIC)
	# A second stress path ends the current ore before its successor is ready.
	# Measure finishing the existing half-built ore, including physics/rendering.
	phase = "half_prepare"
	while game._ore_preparation.chunks.size() < 2368:
		game._advance_ore_preparation()
		await _frames(1)
	var retained: StaticBody3D = game._ore_preparation.chunks[0]
	results.half_prepared_pieces = game._ore_preparation.chunks.size()
	phase = "half_prepared_load"
	started = Time.get_ticks_usec()
	game._spawn_rock()
	_check(game._using_prepared_build,"An early clear keeps its partial preparation")
	while game.ore_building:
		game._advance_ore_build()
		await _frames(1)
	_ready_to_mine()
	await _frames(2)
	results.half_prepared_load_ms = (Time.get_ticks_usec()-started)/1000.0
	_check(game.chunks.has(retained) and game.chunks.size() == 4736 and game.gems.size() == 68,"A reused partial preparation preserves physical stones and all hidden loot")
	_finish()

func _ready_to_mine() -> void:
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1.0
	game._start_round()

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {"count":sorted.size(),"p50":sorted[sorted.size()/2],"p95":sorted[mini(sorted.size()-1,int(ceil(sorted.size()*.95))-1)],"max":sorted[-1],"over_33ms":sorted.filter(func(x):return x>33.333).size(),"over_50ms":sorted.filter(func(x):return x>50).size()}

func _finish() -> void:
	if finished: return
	finished = true
	process_frame.disconnect(_sample)
	results.frames = {}
	results.draw_calls = {}
	for key in samples: results.frames[key] = _stats(samples[key])
	for key in draw_calls:
		var stats := _stats(draw_calls[key])
		stats.erase("over_33ms")
		stats.erase("over_50ms")
		results.draw_calls[key] = stats
	results.errors = errors
	results.adapter = RenderingServer.get_video_adapter_name()
	results.renderer = RenderingServer.get_current_rendering_method()
	results.tag = tag
	DirAccess.make_dir_recursive_absolute("res://artifacts/performance")
	var file := FileAccess.open("res://artifacts/performance/extreme_"+tag+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("EXTREME_MINING ",JSON.stringify(results))
	game.queue_free()
	await process_frame
	await create_timer(.1).timeout
	quit(0 if errors.is_empty() else 1)
