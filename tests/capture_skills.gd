extends SceneTree
## Real game/UI captures. Review credit and complete-tree purchase are explicit.
const Main = preload("res://scripts/main.gd")
var game: Node3D
var files: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	game = Main.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.round_state.wallet_gold = 100000000
	game._open_upgrades()
	await _save("skills_reference_initial")
	root.size = Vector2i(360, 800)
	await process_frame
	await _save("skills_reference_initial_portrait")
	root.size = Vector2i(1152, 800)
	await process_frame
	await _hover("speed")
	await _save("skills_reference_hover")
	await _click(game.skill_ui.get_node_screen("speed"))
	await _save("skills_reference_confirm")
	await _click(game.skill_ui.get_confirmation_rect().get_center())
	await _save("skills_reference_frontier")
	# Buy through the real model's visibility/cost checks for an overview of all
	# authored content. This credit and these unlocks exist only in this capture.
	var progress := true
	while progress:
		progress = false
		for node: Dictionary in game.upgrades.get_nodes():
			if game.upgrades.can_purchase(node.id, game.round_state.wallet_gold):
				var purchase: Dictionary = game.upgrades.purchase(node.id, game.round_state.wallet_gold)
				game.round_state.wallet_gold = purchase.gold
				progress = true
	game._apply_upgrade_stats()
	game.skill_ui.refresh(game.round_state.wallet_gold)
	root.size = Vector2i(1920, 1440)
	await process_frame
	_overview()
	await create_timer(0.65).timeout
	await _save("skills_reference_complete")
	root.size = Vector2i(1152, 800)
	await process_frame
	for id: String in ["shock", "combo", "extra_critical", "revive", "brilliant", "healing_amount_2"]:
		_focus(id, 0.86)
		await _hover(id)
		await _save("skills_reference_" + id)
	root.size = Vector2i(360, 800)
	await process_frame
	_focus("extra_critical", 0.86)
	await _hover("extra_critical")
	await _save("skills_reference_portrait")
	root.size = Vector2i(800, 450)
	await process_frame
	_focus("combo", 0.72)
	await _hover("combo")
	await _save("skills_reference_small_landscape")
	game.skill_ui.close_tree()
	root.size = Vector2i(1152, 800)
	await process_frame
	game._spawn_rock(98174)
	game.spawn_time = 1.0
	if game.spawn_tween != null:
		game.spawn_tween.kill()
		game.rock_motion.scale = Vector3.ONE
	game._process(0.0)
	await _save("skills_reference_special_stones")
	# A complete, explicit example verifies eight-row settlement and golden day.
	game._start_round()
	game.round_state.golden_chance = 1.0
	for tier in 6:
		game.round_state.record_gem(tier, 1.5)
	for i in 12:
		game.round_state.record_stone()
	game.round_state.record_bonus_gold(27)
	game.round_state.advance(10000)
	game._begin_settlement()
	game.hud.finish_settlement()
	await _save("skills_reference_golden_day")
	root.size = Vector2i(360, 800)
	await process_frame
	await _save("skills_reference_golden_portrait")
	root.size = Vector2i(800, 450)
	await process_frame
	await _save("skills_reference_golden_landscape")
	var report := {"review_credit": 100000000, "full_tree_bought_for_capture": true, "nodes": game.upgrades.get_nodes().size(), "files": files, "stats": game.upgrades.stats(), "settlement": game.round_state.last_report}
	var output := FileAccess.open("res://artifacts/skills_reference_report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("SKILL_CAPTURE_OK files=", files.size(), " nodes=", game.upgrades.get_nodes().size())
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await create_timer(0.06).timeout
	quit()

func _overview() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for node: Dictionary in game.upgrades.get_nodes():
		bounds = bounds.expand(Vector2(node.grid) * game.skill_ui.GRID_STEP)
	var ui: Node = game.skill_ui
	ui.hovered_id = ""
	ui.selected_id = ""
	ui._hover_pin = ""
	ui._user_view = true
	ui._zoom = minf((ui._view.x - 100) / (bounds.size.x + 80), (ui._view.y - ui._header_height - 100) / (bounds.size.y + 80))
	ui._pan = -bounds.get_center() * ui._zoom + Vector2(0, ui._header_height * 0.5 + 20)
	ui._layout_nodes()

func _focus(id: String, zoom: float) -> void:
	var ui: Node = game.skill_ui
	ui.hovered_id = ""
	ui.selected_id = ""
	ui._hover_pin = ""
	ui._using_controller = false
	ui._user_view = true
	ui._zoom = zoom
	ui._pan = -Vector2(game.upgrades.get_node(id).grid) * ui.GRID_STEP * zoom
	ui._layout_nodes()

func _hover(id: String) -> void:
	var event := InputEventMouseMotion.new()
	event.position = game.skill_ui.get_node_screen(id)
	root.push_input(event, true)
	await process_frame
	await create_timer(0.08).timeout

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _save(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	var path := "res://artifacts/" + label + ".png"
	snapshot.save_png(ProjectSettings.globalize_path(path))
	files.append(path)

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null
