extends SceneTree
const Auction = preload("res://scripts/ore_auction.gd")

class CaptureGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var game: Node
var ui: Control
var files: Array[String] = []
var outcomes: Array[Dictionary] = []
var finished := false

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30).timeout.connect(func():
		if not finished:
			push_error("AUCTION_CAPTURE_TIMEOUT")
			quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	game = CaptureGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	ui = game.hud.auction_ui
	await physics_frame
	await create_timer(0.2).timeout
	_settle()
	await _save("auction_settled_offer")
	await _click(game.hud._auction.get_global_rect().get_center())
	ui.set_process(false)
	await _save("auction_preview")
	await _resize(Vector2i(360, 800))
	await _save("auction_preview_portrait")
	await _resize(Vector2i(800, 450))
	await _save("auction_preview_small")
	await _resize(Vector2i(1152, 800))
	_seed_outcome(4)
	await _click(ui._confirm.get_global_rect().get_center())
	ui.set_process(false)
	ui._process(1.1)
	await _save("auction_bidding")
	ui._process(1.72)
	await _save("auction_jackpot_reveal")
	ui._process(1.0)
	await _save("auction_result_200")
	outcomes.append(game.round_state.last_report.duplicate(true))
	await _resize(Vector2i(360, 800))
	await _save("auction_result_portrait")
	await _click(ui._confirm.get_global_rect().get_center())
	await _save("auction_adjusted_portrait")
	await _resize(Vector2i(1152, 800))
	await _save("auction_adjusted_settlement")
	for index in 4:
		game._next_round()
		_settle()
		await _click(game.hud._auction.get_global_rect().get_center())
		ui.set_process(false)
		_seed_outcome(index)
		await _click(ui._confirm.get_global_rect().get_center())
		ui.set_process(false)
		ui.finish_reveal()
		await _save("auction_result_%s" % ["m100", "m50", "50", "100"][index])
		outcomes.append(game.round_state.last_report.duplicate(true))
		await _click(ui._confirm.get_global_rect().get_center())
	var report := {"fixture": "Presentation cargo is 21 ordinary stones, 3 common gems and 1 special gem. Outcome seeds intentionally show each result; this is not a random-session frequency sample.", "outcomes": outcomes, "captures": files}
	var output := FileAccess.open("res://artifacts/auction_report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	finished = true
	print("AUCTION_CAPTURE_OK files=%d" % files.size())
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	quit()

func _settle() -> void:
	if game.spawn_tween != null and game.spawn_tween.is_valid():
		game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1.0
	game.round_state.wallet_gold = 777
	game.round_state.start()
	for i in 21:
		game.round_state.record_stone()
	for i in 3:
		game.round_state.record_gem(0)
	game.round_state.record_gem(1)
	game.round_state.advance(30)
	game._begin_settlement()
	game.hud.finish_settlement()
	game.pickaxe.hide()
	game.marker.hide()

func _seed_outcome(index: int) -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in 10000:
		rng.seed = seed_value
		if Auction.outcome_for_ticket(rng.randi_range(0, 99), false) == index:
			game.round_state.auction.previous_total_loss = false
			game.round_state.auction.rng.seed = seed_value
			return

func _resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	await process_frame
	game._resize()
	game.hud._layout()

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://artifacts/" + name + ".png"
	if image.save_png(path) != OK:
		push_error("AUCTION_CAPTURE_SAVE_FAILED " + name)
		quit(1)
	files.append(path)

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null
