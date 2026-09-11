extends SceneTree
## Actual Main and actual skill Buttons; only the review wallet is seeded.
const PURCHASE_ORDER := ["vitality", "recovery", "power", "speed", "reach", "appraisal", "rich_ore", "soft_ore"]

class CaptureGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var game: Node3D
var files: Array[String] = []
var frames: Array[Dictionary] = []
var finished := false
var starting_gold := 160

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func():
		if not finished:
			_fail("Timed out")
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
	# This is explicit review credit, not a fabricated mining/settlement award.
	game.round_state.wallet_gold = starting_gold
	game.hud.set_wallet(starting_gold)
	game._process(0.0)
	game.hud._process(0.5)
	await physics_frame
	await create_timer(0.2).timeout
	await _save("skills_entry")
	game._open_upgrades()
	await create_timer(0.18).timeout
	if not game.skill_ui.is_open:
		_fail("The real Main skill entry did not open")
		return
	await _save("skills_initial")
	await _hover(game.skill_ui.get_node_screen("power"))
	await _save("skills_hover")
	await _click(game.skill_ui.get_node_screen("power"))
	if game.skill_ui.selected_id != "power" or game.round_state.wallet_gold != starting_gold:
		_fail("The first click must select without spending")
		return
	await _save("skills_confirm")
	await _click(game.skill_ui.get_node_screen("vitality"))
	if not game.skill_ui.selected_id.is_empty() or game.round_state.wallet_gold != starting_gold:
		_fail("Clicking another node must cancel the pending confirmation")
		return
	await _save("skills_cancelled")
	if not await _buy("power"):
		return
	await _save("skills_purchased")
	await _hover(game.skill_ui.get_node_screen("speed"))
	await _save("skills_revealed")
	if not await _buy("vitality"):
		return
	if not await _buy("rich_ore"):
		return
	if not await _buy("appraisal"):
		return
	# 160 - 25 - 20 - 40 - 30 = 45, so the now-revealed 55G reach stays locked.
	await _hover(game.skill_ui.get_node_screen("reach"))
	await _click(game.skill_ui.get_node_screen("reach"))
	await _save("skills_insufficient")
	if game.round_state.wallet_gold != 45 or game.upgrades.is_unlocked("reach"):
		_fail("Insufficient-gold selection must preserve wallet and ownership")
		return
	root.size = Vector2i(600, 1000)
	await process_frame
	game._resize()
	game._process(0.0)
	game.hud._process(0.0)
	await _hover(game.skill_ui.get_node_screen("recovery"))
	await _save("skills_portrait")
	await _click(game.skill_ui.get_node_screen("recovery"))
	if game.skill_ui.selected_id != "recovery":
		# An existing insufficient selection may intentionally require a cancel
		# click before selecting a different node.
		await _click(game.skill_ui.get_node_screen("recovery"))
	await _save("skills_portrait_confirm")
	root.size = Vector2i(360, 800)
	await process_frame
	game._resize()
	game._process(0.0)
	await _hover(game.skill_ui.get_node_screen("reach"))
	await _click(game.skill_ui.get_node_screen("reach"))
	if game.skill_ui.selected_id != "reach":
		await _click(game.skill_ui.get_node_screen("reach"))
	await _save("skills_narrow_portrait")
	root.size = Vector2i(800, 450)
	await process_frame
	game._resize()
	game._process(0.0)
	await _click(game.skill_ui.get_node_screen("origin"))
	await _hover(game.skill_ui.get_node_screen("soft_ore"))
	if game.skill_ui.hovered_id != "soft_ore":
		await _hover(game.skill_ui.get_node_screen("soft_ore"))
	if game.skill_ui.hovered_id != "soft_ore" or game.skill_ui.get_detail_rect().size.x <= 0.0:
		_fail("The small landscape capture must actually show the bottom-node hover details")
		return
	await _save("skills_small_landscape")
	root.size = Vector2i(600, 1000)
	await process_frame
	game._resize()
	game.skill_ui.close_tree()
	if game.spawn_tween != null and game.spawn_tween.is_valid():
		await create_timer(0.72).timeout
	game.spawn_time = 1.0
	game._process(0.0)
	game.hud._process(0.0)
	await _save("skills_return_to_mining")
	game.focused = true
	game._start_round()
	game._advance_round(game.round_state.remaining)
	game._process(0.0)
	game.hud.finish_settlement()
	game._process(0.0)
	game.hud._process(0.0)
	await _save("skills_complete_entry_portrait")
	root.size = Vector2i(360, 800)
	await process_frame
	game._resize()
	game._process(0.0)
	game.hud._process(0.0)
	await _save("skills_complete_entry_narrow")
	var unlocked: Array[String] = []
	var visible: Array[String] = []
	for node: Dictionary in game.upgrades.get_nodes():
		if game.upgrades.is_unlocked(node.id):
			unlocked.append(node.id)
		if game.upgrades.is_visible(node.id):
			visible.append(node.id)
	var report := {"test_credit_injected": starting_gold, "wallet_gold": game.round_state.wallet_gold, "actual_purchase_method": "Main entry plus real SkillTreeUI node and confirmation Buttons", "owned": unlocked, "visible": visible, "stats": game.upgrades.stats(), "remaining": game.round_state.remaining, "actual_buried_gems": game.gems.size(), "captures": files, "frames": frames}
	var file := FileAccess.open("res://artifacts/skills_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	finished = true
	print("SKILL_CAPTURE_OK files=", files.size(), " gold=", game.round_state.wallet_gold, " owned=", unlocked, " gems=", game.gems.size())
	_stop_audio(game)
	game.queue_free()
	await process_frame
	var deadline := Time.get_ticks_usec() + 40000
	while Time.get_ticks_usec() < deadline:
		await process_frame
	quit()

func _buy(id: String) -> bool:
	if not game.skill_ui.selected_id.is_empty():
		await _click(game.skill_ui.get_node_screen("origin"))
	await _click(game.skill_ui.get_node_screen(id))
	var confirmation: Rect2 = game.skill_ui.get_confirmation_rect()
	if game.skill_ui.selected_id != id or confirmation.size.x <= 0.0:
		_fail("Missing actual confirmation for " + id)
		return false
	await _click(confirmation.get_center())
	if not game.upgrades.is_unlocked(id):
		_fail("Actual confirmation did not purchase " + id)
		return false
	return true

func _hover(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await process_frame
	await create_timer(0.14).timeout

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
	var visible: Array[String] = []
	for node: Dictionary in game.upgrades.get_nodes():
		if game.upgrades.is_visible(node.id):
			visible.append(node.id)
	frames.append({"file": path, "gold": game.round_state.wallet_gold, "selected": game.skill_ui.selected_id, "hovered": game.skill_ui.hovered_id, "open": game.skill_ui.is_open, "visible": visible, "physical_size": [image.get_width(), image.get_height()]})

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _fail(message: String) -> void:
	finished = true
	push_error("SKILL_CAPTURE_FAILED: " + message)
	quit(1)
