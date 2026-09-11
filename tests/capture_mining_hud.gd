extends SceneTree
## Presentation fixture: all grades, maximum settlement, and portrait bounds.
const HUD = preload("res://scripts/mining_hud.gd")
const FLIGHT = preload("res://scripts/gem_flight_overlay.gd")
const GEM = preload("res://scripts/gem.gd")
var hud: CanvasLayer

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	var background := ColorRect.new()
	background.color = Color("102c37")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	hud = HUD.new()
	root.add_child(hud)
	hud.begin_round(1, 1250)
	hud.set_timer(24.0, 30.0, true)
	hud.set_stones(42)
	hud.set_gem_counts(PackedInt32Array([3, 1, 0, 0, 0, 0]))
	await _save("hud_mining_landscape")
	var report := {"rows": [{"kind": "stone", "tier": -1, "label": "돌 조각", "count": 42, "unit_gold": 1, "gold": 42}, {"kind": "gem", "tier": 0, "label": "일반", "count": 3, "unit_gold": 10, "gold": 30}, {"kind": "gem", "tier": 1, "label": "특별", "count": 1, "unit_gold": 50, "gold": 50}], "total": 122, "wallet_before": 1250, "wallet_after": 1372, "round_index": 1}
	hud.show_settlement(report)
	await create_timer(1.3).timeout
	await _save("hud_settlement_counting")
	hud.finish_settlement()
	await _save("hud_settlement_complete")
	root.size = Vector2i(600, 1000)
	# Keep the production project's 1440x1000 content size: only resize the
	# actual window, so portrait expand/stretch is exercised faithfully.
	await process_frame
	print("HUD_PORTRAIT_DIMENSIONS content=%s logical=%s window=%s stretch=%s" % [root.content_scale_size, root.get_visible_rect().size, root.size, root.get_final_transform().get_scale()])
	hud.begin_round(2, 1372)
	hud.set_timer(30, 30, false)
	await _save("hud_mining_portrait")
	var rows: Array[Dictionary] = []
	rows.append({"kind": "stone", "tier": -1, "label": "돌 조각", "count": 120, "unit_gold": 1, "gold": 120})
	var prices := [10, 50, 200, 1000, 5000, 25000]
	var total := 120
	for tier in 6:
		rows.append({"kind": "gem", "tier": tier, "label": HUD.RARITY_NAMES[tier], "count": 10, "unit_gold": prices[tier], "gold": prices[tier] * 10})
		total += prices[tier] * 10
	var maximum_report := {"rows": rows, "total": total, "wallet_before": 1372, "wallet_after": total + 1372, "round_index": 2}
	hud.show_settlement(maximum_report)
	hud.finish_settlement()
	await _save("hud_settlement_portrait_all")
	hud.show_settlement({"rows": [], "total": 0, "wallet_before": 0, "wallet_after": 0})
	hud.finish_settlement()
	await _save("hud_settlement_empty")
	await _capture_overlay()
	root.size = Vector2i(900, 600)
	await process_frame
	hud.show_settlement(maximum_report)
	hud.finish_settlement()
	await _save("hud_settlement_900x600_all")
	root.size = Vector2i(800, 450)
	await process_frame
	hud.begin_round(4, 1372)
	hud.set_timer(30, 30, false)
	await _save("hud_mining_800x450")
	hud.show_settlement(maximum_report)
	hud.finish_settlement()
	await _save("hud_settlement_800x450_all")
	hud.show_settlement(report)
	hud.finish_settlement()
	await _save("hud_settlement_800x450_starter")
	print("MINING_HUD_CAPTURE_OK files=12")
	quit()

func _capture_overlay() -> void:
	hud.begin_round(3, 1372)
	hud.set_timer(17, 30, true)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 0, 10)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = 60
	camera.current = true
	var world_env := WorldEnvironment.new()
	world_env.environment = Environment.new()
	world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.environment.ambient_light_color = Color("bad6e0")
	world_env.environment.ambient_light_energy = 0.4
	scene.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -32, 0)
	light.light_color = Color("fff1d9")
	light.light_energy = 2.2
	scene.add_child(light)
	var jewel := GEM.new()
	jewel.configure(1)
	scene.add_child(jewel)
	jewel.global_position = camera.project_position(hud.gem_target_screen(1), 3)
	jewel.scale = Vector3.ONE * hud.gem_target_diameter_screen() * camera.size / (root.get_visible_rect().size.y * jewel.bound_radius * 2)
	var flight := FLIGHT.new()
	root.add_child(flight)
	flight.setup(camera)
	flight.adopt(jewel)
	await _save("hud_actual_gem_above_panel")
	flight.release(jewel)
	jewel.queue_free()
	hud.pulse_gem(1, 1)
	await _save("hud_actual_gem_delivered")

func _save(tag: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://artifacts/" + tag + ".png")
