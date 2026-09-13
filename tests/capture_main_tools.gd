extends "res://tests/capture_tools.gd"
## Real purchase / equip flow and six authored models. Review credit is explicit.
const Tools = preload("res://scripts/main_tools.gd")

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	game = CaptureGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.round_state.wallet_gold = 20000000
	game.hud.set_wallet(20000000)
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game._process(0.0)
	await physics_frame
	await create_timer(0.2).timeout
	game._open_upgrades()
	await _tab("tools")
	await create_timer(0.2).timeout
	var display: Control = game.skill_ui.tools_panel
	await _save("main_tools_cabinet")
	for i in Tools.CATALOG.size():
		display.cancel_selection()
		await _click(display.get_price_tag_rect(i).get_center())
		await _save("main_tools_detail_"+str(Tools.CATALOG[i].id))
		if i > 0:
			await _click(display.get_confirmation_rect().get_center())
		if game.main_tools.equipped != Tools.CATALOG[i].id:
			_fail("Real shop purchase did not equip "+str(Tools.CATALOG[i].id))
			return
		await _save("main_tools_owned_"+str(Tools.CATALOG[i].id))
	display.cancel_selection()
	await _save("main_tools_cabinet_owned")
	for dimensions: Vector2i in [Vector2i(360,800),Vector2i(800,450)]:
		await _resize(dimensions)
		await _save("main_tools_shelf_%dx%d" % [dimensions.x,dimensions.y])
		display._select_item(3)
		await _save("main_tools_detail_%dx%d" % [dimensions.x,dimensions.y])
		display.cancel_selection()
	await _resize(Vector2i(1152,800))
	game.skill_ui.close_tree()
	game._process(0.0)
	var aim := root.get_visible_rect().size*Vector2(0.53,0.53)
	for entry: Dictionary in Tools.CATALOG:
		game.main_tools.equip(entry.id)
		game._apply_upgrade_stats()
		game.aim_position = aim
		game.pickaxe.set_target(aim)
		game.pickaxe._process(0.0)
		await _save("main_tools_equipped_"+str(entry.id))
		game.pickaxe.swing()
		var first: float = game.pickaxe._strike_times[0]
		game.pickaxe._process(first/game.pickaxe.speed_multiplier+0.0001)
		await _save("main_tools_strike_"+str(entry.id))
		game.pickaxe.cancel_swing()
		game._tool_impact_queue.clear()
		game.impact_pending = false
	var report := {"test_credit_injected":20000000,"final_gold":game.round_state.wallet_gold,"catalog":display.get_catalog(),"captures":files,"snapshots":snapshots}
	var file := FileAccess.open("res://artifacts/main_tools_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	finished = true
	print("MAIN_TOOLS_CAPTURE_OK files=",files.size()," wallet=",game.round_state.wallet_gold)
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	quit()
