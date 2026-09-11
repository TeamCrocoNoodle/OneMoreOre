extends SceneTree
## Actual Main presentation fixture; review cargo is explicitly synthetic.
const HUD = preload("res://scripts/mining_hud.gd")

class CaptureGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var game: Node3D
var files: Array[String] = []
var finished := false
var counts := PackedInt32Array([3, 2, 1, 1, 1, 1])
var rendered_models: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func():
		if not finished:
			push_error("MODELED_UI_CAPTURE_TIMEOUT")
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
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.round_state.wallet_gold = 1234
	game._process(0.0)
	await physics_frame
	await create_timer(0.2).timeout
	for tier in range(-1, 6):
		var texture: Texture2D = game.model_gallery.get_coin_texture() if tier < 0 else game.model_gallery.get_gem_texture(tier)
		if not _record_texture(texture, "coin" if tier < 0 else "gem_%d" % tier):
			return
	_present_satchel()
	await _save("modeled_hud_six")
	game._open_upgrades()
	await _hover(game.skill_ui.get_node_screen("appraisal"))
	await _save("modeled_skill_cost")
	await _click(game.skill_ui.get_tab_rect("tools").get_center())
	await create_timer(0.2).timeout
	await _save("modeled_tools_wide")
	if not _record_texture(game.skill_ui.tools_panel.cabinet_viewport.get_texture(), "cabinet"):
		return
	await _hover(game.skill_ui.tools_panel.get_item_rect(1).get_center())
	await _save("modeled_tools_hover")
	await _resize(Vector2i(360, 800))
	game.skill_ui.tools_panel.scroll_by(-100000.0)
	await _save("modeled_tools_portrait")
	await _resize(Vector2i(800, 450))
	game.skill_ui.tools_panel.scroll_by(100000.0)
	await _save("modeled_tools_small_bottom")
	game.skill_ui.close_tree()
	await _resize(Vector2i(360, 800))
	_present_satchel()
	await _save("modeled_hud_portrait")
	await _resize(Vector2i(1152, 800))
	var report := _review_report()
	game.hud.show_settlement(report)
	game.hud._process(1.1)
	await _save("modeled_settlement_counting")
	game.hud.finish_settlement()
	await _save("modeled_settlement_final")
	await _resize(Vector2i(360, 800))
	await _save("modeled_settlement_portrait")
	var output := {
		"fixture": "Actual Main UI with explicit presentation-only review cargo; no mining or purchase is fabricated.",
		"review_wallet": 1234, "review_counts": Array(counts), "review_stones": 42,
		"presentation_report": report, "actual_wallet": game.round_state.wallet_gold,
		"actual_mined_counts": Array(game.round_state.gem_counts), "rendered_models": rendered_models, "captures": files
	}
	var file := FileAccess.open("res://artifacts/modeled_ui_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("MODELED_UI_CAPTURE_OK files=%d actual_wallet=%d" % [files.size(), game.round_state.wallet_gold])
	finished = true
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	quit()

func _present_satchel() -> void:
	game.hud.begin_round(1, 1234)
	game.hud.set_timer(24.0, 30.0, true)
	game.hud.set_stones(42)
	game.hud.set_gem_counts(counts)
	game.hud._process(0.5)

func _review_report() -> Dictionary:
	var rows: Array[Dictionary] = [{"kind": "stone", "tier": -1, "label": "돌 조각", "count": 42, "unit_gold": 1, "gold": 42}]
	var prices := [10, 50, 200, 1000, 5000, 25000]
	var total := 42
	for tier in 6:
		var gold: int = counts[tier] * prices[tier]
		rows.append({"kind": "gem", "tier": tier, "label": HUD.RARITY_NAMES[tier], "count": counts[tier], "unit_gold": prices[tier], "gold": gold})
		total += gold
	return {"rows": rows, "total": total, "wallet_before": 1234, "wallet_after": 1234 + total, "round_index": 1}

func _resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	await process_frame
	game._resize()
	game._process(0.0)
	if game.hud.settlement_visible:
		# The presentation-only report leaves the actual model in READY.
		# Preserve a finished timer behind the modal when Main recomputes layout.
		game.hud.set_timer(0.0, 30.0, false)
	game.hud._process(0.0)

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

func _hover(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await process_frame
	await create_timer(0.12).timeout

func _save(tag: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://artifacts/" + tag + ".png"
	if image.save_png(path) != OK:
		push_error("MODELED_UI_CAPTURE_SAVE_FAILED " + tag)
		quit(1)
	files.append(path)

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _record_texture(texture: Texture2D, kind: String) -> bool:
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		push_error("MODELED_UI_BLANK_TEXTURE " + kind)
		finished = true
		quit(1)
		return false
	var covered := 0
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			if image.get_pixel(x, y).a > 0.05:
				covered += 1
	if covered < 16:
		push_error("MODELED_UI_EMPTY_MODEL " + kind)
		finished = true
		quit(1)
		return false
	if kind == "coin":
		image.save_png("res://artifacts/modeled_coin_detail.png")
	rendered_models.append({"kind": kind, "width": image.get_width(), "height": image.get_height(), "visible_alpha_samples": covered})
	return true
