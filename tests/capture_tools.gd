extends SceneTree
## Real Main shared tabs and shelf previews; the tool display never buys items.

class CaptureGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var game: Node3D
var files: Array[String] = []
var snapshots: Array[Dictionary] = []
var finished := false

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
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	# Review funds are explicit. Every tool price remains presentation only.
	game.round_state.wallet_gold = 160
	game.hud.set_wallet(160)
	game._process(0.0)
	game.hud._process(0.5)
	await physics_frame
	await create_timer(0.2).timeout
	game._open_upgrades()
	await _save("tools_shared_skills")
	await _click(game.skill_ui.get_node_screen("power"))
	await _save("tools_skill_pending")
	await _tab("tools")
	if not game.skill_ui.selected_id.is_empty() or game.skill_ui.get_confirmation_rect().size != Vector2.ZERO:
		_fail("Tools must cancel the pending skill confirmation")
		return
	await create_timer(0.25).timeout
	await _save("tools_desktop_shelves")
	var display: Control = game.skill_ui.tools_panel
	await _hover(display.get_item_rect(1).get_center())
	await _save("tools_desktop_hover")
	await _click(display.get_price_tag_rect(2).get_center())
	if game.round_state.wallet_gold != 160:
		_fail("A preview-only price tag spent gold")
		return
	await _save("tools_desktop_selected")
	await _tab("skills")
	await _save("tools_skills_return")
	await _tab("tools")
	await _resize(Vector2i(360, 800))
	display.scroll_by(-100000.0)
	await _save("tools_portrait_top")
	display.scroll_by(100000.0)
	await _hover(display.get_item_rect(5).get_center())
	await _save("tools_portrait_bottom")
	await _resize(Vector2i(800, 450))
	display.scroll_by(-100000.0)
	await _save("tools_small_landscape_top")
	display.scroll_by(100000.0)
	await _save("tools_small_landscape_bottom")
	await _tab("skills")
	await _save("tools_small_landscape_skills")
	await _resize(Vector2i(1152, 800))
	game.skill_ui.close_tree()
	game._process(0.0)
	game.hud._process(0.0)
	await _save("tools_closed")
	if game.round_state.wallet_gold != 160 or game.upgrades.is_unlocked("power"):
		_fail("Viewing tools or cancelling tabs altered the actual economy")
		return
	var report := {"test_credit_injected": 160, "final_gold": game.round_state.wallet_gold, "tools_purchased": 0, "actual_catalog": display.get_catalog(), "captures": files, "snapshots": snapshots}
	var file := FileAccess.open("res://artifacts/tools_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	finished = true
	print("TOOLS_CAPTURE_OK files=", files.size(), " wallet=", game.round_state.wallet_gold, " items=", display.get_catalog().size())
	_stop_audio(game)
	game.queue_free()
	await process_frame
	var deadline := Time.get_ticks_usec() + 40000
	while Time.get_ticks_usec() < deadline:
		await process_frame
	quit()

func _tab(id: String) -> void:
	await _click(game.skill_ui.get_tab_rect(id).get_center())
	if game.skill_ui.selected_tab != id:
		_fail("The real shared tab did not select " + id)

func _resize(size: Vector2i) -> void:
	# Keep the real 1440x1000 design size and expand stretch in every layout.
	root.size = size
	await process_frame
	game._resize()
	game._process(0.0)
	game.hud._process(0.0)

func _hover(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await process_frame
	await create_timer(0.12).timeout

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

func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://artifacts/" + name + ".png"
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		_fail("Cannot save " + name)
		return
	files.append(path)
	var display: Control = game.skill_ui.tools_panel
	snapshots.append({"file": path, "open": game.skill_ui.is_open, "tab": game.skill_ui.selected_tab, "selected_skill": game.skill_ui.selected_id, "selected_tool": display.selected_index, "scroll": display.get_scroll_offset(), "scroll_limit": display.get_scroll_limit(), "gold": game.round_state.wallet_gold, "physical_size": [image.get_width(), image.get_height()]})

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _fail(message: String) -> void:
	finished = true
	push_error("TOOLS_CAPTURE_FAILED: " + message)
	quit(1)
