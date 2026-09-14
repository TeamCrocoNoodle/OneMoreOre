extends "res://tests/validate_tools.gd"
## Actual Control geometry and 3D projections under production canvas stretch.

func _run() -> void:
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	game = TestGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.round_state.wallet_gold = 32000000
	var hud: Node = game.hud
	var ui: Node = game.skill_ui
	var display: Control = ui.tools_panel
	var dimensions := [Vector2i(320,568), Vector2i(360,800), Vector2i(600,400), Vector2i(640,360), Vector2i(640,480), Vector2i(800,450), Vector2i(1152,800), Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(3440,1440), Vector2i(768,1024), Vector2i(1080,2400)]
	var rows: Array[Dictionary] = []
	for i in 10:
		rows.append({"kind":"gem" if i in range(1,8) else "stone", "tier":i-1 if i in range(1,8) else -1, "label":"보스 처치 보상" if i == 9 else "채굴 보너스" if i == 8 else "돌 조각" if i == 0 else hud.RARITY_NAMES[i-1], "count":999, "unit_gold":120000, "gold":12345678})
	var report := {"rows":rows, "total":123456780, "wallet_before":32000000, "wallet_after":155456780}
	var desktop_snapshot := {}
	for size: Vector2i in dimensions:
		root.size = size
		await process_frame
		await process_frame
		var bounds := root.get_visible_rect().grow(0.1)
		var label := str(size)
		_check(is_equal_approx(ui._scale,hud._scale), label+" uses shared UI scale")
		_check(hud._portrait == (size.x < size.y), label+" uses physical orientation")
		for card: Rect2 in hud._gem_cards:
			_check(bounds.encloses(Rect2(card.position*hud._scale,card.size*hud._scale)),label+" gem landing/card remains visible")
		hud.show_settlement(report)
		hud.finish_settlement()
		hud.set_upgrades_available(true)
		hud.set_auction_available(true)
		_check(bounds.encloses(Rect2(hud._modal_rect.position*hud._scale,hud._modal_rect.size*hud._scale)),label+" all ten result rows fit")
		_check(bounds.encloses(hud._replay.get_global_rect()),label+" settlement action fits")
		var actions: Array[Button] = [hud._replay,hud._upgrades,hud._auction]
		for index in actions.size():
			_check(bounds.encloses(actions[index].get_global_rect()),label+" settlement footer button visible")
			for next in range(index+1,actions.size()):
				_check(not actions[index].get_global_rect().intersects(actions[next].get_global_rect()),label+" settlement footer buttons never overlap")
		hud.auction_ui.show_offer(123456780)
		_check(bounds.encloses(hud.auction_ui._confirm.get_global_rect()),label+" auction confirmation fits")
		hud.auction_ui.close()
		ui.open_tree(32000000)
		_check(bounds.encloses(ui._close.get_global_rect()),label+" close fits")
		_check(not ui.get_tab_rect("skills").intersects(ui._close.get_global_rect()),label+" tabs and close do not overlap")
		ui.select_tab("skills")
		ui._choose_node("speed")
		_check(bounds.encloses(ui.get_detail_rect()),label+" selected skill details fit")
		_check(bounds.encloses(ui.get_confirmation_rect()),label+" skill confirmation fits")
		ui.select_tab("tools")
		for kind: String in ["main","aux"]:
			display.select_kind(kind)
			display.scroll_by(-100000)
			await process_frame
			var original_child: Node = display.cabinet_model.get_child(0)
			var model_aspect: float = display._model_width / (display._model_row_height*ceilf(display.get_catalog().size()/2.0)+52)
			_check(is_equal_approx(display._cabinet.size.x/display._cabinet.size.y,model_aspect),label+" "+kind+" shelf retains model aspect")
			for index in display.get_catalog().size():
				display._focus_item(index)
				var tag: Rect2 = display.get_price_tag_rect(index)
				_check(bounds.encloses(tag),label+" "+kind+" price tag accessible "+str(index))
				_check(display.get_item_rect(index).encloses(tag),label+" projected price tag matches button "+str(index))
				_check(tag.position.y >= display.global_position.y+38*display._scale-0.1,label+" tag clear of category tabs")
				if index in [0,display.get_catalog().size()-1]:
					display._select_item(index)
					await process_frame
					_check(bounds.encloses(display.get_confirmation_rect()),label+" tool confirmation fits")
					_check(not display._description.get_global_rect().intersects(display.get_confirmation_rect()),label+" description never overlaps purchase")
					_check(bounds.encloses(display._description.get_global_rect()),label+" description fits")
					_check(display._detail_rect.position.y >= 42,label+" tool title stays below category bar")
					_check(is_equal_approx(display._hero_rect.size.x,display._hero_rect.size.y),label+" tool preview remains square")
					display.cancel_selection()
			display.scroll_by(-100000)
			_check(original_child == display.cabinet_model.get_child(0),label+" scrolling retains cabinet geometry")
			if kind == "main" and size == Vector2i(1920,1080):
				desktop_snapshot = {"view":ui._view,"cabinet":display._cabinet.size}
			if kind == "main" and size == Vector2i(3840,2160):
				_check(ui._view.is_equal_approx(desktop_snapshot.view),"4K maintains Full HD relative UI size")
				_check(display._cabinet.size.is_equal_approx(desktop_snapshot.cabinet),"4K maintains Full HD relative shelf size")
		ui.close_tree()
	# Resize an open selected inspector without rebuilding any authored geometry.
	root.size = Vector2i(1920,1080)
	await process_frame
	ui.open_tree(32000000)
	ui.select_tab("tools")
	display.select_kind("main")
	display._select_item(5)
	var cabinet_child: Node = display.cabinet_model.get_child(0)
	var preview: Node = display._preview_model
	root.size = Vector2i(3840,2160)
	await process_frame
	_check(cabinet_child == display.cabinet_model.get_child(0),"Resolution-only resize retains all cabinet meshes")
	_check(preview == display._preview_model,"Resize retains inspected tool geometry")
	_check(display._preview_viewport.size.x > 512,"Large previews render at matching resolution")
	# Changing the project content scale (HiDPI/stretch) must not change the UI
	# in physical pixels or separate a projected tag from its clickable control.
	display.cancel_selection()
	display.scroll_by(-100000)
	var before: Rect2 = root.get_final_transform() * display.get_price_tag_rect(0)
	for stretch: Vector2i in [Vector2i(1920,1080),Vector2i(720,500),Vector2i(1440,1000)]:
		root.content_scale_size = stretch
		await process_frame
		var after: Rect2 = root.get_final_transform() * display.get_price_tag_rect(0)
		_check(after.position.distance_to(before.position) < 2 and after.size.distance_to(before.size) < 2,"Content stretch preserves physical shelf/tag placement")
	# Every late-game description must be reachable at the smallest landscape.
	for node: Dictionary in game.upgrades.get_nodes():
		game.upgrades.purchase(node.id,1000000000)
	root.size = Vector2i(640,360)
	await process_frame
	ui.refresh(32000000)
	ui.select_tab("skills")
	var longest := ""
	var longest_size := 0
	for node: Dictionary in game.upgrades.get_nodes():
		if not game.upgrades.is_visible(node.id): continue
		if str(node.description).length() > longest_size:
			longest = node.id
			longest_size = str(node.description).length()
		ui._cancel_selection()
		ui._zoom = 0.5
		ui._choose_node(node.id)
		_check(root.get_visible_rect().grow(0.1).encloses(ui.get_detail_rect()),"Long skill detail fits: "+node.id)
		_check(ui.get_detail_rect().position.y >= ui._header_height*ui._scale,"Skill detail remains below navigation: "+node.id)
	game.upgrades._owned.erase(longest)
	ui.refresh(32000000)
	ui._cancel_selection()
	ui._zoom = 1.55
	ui._choose_node(longest)
	await process_frame
	var description: RichTextLabel = ui._detail_body
	var scroll: VScrollBar = description.get_v_scroll_bar()
	_check(scroll.max_value > scroll.page,"A real long description scrolls in compact confirmation layout")
	var zoom: float = ui._zoom
	var wheel := InputEventMouseButton.new()
	wheel.position = description.get_global_rect().get_center()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel,true)
	await process_frame
	_check(scroll.value > 0 and is_equal_approx(ui._zoom,zoom),"Wheel scrolls the description without zooming the graph")
	scroll.value = 0
	var touch := InputEventScreenTouch.new()
	touch.index = 8
	touch.position = description.get_global_rect().get_center()
	touch.pressed = true
	root.push_input(touch,true)
	var drag := InputEventScreenDrag.new()
	drag.index = 8
	drag.position = touch.position - Vector2(0,60)
	drag.relative = Vector2(0,-60)
	root.push_input(drag,true)
	touch.pressed = false
	root.push_input(touch,true)
	await process_frame
	_check(scroll.value > 0 and ui.selected_id == longest,"Touch scroll preserves the pending purchase")
	scroll.value = 0
	var controller := InputEventJoypadButton.new()
	controller.button_index = JOY_BUTTON_DPAD_DOWN
	controller.pressed = true
	root.push_input(controller,true)
	await process_frame
	_check(scroll.value > 0 and ui.selected_id == longest,"Controller scroll preserves the pending purchase")
	controller.pressed = false
	root.push_input(controller,true)
	ui.close_tree()
	game.hud.begin_round(2,32000000)
	for item: Dictionary in game.aux_tools.get_catalog():
		game.aux_tools.acquire(item.id,32000000)
	game.auxiliary.hud.refresh()
	var aux_hud: Node = game.auxiliary.hud
	for dimensions2: Vector2i in [Vector2i(640,360),Vector2i(320,568),Vector2i(3840,2160)]:
		root.size = dimensions2
		await process_frame
		aux_hud.refresh()
		for id: String in ["crusher","detonator"]:
			_check(root.get_visible_rect().encloses(aux_hud.action_rect(id)),"Auxiliary actions fit "+str(dimensions2))
			_check(not aux_hud.action_rect(id).intersects(hud._upgrades.get_global_rect()),"Auxiliary controls clear the upgrade button")
		_check(not Rect2(24,210,300,88).intersects(aux_hud.xray_rect),"X-ray counter clear of boss/combo status")
	_stop_audio(game)
	game.queue_free()
	await process_frame
	ended = true
	print("RESPONSIVE_UI_VALIDATION checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
