extends "res://tests/capture_tools.gd"
const MainTools = preload("res://scripts/main_tools.gd")
const AuxTools = preload("res://scripts/aux_tools.gd")

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
	game.spawn_time = 1
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.round_state.wallet_gold = 32000000 # Explicit capture credit.
	game.hud.set_wallet(game.round_state.wallet_gold)
	await physics_frame
	game._open_upgrades()
	game.skill_ui.select_tab("tools")
	var display: Control = game.skill_ui.tools_panel
	await _save("balance_main_prices")
	display._select_item(5)
	await _save("balance_gold_pickaxe")
	display.cancel_selection()
	display.select_kind("aux")
	display._select_item(3)
	await _save("balance_crusher_rules")
	display.cancel_selection()
	await _resize(Vector2i(360,800))
	display.select_kind("main")
	await _save("balance_prices_portrait")
	display._select_item(5)
	await _save("balance_gold_portrait")
	display.cancel_selection()
	display.select_kind("aux")
	display._select_item(3)
	await _save("balance_crusher_portrait")
	display.cancel_selection()
	await _resize(Vector2i(1152,800))
	game.skill_ui.close_tree()
	game.aux_tools.acquire("crusher",AuxTools.definition("crusher").price)
	game.auxiliary.configure()
	game._start_round()
	game.auxiliary.crusher_remaining = 27.2
	game.auxiliary.hud.refresh()
	await _save("balance_crusher_cooldown")
	finished = true
	print("BALANCE_CAPTURE_OK files=",files.size())
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await create_timer(.1).timeout
	quit()
