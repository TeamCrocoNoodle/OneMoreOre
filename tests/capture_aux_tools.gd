extends "res://tests/capture_tools.gd"
## Actual purchases, ray-driven pin hits, device feedback and half-value settlement.
const Aux = preload("res://scripts/aux_tools.gd")
var aux: Node3D

func _initialize() -> void:
	_run.call_deferred()
	create_timer(120).timeout.connect(func():
		if not finished: _fail("Auxiliary capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	game = CaptureGame.new()
	root.add_child(game)
	for node: Node in [game,game.hud,game.pickaxe,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	aux = game.auxiliary
	await _fresh()
	game.round_state.wallet_gold = 20000000 # Explicit review funds, never production save.
	game.hud.set_wallet(20000000)
	game._open_upgrades()
	await _tab("tools")
	var display: Control = game.skill_ui.tools_panel
	await _click(display.get_kind_rect("aux").get_center())
	await _save("aux_tools_cabinet_top")
	display.scroll_by(100000)
	await _save("aux_tools_cabinet_bottom")
	for i in Aux.CATALOG.size():
		display.cancel_selection()
		display._focus_item(i)
		await _click(display.get_price_tag_rect(i).get_center())
		await _save("aux_tools_detail_"+str(Aux.CATALOG[i].id))
		await _click(display.get_confirmation_rect().get_center())
		if not game.aux_tools.is_owned(Aux.CATALOG[i].id):
			_fail("Real auxiliary purchase failed: "+str(Aux.CATALOG[i].id))
			return
	display.cancel_selection()
	await _save("aux_tools_cabinet_owned")
	for dimensions: Vector2i in [Vector2i(360,800),Vector2i(800,450)]:
		await _resize(dimensions)
		display.scroll_by(-100000)
		await _save("aux_tools_shop_%dx%d_top" % [dimensions.x,dimensions.y])
		display.scroll_by(100000)
		await _save("aux_tools_shop_%dx%d_bottom" % [dimensions.x,dimensions.y])
		display._select_item(6)
		await _save("aux_tools_review_%dx%d" % [dimensions.x,dimensions.y])
		display.cancel_selection()
	await _resize(Vector2i(1152,800))
	game.skill_ui.close_tree()
	await _fresh()
	_nearest_signal()
	aux._process(0)
	await _save("aux_tools_live_ready")
	game._start_round()
	if not aux.fire_laser(): _fail("No actual laser contact")
	game._process(0)
	aux._process(0)
	await _save("aux_tools_laser")
	await _fresh()
	aux.spawn_pin()
	if not is_instance_valid(aux.pin):
		_fail("Pin missing")
		return
	await physics_frame
	aux._process(0)
	await _save("aux_tools_pin_in_ore")
	# Camera-only inspection of the real wedge and its real collision target.
	var camera_transform: Transform3D = game.camera.global_transform
	var camera_size: float = game.camera.size
	game.camera.global_position += aux.pin.global_position-game.shell.global_position
	game.camera.size = 3.3
	game.hud.hide()
	aux.hud.hide()
	game.pickaxe.hide()
	for step in 3:
		await physics_frame
		await physics_frame
		if not is_instance_valid(aux.pin): break
		var screen: Vector2 = game.camera.unproject_position(aux.pin.to_global(Vector3(0,0.34,0)))
		if game.ray_at(screen).get("collider") != aux.pin:
			_fail("Pin cannot be reached by the actual ray")
			return
		await _save("aux_tools_pin_drive_%d" % step)
		game._mine_at(screen)
	await _save("aux_tools_pin_split")
	game.camera.global_transform = camera_transform
	game.camera.size = camera_size
	game.hud.show()
	game.pickaxe.show()
	await _fresh()
	game._start_round()
	game.round_state.record_gem(0)
	game.displayed_gems[0] = 1
	game.hud.set_gem_counts(game.displayed_gems)
	aux.activate("crusher")
	aux._process(0.22)
	game._process(0.22)
	game.hud._process(0.22)
	await _save("aux_tools_crusher_intake")
	await create_timer(0.5).timeout # Real emergence tweens finish before cargo flight.
	for i in 12:
		game._update_collections(0.1)
		game.hud._process(0.1)
	game.round_state.advance(100)
	game._process(0)
	game.hud._process(12)
	aux._process(1)
	await _save("aux_tools_crusher_settlement")
	var sale: Dictionary = game.round_state.last_report.duplicate(true)
	await _fresh()
	aux.activate("detonator")
	game._process(0)
	aux._process(0.10)
	game.hud._process(0.1)
	await _save("aux_tools_detonator_blast")
	aux.advance(1.11)
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	aux._process(0)
	await _save("aux_tools_detonator_used")
	await _dense_settlement()
	await _fresh()
	for dimensions: Vector2i in [Vector2i(360,800),Vector2i(800,450)]:
		await _resize(dimensions)
		_nearest_signal()
		aux._process(0)
		await _save("aux_tools_hud_%dx%d" % [dimensions.x,dimensions.y])
	var report := {"test_credit_injected":20000000,"owned_auxiliary":game.aux_tools._owned,"main_equipped":game.main_tools.equipped,"crusher_report":sale,"captures":files,"snapshots":snapshots}
	var output := FileAccess.open("res://artifacts/aux_tools_report.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	finished = true
	print("AUX_TOOLS_CAPTURE_OK files=",files.size())
	_stop_audio(game)
	var deadline := Time.get_ticks_msec()+100
	while Time.get_ticks_msec() < deadline: await process_frame
	game.queue_free()
	await process_frame
	quit()

func _dense_settlement() -> void:
	await _fresh()
	var original: Dictionary = game.upgrade_stats.duplicate()
	# Explicit endgame stress settings; all proceeds still come from real gems.
	game.upgrade_stats.gem_spawn_bonus = 1.0
	game.upgrade_stats.rare_spawn_bonus = 1.0
	game.upgrade_stats.brilliant = 1.0
	game.upgrade_stats.brilliant_chance_bonus = 1.0
	game._spawn_rock(98873)
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	await physics_frame
	aux.activate("crusher")
	await create_timer(0.5).timeout
	for i in 12:
		game._update_collections(0.1)
		game.hud._process(0.1)
	game.round_state.advance(100)
	game._process(0)
	game.hud._process(12)
	aux._process(1)
	for dimensions: Vector2i in [Vector2i(1152,800),Vector2i(360,800),Vector2i(800,450)]:
		await _resize(dimensions)
		await _save("aux_tools_dense_settlement_%dx%d" % [dimensions.x,dimensions.y])
	game.upgrade_stats = original
	await _resize(Vector2i(1152,800))

func _fresh() -> void:
	game.focused = true
	game.using_controller = false
	aux.random.seed = 6188
	game.round_state.phase = game.RoundModel.Phase.COMPLETE
	game._next_round()
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	game.effects._process(2.0)
	game._process(0)
	aux.pin_roll_rock = game.rock_number
	aux._process(0)
	await physics_frame
	await physics_frame

func _nearest_signal() -> void:
	var closest := INF
	var point := Vector2.ZERO
	for contact: Dictionary in aux.exposed_contacts():
		game.aim_position = contact.screen
		aux.update_detector()
		if aux.detector_distance < closest:
			closest = aux.detector_distance
			point = contact.screen
	game.aim_position = point
	game.pickaxe.set_target(point)
	game.pickaxe._process(0)
	aux.update_detector()
