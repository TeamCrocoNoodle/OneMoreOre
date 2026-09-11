extends SceneTree
## Real starter ore -> raycast excavation -> crystal flights -> timed settlement.
## Only the clock and camera are driven by this fixture; cargo is never injected.
const Gem = preload("res://scripts/gem.gd")
const RoundModel = preload("res://scripts/mining_round.gd")
const SEED := 12873

class CaptureGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		# Keep normal buried-gem placement, with repeatable first/next ore seeds.
		super._spawn_rock(12873 + rock_number * 7919 if seed_override < 0 else seed_override, showcase)

var game: CaptureGame
var finished := false
var files: Array[String] = []
var snapshots: Array[Dictionary] = []
var cues: Array[Dictionary] = []
var excavations: Array[Dictionary] = []
var report: Dictionary = {}
var active_saved := false

func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
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
	game.hud.set_process(false)
	game.hud.cue.connect(func(kind: String, tier: int): cues.append({"kind": kind, "tier": tier}))
	game.focused = true
	game.spawn_time = 1.0
	game.marker.hide()
	game.hud._process(0.5)
	await physics_frame
	await create_timer(0.25).timeout
	game._process(0.0)
	game.hud._process(0.0)
	var targets: Array[StaticBody3D] = []
	var initial_gems: Array[Dictionary] = []
	for jewel in game.gems:
		var host: StaticBody3D = jewel.host_chunk.get_ref()
		initial_gems.append({"grade": jewel.grade, "rarity": Gem.GRADE_NAMES[jewel.grade], "host_layer": host.layer_index, "hidden": jewel.is_embedded and not jewel.visible and jewel.collision_layer == 0})
		if jewel.grade == Gem.COMMON:
			targets.append(jewel)
	for jewel in game.gems:
		if jewel.grade == Gem.SPECIAL:
			targets.append(jewel)
	if game.showcase_mode or not game.round_enabled or targets.size() != 4 or game.round_state.phase != RoundModel.Phase.READY:
		_fail("Expected the untouched timed starter with three white and one green gem")
		return
	report = {"seed": game.rock_seed, "radius": game.active_rock_radius, "initial_chunks": game.chunks.size(), "initial_gems": initial_gems, "mining_method": "Main._mine_at real physics rays through the normal buried starter", "clock_method": "Manual _advance_round; no cargo or report injection"}
	await _save("round_ready")
	await _window_size(Vector2i(1280, 720))
	await _save("round_ready_wide")
	await _window_size(Vector2i(360, 800))
	await _save("round_ready_narrow")
	await _portrait(false)
	for i in targets.size():
		var jewel: StaticBody3D = targets[i]
		if not is_instance_valid(jewel) or jewel.collected:
			continue
		if not await _excavate(jewel, i == 0, jewel.grade == Gem.SPECIAL):
			return
	if game.round_state.gem_counts[0] != 3 or game.round_state.gem_counts[1] != 1 or not game.collecting_gems.is_empty():
		_fail("All four actually excavated starter gems must arrive before settlement")
		return
	game.hud._process(0.45)
	await _save("round_cargo_arrived")
	await _portrait(true)
	await _save("round_portrait_play")
	await _portrait(false)
	game.focused = true
	game._advance_round(maxf(game.round_state.remaining - 4.75, 0.0))
	game._process(0.0)
	game.hud._process(0.02)
	await _save("round_last5s")
	var expected_counts: PackedInt32Array = game.round_state.gem_counts.duplicate()
	var expected_stones: int = game.round_state.ordinary_stones
	var expected_gold := expected_stones
	var prices := [10, 50, 200, 1000, 5000, 25000]
	for tier in 6:
		expected_gold += expected_counts[tier] * prices[tier]
	report["mined"] = {"ordinary_stones": expected_stones, "gem_counts": Array(expected_counts), "unit_gem_gold": prices, "predicted_gold": expected_gold, "hits": game.hit_count, "broken_chunks": game.broken_count}
	game._advance_round(4.75)
	game._process(0.0)
	if game.round_state.phase != RoundModel.Phase.SETTLING:
		_fail("Real timer expiry and drained flights must open settlement")
		return
	report["settlement"] = game.round_state.last_report.duplicate(true)
	game.hud._process(0.76)
	await _save("round_settlement_firstrow")
	game.hud._process(0.80)
	await _save("round_settlement_counting")
	game.hud._process(1.50)
	if game.round_state.phase != RoundModel.Phase.COMPLETE or game.round_state.wallet_gold != expected_gold or int(report.settlement.total) != expected_gold:
		_fail("Animated settlement did not commit exactly the independently priced cargo")
		return
	await _save("round_settlement_final")
	await _window_size(Vector2i(1280, 720))
	await _save("round_settlement_wide")
	await _portrait(true)
	await _save("round_portrait_settlement")
	await _window_size(Vector2i(360, 800))
	await _save("round_settlement_narrow")
	await _portrait(false)
	# Drive the actual visible button, including its guarded signal and reset route.
	game.hud._replay.pressed.emit()
	await create_timer(0.72).timeout
	game.spawn_time = 1.0
	game.focused = true
	game._process(0.0)
	game.hud._process(0.5)
	if game.round_state.phase != RoundModel.Phase.READY or game.round_state.round_index != 2 or game.round_state.wallet_gold != expected_gold or game.round_state.remaining != 30.0 or game.displayed_gems != PackedInt32Array([0, 0, 0, 0, 0, 0]):
		_fail("Next round must preserve the wallet and reset timer and cargo")
		return
	await _save("round_next_round")
	report["next_round"] = {"seed": game.rock_seed, "round_index": game.round_state.round_index, "wallet_gold": game.round_state.wallet_gold, "remaining": game.round_state.remaining, "gem_counts": Array(game.displayed_gems), "hidden_gems": game.gems.size()}
	report["excavations"] = excavations
	report["captures"] = files
	report["snapshots"] = snapshots
	report["hud_cues"] = cues
	var file := FileAccess.open("res://artifacts/round_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	finished = true
	print("ROUND_CAPTURE_OK files=", files.size(), " hits=", game.hit_count, " stones=", expected_stones, " gems=", expected_counts, " gold=", expected_gold, " next_seed=", game.rock_seed)
	_stop_audio(game)
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await process_frame
	quit()

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _excavate(jewel: StaticBody3D, capture_white: bool, capture_green: bool) -> bool:
	var host: StaticBody3D = jewel.host_chunk.get_ref()
	var grade: int = jewel.grade
	var host_layer: int = host.layer_index
	var start_hits: int = game.hit_count
	game.shell.quaternion = Quaternion(Vector3(host.direction).normalized(), game.camera.global_basis.z.normalized())
	await physics_frame
	for step in 80:
		game.focused = true
		var target: Vector2 = game.camera.unproject_position(host.mesh_instance.to_global(host.face_center))
		var ray: Dictionary = game.ray_at(target)
		if ray.is_empty():
			_fail("Real excavation ray missed grade %d at hit %d" % [grade, step])
			return false
		game.aim_position = target
		game.pickaxe.set_target(target)
		if not game._mine_at(target):
			_fail("Real excavation hit rejected grade %d at hit %d" % [grade, step])
			return false
		game._advance_round(0.12)
		game._process(1.0 / 60.0)
		game.hud._process(0.12)
		if not active_saved:
			active_saved = true
			await _save("round_active")
		if jewel.collected:
			if not jewel.is_emerging or jewel.is_embedded or not game.collecting_gems.any(func(entry: Dictionary): return entry.node == jewel):
				_fail("Breaking the real host must start automatic collection and emergence")
				return false
			await create_timer(0.43).timeout
			game._update_collections(0.30)
			game.hud._process(0.10)
			if capture_white or capture_green:
				if game.flight_overlay.active_count <= 0 or not jewel.visible or not is_instance_valid(jewel.facets):
					_fail("The actual crystal must remain rendered during the HUD flight")
					return false
				await _save("round_white_flight_mid" if capture_white else "round_green_flight_mid")
			if capture_white:
				# Keep the real model alive over its HUD destination to verify layering.
				game._update_collections(0.38)
				await _save("round_white_flight_near_hud")
				game._update_collections(0.12)
			else:
				game._update_collections(0.50)
			game.hud._process(0.025)
			if capture_white:
				await _save("round_white_arrival")
			excavations.append({"grade": grade, "host_layer": host_layer, "real_hits": game.hit_count - start_hits, "timer_remaining": game.round_state.remaining, "displayed_counts": Array(game.displayed_gems)})
			await physics_frame
			return true
		await physics_frame
	_fail("Real excavation could not reach grade %d" % grade)
	return false

func _portrait(enabled: bool) -> void:
	await _window_size(Vector2i(600, 1000) if enabled else Vector2i(1152, 800))

func _window_size(dimensions: Vector2i) -> void:
	root.size = dimensions
	# Preserve the real project's 1440x1000 canvas_items/expand stretch contract.
	# The portrait viewport expands logically; changing its design size hides bugs.
	await process_frame
	game._resize()
	game._process(0.0)
	game.hud._process(0.0)

func _save(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/" + label + ".png"
	var picture := root.get_texture().get_image()
	if picture.save_png(ProjectSettings.globalize_path(path)) != OK:
		_fail("Cannot save " + label)
		return
	files.append(path)
	var logical_size := game.get_viewport().get_visible_rect().size
	snapshots.append({"file": path, "phase": game.round_state.phase, "remaining": game.round_state.remaining, "wallet_gold": game.round_state.wallet_gold, "hud_counts": Array(game.hud.displayed_counts), "hud_stones": game.hud.displayed_stones, "flying_models": game.flight_overlay.active_count, "settlement_shown_gold": game.hud._shown_total, "width": picture.get_width(), "height": picture.get_height(), "logical_width": logical_size.x, "logical_height": logical_size.y})

func _fail(message: String) -> void:
	finished = true
	push_error("ROUND_CAPTURE_FAILED: " + message)
	quit(1)
