extends "res://tests/capture_tools.gd"
## Real game models at reference left / edge-on / right positions and impact.
const Tools = preload("res://scripts/main_tools.gd")

class Caption extends Control:
	var text := ""
	func _draw() -> void:
		draw_string(ThemeDB.fallback_font, Vector2(28, 185), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)

func _initialize() -> void:
	_run.call_deferred()
	create_timer(60).timeout.connect(func():
		if not finished: _fail("Tool facing capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/tool_facing"))
	game = CaptureGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	while game._ore_builder != null:
		game._advance_ore_build()
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.spawn_time = 1.0
	game.rock_motion.scale = Vector3.ONE
	game.focused = true
	game._process(0)
	game.hud._process(0.5)
	await physics_frame
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var caption := Caption.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(caption)
	var center: Vector2 = game.camera.unproject_position(game.shell.global_position)
	var span: float = game.camera.unproject_position(game.shell.global_position + game.camera.global_basis.x * game.active_rock_radius).x - center.x
	var sheet := Image.create(1440, 334 * Tools.CATALOG.size(), false, Image.FORMAT_RGBA8)
	for row in Tools.CATALOG.size():
		var id: String = Tools.CATALOG[row].id
		game.pickaxe.set_tool(id)
		game.pickaxe.speed_multiplier = 1.0
		for column in 3:
			var side: String = ["left", "center", "right"][column]
			var target := center + Vector2(span * (column - 1) * 1.08, 0)
			game.pickaxe.cancel_swing()
			game.aim_position = target
			game._process(0)
			game.pickaxe._process(0)
			caption.text = "%s / %s" % [id, side]
			caption.queue_redraw()
			var frame := await _frame("%s_%s_idle" % [id, side])
			frame.resize(480, 334, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(frame, Rect2i(0, 0, 480, 334), Vector2i(column * 480, row * 334))
			game.pickaxe.swing()
			game.pickaxe._process(float(game.pickaxe._strike_times[0]) + 0.0001)
			caption.text += " / impact"
			caption.queue_redraw()
			await _frame("%s_%s_impact" % [id, side])
			game._tool_impact_queue.clear()
			game.impact_pending = false
			_stop_audio(game)
	sheet.save_png(ProjectSettings.globalize_path("res://artifacts/tool_facing/all_tools.png"))
	sheet.get_region(Rect2i(0, 0, 1440, 334)).save_png(ProjectSettings.globalize_path("res://artifacts/tool_facing/reference_turn.png"))
	var height: float = center.y - game.camera.unproject_position(game.shell.global_position + game.camera.global_basis.y * game.active_rock_radius).y
	await _capture_vertical(caption, center, Vector2(span, height))
	# Record a center swing with the edge facing into the screen.
	game.pickaxe.cancel_swing()
	game.pickaxe.set_tool("pickaxe")
	game.aim_position = center
	game._process(0)
	game.pickaxe.swing()
	var time := 0.0
	for phase: float in [0.0, 0.065, 0.09, 0.11, 0.12, 0.18, 0.27, 0.34]:
		game.pickaxe._process(phase - time)
		time = phase
		caption.text = "pickaxe / center swing / %.3f s" % phase
		caption.queue_redraw()
		await _frame("center_swing_%03d" % roundi(phase * 1000))
	game.pickaxe.cancel_swing()
	game._tool_impact_queue.clear()
	game.impact_pending = false
	finished = true
	print("TOOL_FACING_CAPTURE_OK frames=", files.size())
	_stop_audio(game)
	layer.queue_free()
	game.queue_free()
	await process_frame
	await process_frame
	quit()

func _capture_vertical(caption: Control, center: Vector2, half_size: Vector2) -> void:
	var idle_sheet := Image.create(1440, 1002, false, Image.FORMAT_RGBA8)
	var impact_sheet := Image.create(1440, 1002, false, Image.FORMAT_RGBA8)
	for entry: Dictionary in Tools.CATALOG:
		game.pickaxe.set_tool(entry.id)
		for row in 3:
			for column in 3:
				# Full direction grid for the pick; upper/lower views of other tools.
				if entry.id != "pickaxe" and (column != 1 or row == 1): continue
				# Keep comparison targets inside the ore silhouette and leave room
				# for the full hand-tool swing. Numerical checks also cover its edges.
				var offset := Vector2(column - 1, row - 1) * 0.55
				game.pickaxe.cancel_swing()
				game.aim_position = center + half_size * offset
				game._process(0)
				game.pickaxe._process(0)
				var label := "%s_direction_inner_%d_%d" % [entry.id, row, column]
				caption.text = "%s / %s / %s" % [entry.id, ["top", "middle", "bottom"][row], ["left", "center", "right"][column]]
				caption.queue_redraw()
				var frame := await _frame(label + "_idle")
				if entry.id == "pickaxe":
					frame.resize(480, 334, Image.INTERPOLATE_LANCZOS)
					idle_sheet.blit_rect(frame, Rect2i(0, 0, 480, 334), Vector2i(column * 480, row * 334))
				game.pickaxe.swing()
				game.pickaxe._process(float(game.pickaxe._strike_times[0]) + 0.0001)
				caption.text += " / impact"
				caption.queue_redraw()
				frame = await _frame(label + "_impact")
				if entry.id == "pickaxe":
					frame.resize(480, 334, Image.INTERPOLATE_LANCZOS)
					impact_sheet.blit_rect(frame, Rect2i(0, 0, 480, 334), Vector2i(column * 480, row * 334))
				game._tool_impact_queue.clear()
				game.impact_pending = false
				_stop_audio(game)
	idle_sheet.save_png(ProjectSettings.globalize_path("res://artifacts/tool_facing/all_directions.png"))
	impact_sheet.save_png(ProjectSettings.globalize_path("res://artifacts/tool_facing/all_directions_impact.png"))

func _frame(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png(ProjectSettings.globalize_path("res://artifacts/tool_facing/%s.png" % label))
	files.append(label)
	return frame
