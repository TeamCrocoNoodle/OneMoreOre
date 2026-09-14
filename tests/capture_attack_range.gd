extends "res://tests/capture_tools.gd"
## Actual gameplay at baseline, upgraded range, and responsive window sizes.
const MainTools = preload("res://scripts/main_tools.gd")
var reports: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(60).timeout.connect(func():
		if not finished: _fail("Attack range capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/attack_range"))
	game = CaptureGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game._process(0.0)
	await physics_frame
	await create_timer(0.3).timeout
	game.aim_position = root.get_visible_rect().size * Vector2(0.48, 0.48)
	await _frame("baseline")
	game.main_tools.acquire("hammer", int(MainTools.definition("hammer").price))
	game._apply_upgrade_stats()
	await _frame("hammer")
	var values: Dictionary = game.upgrade_stats.duplicate()
	values.range_bonus = 1.5
	game.mining_skills.configure(values)
	await _frame("hammer_upgraded")
	game.mining_skills.buff = 2
	game.mining_skills.buff_remaining = 5.0
	await _frame("hammer_buff")
	# The preview is recomputed from bounded rays, never by building meshes.
	var primary: Dictionary = game.ray_at(game.aim_position)
	var timings: Array[float] = []
	for sample in 180:
		var start := Time.get_ticks_usec()
		game._update_attack_preview(primary)
		timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
	timings.sort()
	reports.append({"ore_chunks": game.chunks.size(), "preview_cpu_median_ms": timings[90], "preview_cpu_p95_ms": timings[171]})
	game._open_upgrades()
	await _save("attack_range/upgrades_hidden")
	game.skill_ui.close_tree()
	for dimensions: Vector2i in [Vector2i(800, 450), Vector2i(360, 800), Vector2i(1920, 1080)]:
		await _resize(dimensions)
		game.aim_position = root.get_visible_rect().size * Vector2(0.48, 0.48)
		await _frame("range_%dx%d" % [dimensions.x, dimensions.y])
	# Exercise the largest ore too, including preview cost on its real shapes.
	await _resize(Vector2i(1152, 800))
	game.campaign_enabled = false
	game.campaign.cleared = 6
	game.round_state.lifetime_mining_gold = 999999999
	game._spawn_rock(12873)
	while game.ore_building:
		game._advance_ore_build()
		await process_frame
	game.spawn_time = 1.0
	await physics_frame
	game.aim_position = root.get_visible_rect().size * Vector2(0.48, 0.48)
	await _frame("exotic")
	primary = game.ray_at(game.aim_position)
	timings.clear()
	for sample in 180:
		var start := Time.get_ticks_usec()
		game._update_attack_preview(primary)
		timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
	timings.sort()
	reports.append({"ore_chunks": game.chunks.size(), "preview_cpu_median_ms": timings[90], "preview_cpu_p95_ms": timings[171]})
	var file := FileAccess.open("res://artifacts/attack_range/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	file.close()
	_stop_audio(game)
	await create_timer(0.15).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	finished = true
	print("ATTACK_RANGE_CAPTURE_OK files=", files.size(), " reports=", JSON.stringify(reports))
	quit()

func _frame(label: String) -> void:
	game.focused = true
	game._physics_process(0.0)
	game.pickaxe._process(0.0)
	await _save("attack_range/" + label)
	if not game.attack_range.ring.visible:
		_fail("No real attack preview in " + label)
	reports.append({"label": label, "world_radius": game.mining_skills.radius(game.round_state.spent), "screen_radius": game.attack_range.ring.radius, "targets": game._attack_preview_chunks.size()})
