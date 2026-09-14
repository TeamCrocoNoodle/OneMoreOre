extends "res://tests/capture_tools.gd"
## GPU review of large, small, portrait, and live-resized UI using real Main.

func _initialize() -> void:
	_run.call_deferred()
	create_timer(90.0).timeout.connect(func():
		if not finished: _fail("Responsive capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
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
	game.round_state.wallet_gold = 32000000
	game.hud.set_wallet(32000000)
	game._process(0.0)
	game.hud._process(0.5)
	await physics_frame
	await create_timer(0.2).timeout
	var ui: Node = game.skill_ui
	var display: Control = ui.tools_panel
	for dimensions: Vector2i in [Vector2i(3840,2160),Vector2i(640,360),Vector2i(360,800),Vector2i(1080,2400)]:
		await _resize(dimensions)
		var tag := "responsive_%dx%d_" % [dimensions.x,dimensions.y]
		await _save(tag+"hud")
		game._open_upgrades()
		ui.select_tab("tools")
		display.select_kind("main")
		display.scroll_by(-100000)
		await _save(tag+"shelf")
		display.select_kind("aux")
		display.scroll_by(100000)
		await _save(tag+"aux")
		display._select_item(6)
		await _save(tag+"inspector")
		ui.close_tree()
		var rows: Array[Dictionary] = []
		for i in 10:
			rows.append({"kind":"gem" if i in range(1,8) else "stone", "tier":i-1 if i in range(1,8) else -1, "label":"보스 처치 보상" if i == 9 else "채굴 보너스" if i == 8 else "돌 조각" if i == 0 else game.hud.RARITY_NAMES[i-1], "count":999, "unit_gold":120000, "gold":12345678})
		game.hud.show_settlement({"rows":rows,"total":123456780,"wallet_before":32000000,"wallet_after":155456780})
		game.hud.finish_settlement()
		game.hud.set_upgrades_available(true)
		game.hud.set_auction_available(true)
		game.hud._clock += 2
		await _save(tag+"settlement")
		game.hud.auction_ui.show_offer(123456780)
		await _save(tag+"auction")
		game.hud.auction_ui.close()
		game.hud.begin_round(1,32000000)
	# Inspect an actual late skill and all equipped action controls in a compact view.
	await _resize(Vector2i(640,360))
	for node: Dictionary in game.upgrades.get_nodes():
		game.upgrades.purchase(node.id,1000000000)
	game._open_upgrades()
	ui.select_tab("skills")
	var longest := ""
	var length := 0
	for node: Dictionary in game.upgrades.get_nodes():
		if str(node.description).length() > length and game.upgrades.is_visible(node.id):
			longest = node.id
			length = str(node.description).length()
	ui._choose_node(longest)
	await _save("responsive_640x360_skill_detail")
	ui.close_tree()
	for item: Dictionary in game.aux_tools.get_catalog():
		game.aux_tools.acquire(item.id,32000000)
	game.auxiliary.hud.refresh()
	game.hud.set_boss_info({"danger":false,"accent":Color("dca75c"),"stage":6,"title":"이형의 심장","ratio":0.5,"status":"보스의 중심부를 파괴하세요","hint":"균열을 노려 채굴하세요"})
	game.hud.set_skill_status(12,3.2,4,1,4.2,123456)
	game.hud._canvas.queue_redraw()
	await _save("responsive_640x360_boss_hud")
	var file := FileAccess.open("res://artifacts/responsive_ui_captures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshots,"\t"))
	file.close()
	finished = true
	print("RESPONSIVE_CAPTURE_OK files=",files.size())
	_stop_audio(game)
	game.queue_free()
	await process_frame
	quit()
