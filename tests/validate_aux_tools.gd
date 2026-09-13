extends "res://tests/validate_tools.gd"
## Exercises actual shop inputs, physics contacts, round accounting and tool lifetimes.
const Aux = preload("res://scripts/aux_tools.gd")
const Bank = preload("res://scripts/aux_audio_bank.gd")
const RoundState = preload("res://scripts/mining_round.gd")
const Skills = preload("res://scripts/skill_tree.gd")
var aux: Node3D

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	_validate_catalog_and_audio()
	_validate_ledger()
	game = TestGame.new()
	root.add_child(game)
	for node: Node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	aux = game.auxiliary
	await _fresh()
	var rock: int = game.rock_number
	_input_key(KEY_R)
	_check(game.rock_number == rock and game.chunks.size() == 74,"R cannot skip an ore before buying a crusher")
	await _shop()
	await _laser_and_sensors()
	await _pin()
	await _crusher()
	await _detonator()
	await _dense_ore()
	await _layouts()
	_check(aux.audio.players.size() == 5,"Repeated auxiliary actions retain five preloaded sound voices")
	_stop_audio(game)
	var deadline := Time.get_ticks_msec()+100
	while Time.get_ticks_msec() < deadline: await process_frame
	game.queue_free()
	await process_frame
	ended = true
	print("AUX_TOOLS_VALIDATION checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _validate_catalog_and_audio() -> void:
	var model := Aux.new()
	var stats := Skills.new().stats()
	var original := stats.duplicate()
	var previous := -1
	_check(Aux.CATALOG.size() == 7 and not model.acquire("missing",99999).ok,"Seven specified auxiliaries only; unknown purchase rejected")
	for entry: Dictionary in Aux.CATALOG:
		_check(entry.price > previous,"Auxiliary prices increase in reference order")
		previous = entry.price
		_check(not model.acquire(entry.id,entry.price-1).ok,"Insufficient funds cannot buy "+entry.id)
		var result := model.acquire(entry.id,entry.price+9)
		_check(result.ok and result.gold == 9 and model.is_owned(entry.id),"One purchase permanently activates "+entry.id)
		_check(not model.acquire(entry.id,99999).ok,"Duplicate auxiliary purchase cannot spend gold")
	_check(model._owned.size() == 7 and model.apply_to(stats).duration == 30+Aux.BEER_HEALTH,"All seven work together; beer adds its published maximum health")
	_check(model.apply_to(stats) == model.apply_to(stats) and stats == original,"Auxiliary stat composition never mutates or accumulates on skill values")
	stats.duration = 47.0
	_check(model.apply_to(stats).duration == 47+Aux.BEER_HEALTH,"Beer adds to upgraded maximum health")
	_check(Bank.CUES.size() == 18,"Every auxiliary has authored feedback in the eighteen-cue bank")
	var hashes: Array[int] = []
	for stream: AudioStreamWAV in Bank.CUES.values():
		_check(stream.mix_rate == 48000 and stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS,"Auxiliary sounds import as 48 kHz stereo PCM16")
		var fingerprint := hash(stream.data)
		_check(not hashes.has(fingerprint) and stream.get_length() >= 0.1,"Each synthesized sound is distinct and nonempty")
		hashes.append(fingerprint)
		var silent := true
		for byte in stream.data.slice(stream.data.size()-128): silent = silent and byte == 0
		_check(silent,"Every sound ends in exact digital silence")

func _validate_ledger() -> void:
	var ledger := RoundState.new()
	ledger.apply_stats({"gem_value_multiplier":1.5,"income_multiplier":1.2})
	ledger.wallet_gold = 57
	ledger.start()
	ledger.record_stone()
	var expected := 1
	for tier in RoundState.GEM_GOLD.size():
		var unit := roundi(RoundState.GEM_GOLD[tier]*1.5)
		ledger.record_gem(tier) # Already mined, always full value.
		ledger.record_gem(tier,2.0,0.5) # Brilliant bonus and skill value before recovery.
		ledger.record_gem(tier,1.0,0.5)
		var discount := unit + unit-roundi(unit*0.5)
		_check(ledger.gem_counts[tier] == 3 and ledger.crushed_counts[tier] == 2 and ledger.gem_discount[tier] == discount,"Mixed cargo retains per-gem recovery after brilliance and skill value")
		expected += unit*2+roundi(unit*0.5)
	ledger.advance(100)
	var report := ledger.begin_settlement()
	_check(report.subtotal == expected and report.total == roundi(expected*1.2),"Only crushed cargo loses value; income skills apply to the final correct subtotal")
	var sum := 0
	for row: Dictionary in report.rows:
		sum += int(row.gold)
		if row.kind == "gem":
			_check(row.crushed_count == 2 and "분쇄" in row.formula and "찬란함" in row.formula,"Settlement exposes the exact mixed-cargo deduction")
	_check(sum == report.total,"Animated settlement rows sum to the actual wallet payment")
	_check(ledger.commit_settlement() and not ledger.commit_settlement() and ledger.wallet_gold == 57+report.total,"Settlement pays the adjusted value exactly once")
	_check(ledger.can_auction(),"Crusher-adjusted earnings remain eligible for auction")
	var auction := ledger.begin_auction()
	_check(not auction.is_empty(),"Auction uses the completed adjusted settlement")
	ledger.commit_auction()
	_check(ledger.new_round() and ledger.gem_discount == PackedInt32Array([0,0,0,0,0,0,0]) and ledger.crushed_counts == ledger.gem_discount,"The next round clears all recovery deductions")

func _shop() -> void:
	game.round_state.wallet_gold = 20000000
	game._open_upgrades()
	game.skill_ui.select_tab("tools")
	var display: Control = game.skill_ui.tools_panel
	await _click(display.get_kind_rect("aux").get_center())
	_check(display.selected_kind == "aux" and display.get_catalog().size() == 7,"Real category button opens seven auxiliary shelf models")
	var models: Array[Node] = []
	_find_previews(display.cabinet_model,models)
	_check(models.size() == 7,"The auxiliary cabinet retains all seven authored 3D objects")
	for model in models: _check(_mesh_count(model) >= 5,"Each auxiliary has solid modeled parts")
	await _click(display.get_price_tag_rect(0).get_center())
	await _touch(display.get_kind_rect("main").get_center(),true)
	await _touch(display.get_kind_rect("main").get_center(),false)
	_check(display.selected_kind == "main" and display.selected_index == -1 and game.round_state.wallet_gold == 20000000,"Touch category switch cancels a pending purchase")
	display._kind_buttons.aux.grab_focus()
	await _joy(JOY_BUTTON_A)
	_check(display.selected_kind == "aux","Controller A can activate the focused auxiliary category")
	display._buttons[0].grab_focus()
	await _joy(JOY_BUTTON_DPAD_UP)
	_check(root.gui_get_focus_owner() == display._kind_buttons.aux,"D-pad Up exits the first shelf row to its category button")
	await _joy(JOY_BUTTON_DPAD_LEFT)
	await _joy(JOY_BUTTON_A)
	_check(display.selected_kind == "main","Controller can return from the shelf to the other tool category")
	await _click(display.get_kind_rect("aux").get_center())
	var expected := 20000000
	for i in Aux.CATALOG.size():
		display.cancel_selection()
		display._focus_item(i) # Native focus scrolls the fourth row into view.
		await _click(display.get_price_tag_rect(i).get_center())
		_check(display.selected_index == i and game.round_state.wallet_gold == expected,"Selecting an auxiliary opens review without spending")
		if i == 2:
			await _touch(display.get_confirmation_rect().get_center(),true)
			await _touch(display.get_confirmation_rect().get_center(),false)
		else: await _click(display.get_confirmation_rect().get_center())
		expected -= int(Aux.CATALOG[i].price)
		_check(game.aux_tools.is_owned(Aux.CATALOG[i].id) and game.round_state.wallet_gold == expected,"Real check confirmation buys "+str(Aux.CATALOG[i].id))
		_check(display._confirm.disabled and game.main_tools.equipped == "pickaxe","Purchased auxiliaries stay active without replacing the main tool")
		await _click(display.get_confirmation_rect().get_center())
		_check(game.round_state.wallet_gold == expected,"Owned auxiliary is never charged twice through the UI")
	_check(game.round_state.duration == 30+Aux.BEER_HEALTH and game.round_state.remaining == 30+Aux.BEER_HEALTH,"Real beer purchase immediately increases the next mining allowance")
	var atlas: SubViewport = aux.hud.atlas
	for i in 10: aux.hud.refresh()
	_check(atlas == aux.hud.atlas,"Repeated HUD refresh reuses one auxiliary model atlas")
	display.cancel_selection()
	game.skill_ui.close_tree()
	await process_frame

func _fresh() -> void:
	game.focused = true
	game.using_controller = false
	game.round_state.phase = RoundState.Phase.COMPLETE
	game._next_round()
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	game._wait_for_mine_release = false
	game.aim_position = root.get_visible_rect().size*0.5
	game._process(0)
	aux.pin_roll_rock = game.rock_number # Random appearance is checked separately.
	await physics_frame
	await physics_frame

func _laser_and_sensors() -> void:
	await _fresh()
	var duration: float = aux.laser_remaining
	aux.advance(200)
	_check(aux.laser_remaining == duration and aux.laser_shots == 0,"Laser neither counts down nor starts a round while waiting for the player")
	game._start_round()
	game.focused = false
	aux.advance(200)
	_check(aux.laser_remaining == duration,"Focus pause cannot accumulate automatic laser shots")
	game.focused = true
	var before: int = game.chunks.size()
	aux.laser_remaining = 0.01
	aux.advance(0.02)
	_check(game.chunks.size() == before-1 and aux.laser_shots == 1,"An elapsed laser interval instantly removes exactly one exposed piece")
	_check(aux.laser_remaining >= Aux.LASER_MIN and aux.laser_remaining <= Aux.LASER_MAX and aux._beam.visible,"Laser schedules its published random interval and draws a shot")
	_check(aux._beam.to_global(Vector3.UP*0.5).distance_to(aux._beam_end) < 0.001 and aux._beam.to_global(Vector3.DOWN*0.5).distance_to(aux._visuals.laser.muzzle.global_position) < 0.001,"Laser cylinder joins the actual muzzle and stone contact in world space")
	var timer: float = aux.laser_remaining
	game._spawn_rock()
	_check(aux.laser_remaining == timer and not aux._beam.visible,"New ore clears old laser beams without resetting its countdown")
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	await physics_frame
	var contacts: Array[Dictionary] = aux.exposed_contacts()
	_check(not contacts.is_empty(),"Actual ore supplies visible physics contacts")
	for selected: Dictionary in contacts:
		game.aim_position = selected.screen
		aux.update_detector()
		var nearest := INF
		for jewel in game.gems: nearest = minf(nearest,Vector3(selected.hit.position).distance_to(jewel.global_position))
		_check(aux.detector_valid and is_equal_approx(aux.detector_distance,nearest),"Detector measures the nearest actual embedded gem from the precise ray impact")
	var distance: float = aux.detector_distance
	game.main_tools.acquire("hammer",9999)
	game._apply_upgrade_stats()
	aux.update_detector()
	_check(is_equal_approx(aux.detector_distance,distance),"Hammer's wider attack radius cannot change the detector distance")
	game.aim_position = Vector2(2,2)
	aux.update_detector()
	_check(not aux.detector_valid,"Off-ore cursor suppresses the proximity signal")
	aux.hud.refresh()
	_check(aux.hud.remaining_gems == 4,"Xray counts all four still-hidden starting gems")

func _pin() -> void:
	await _fresh()
	for seed_value in 12:
		aux.random.seed = seed_value*317+7
		_check(aux.spawn_pin(),"Different random shared seams produce a usable pin")
		if not is_instance_valid(aux.pin): continue
		for depth in 3:
			await physics_frame
			await physics_frame
			var cap: Vector2 = game.camera.unproject_position(aux.pin.to_global(Vector3(0,0.34,0)))
			_check(game.ray_at(cap).get("collider") == aux.pin,"Random seam neighbours cannot occlude any of the three required pin hits")
			aux.pin.drive()
		aux._clear_pin()
		await physics_frame
		await physics_frame
	aux.pin_roll_rock = -1
	aux.random.seed = 9128
	aux.advance(0)
	var rolled: int = aux.pin_roll_rock
	aux._clear_pin()
	for i in 100: aux.advance(0)
	_check(rolled == game.rock_number and not is_instance_valid(aux.pin),"Pin appearance rolls only once per ore, never every frame")
	_check(aux.spawn_pin(),"Owned pin can appear in an exposed stone seam")
	if not is_instance_valid(aux.pin): return
	var origin: Vector3 = aux.pin.position
	var initial: int = game.chunks.size()
	for strike in 3:
		await physics_frame
		await physics_frame
		var point: Vector2 = game.camera.unproject_position(aux.pin.to_global(Vector3(0,0.34,0)))
		var contact: Dictionary = game.ray_at(point)
		_check(contact.get("collider") == aux.pin,"The pin cap remains physically targetable after driving it deeper")
		if contact.get("collider") != aux.pin: break
		_check(game._mine_at(point),"An actual mining ray strikes the pin")
		if strike < 2:
			_check(aux.pin.driven == strike+1 and aux.pin.position.distance_to(origin) > strike*0.1,"Each impact moves the forged wedge deeper into the ore")
	_check(not is_instance_valid(aux.pin) and game.chunks.size() < initial and not game.chunks.is_empty(),"Third pin hit removes nearby stones while leaving distant ore intact")
	await _fresh()
	_check(not is_instance_valid(aux.pin),"Changing ore removes any old splitting pin")

func _crusher() -> void:
	await _fresh()
	game._start_round()
	game.round_state.record_gem(0) # A gem mined from a prior ore keeps full value.
	game.round_state.record_stone()
	var old_rock: int = game.rock_number
	var before: Array = game.chunks.duplicate()
	var start := Time.get_ticks_usec()
	_input_key(KEY_R)
	var elapsed_ms := (Time.get_ticks_usec()-start)/1000.0
	print("AUX_BULK_MS crusher=",elapsed_ms)
	_check(game.chunks.is_empty() and game.gems.is_empty() and game.collecting_gems.size() == 4,"R grinds all current stone and recovers every embedded gem immediately")
	_check(game.round_state.ordinary_stones == 1 and game.round_state.gem_counts[0] == 5 and game.round_state.gem_discount[0] == 4*(RoundState.GEM_GOLD[0]-roundi(RoundState.GEM_GOLD[0]*Aux.CRUSHER_RECOVERY)) and game.round_state.gem_discount[1] == 0,"Crusher discounts four white starter gems only and awards no ground plain-stone gold")
	for body in before: _check(body.collision_layer == 0 and not body.visible,"Ground pieces lose collision and crack-light visibility immediately")
	_check(aux._ghosts.size() == 10 and game._tool_impact_queue.is_empty(),"Whole-ore grinding uses at most ten existing-mesh proxies and cancels stale pickaxe impacts")
	_check(not aux.activate("crusher"),"An active crusher cannot double-count ore")
	aux.advance(0.86)
	_check(game.rock_number == old_rock+1 and game.gems.size() == 4 and game.collecting_gems.is_empty(),"Crusher advances to a new ore and delivers pending gem flights once")
	_check(aux.crusher_remaining > 0 and not aux.can_activate("crusher"),"Crusher cooldown survives the next ore and prevents continuous free extraction")
	var cooldown: float = aux.crusher_remaining
	aux.configure()
	_check(aux.crusher_remaining == cooldown,"Reconfiguring owned tools cannot reset crusher cooldown")
	game.focused = false
	aux.advance(10)
	_check(aux.crusher_remaining == cooldown,"Focus loss pauses cooldown along with the mining timer")
	game.focused = true
	game.spawn_time = 1
	aux.advance(cooldown+.01)
	_check(aux.can_activate("crusher"),"Crusher becomes available after its full active cooldown")
	_check(game.displayed_gems[0] == 4 and game.displayed_gems[1] == 0,"Automatic next ore cannot lose the four recovered white gems' UI counts")
	await _fresh()
	game.using_controller = true
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_X
	joy.pressed = true
	game._input(joy)
	_check(game.chunks.is_empty(),"Controller X activates the crusher")
	game.round_state.remaining = 0.001
	game._physics_process(0.02)
	old_rock = game.rock_number
	aux.advance(3)
	_check(game.rock_number == old_rock and aux._skip_remaining < 0,"A deadline cancels pending auto-skip without creating free new ore")

func _detonator() -> void:
	await _fresh()
	var before: int = game.chunks.size()
	var start := Time.get_ticks_usec()
	_input_key(KEY_SPACE)
	print("AUX_BULK_MS detonator=",(Time.get_ticks_usec()-start)/1000.0)
	_check(aux.detonator_used and game.chunks.is_empty() and game.gems.is_empty(),"Space detonates every piece of the current ore")
	_check(game.round_state.ordinary_stones == before-4 and game.round_state.gem_discount == PackedInt32Array([0,0,0,0,0,0,0]),"Detonation preserves full gem value and ordinary stone proceeds")
	_check(not aux.activate("detonator"),"A second detonation cannot execute in the same mining round")
	aux.advance(1.11)
	_check(aux.detonator_used and not aux.can_activate("detonator"),"Detonator allowance survives the move to the next ore")
	await _fresh()
	_check(not aux.detonator_used and aux.can_activate("detonator"),"A new mining round restores exactly one detonation")
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_LEFT_STICK
	joy.pressed = true
	game._input(joy)
	_check(aux.detonator_used and game.using_controller,"Controller L3 activates the detonator without using the upgrade shortcut")
	await _fresh()
	aux.hud.refresh()
	game.set_process_input(true)
	await _touch(aux.hud.action_rect("detonator").get_center(),true)
	await _touch(aux.hud.action_rect("detonator").get_center(),false)
	game.set_process_input(false)
	_check(aux.detonator_used and game.touch_id == -1 and not game.impact_pending,"The actual touch action button detonates without a stray mining tap")
	_check(root.gui_get_focus_owner() != aux.hud.buttons.detonator,"Using an auxiliary releases its focus so controller A returns to mining")
	await _fresh()
	game.focused = false
	_check(not aux.activate("detonator") and not aux.fire_laser(),"Inactive application cannot extract resources")
	game.focused = true
	game.round_state.phase = RoundState.Phase.DRAINING
	_check(not aux.activate("crusher") and not aux.activate("detonator"),"Expired rounds block both manual auxiliaries")

func _layouts() -> void:
	await _fresh()
	for dimensions: Vector2i in [Vector2i(360,800),Vector2i(800,450),Vector2i(1152,800)]:
		root.size = dimensions
		await process_frame
		game._resize()
		game._process(0)
		aux.hud.refresh()
		var view: Rect2 = root.get_visible_rect()
		var crusher: Rect2 = aux.hud.action_rect("crusher")
		var blast: Rect2 = aux.hud.action_rect("detonator")
		_check(view.encloses(crusher) and view.encloses(blast) and not crusher.intersects(blast),"Both touch action buttons fit the real portrait/landscape stretch")
		_check(not crusher.intersects(game.hud._upgrades.get_global_rect()) and not blast.intersects(game.hud._upgrades.get_global_rect()),"Auxiliary actions do not overlap the existing upgrade entry")
		_check(game._aim_over_hud(crusher.get_center()) and game._aim_over_hud(blast.get_center()),"Auxiliary action rectangles block mining rays")
		game._open_upgrades()
		game.skill_ui.select_tab("tools")
		var display: Control = game.skill_ui.tools_panel
		display.select_kind("aux")
		display.scroll_by(100000)
		_check(view.intersects(display.get_price_tag_rect(6)),"The seventh auxiliary's price tag can be reached in every layout")
		display.scroll_by(-100000)
		_check(view.intersects(display.get_price_tag_rect(0)) and view.encloses(display.get_kind_rect("aux")),"First shelf and category navigation remain reachable")
		game.skill_ui.close_tree()
		var row := {"kind":"gem","count":36,"unit_gold":25000,"premium":900000,"discount":900000,"formula":"36개 × 25000 G · 찬란함 +900000 G · 분쇄 −900000 G"}
		var width: float = game.hud._info_rect.size.x-80
		var formula: Dictionary = game.hud._result_formula(row,width)
		_check(game.hud._font.get_string_size(formula.text,HORIZONTAL_ALIGNMENT_LEFT,-1,formula.size).x <= width,"Dense high-rarity settlement formula fits even the portrait row")

func _dense_ore() -> void:
	await _fresh()
	var original: Dictionary = game.upgrade_stats.duplicate()
	game.upgrade_stats.gem_spawn_bonus = 1.0
	game.upgrade_stats.rare_spawn_bonus = 1.0
	game.upgrade_stats.brilliant = 1.0
	game.upgrade_stats.brilliant_chance_bonus = 1.0
	game._spawn_rock(98873)
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	await physics_frame
	var count: int = game.gems.size()
	_check(count == int(game.ore_profile.gem_cap),"Stress ore fills its allowed internal mineral sockets")
	var expected := 0
	for jewel in game.gems:
		var unit: int = RoundState.GEM_GOLD[jewel.grade]
		expected += roundi((unit+roundi(unit*(float(jewel.get_meta("value_multiplier",1.0))-1.0)))*0.5)
	var lights: Array[Node3D] = []
	for body in game.chunks:
		if body.is_gem_cover:
			body.hit(1.0,body.mesh_instance.to_global(body.face_center))
			lights.append(body.light_node)
	var start := Time.get_ticks_usec()
	_check(aux.activate("crusher"),"Crusher can recover a completely filled, damaged high-rarity ore")
	print("AUX_DENSE_CRUSH_MS ",(Time.get_ticks_usec()-start)/1000.0," gems=",count)
	_check(game.collecting_gems.size() == count and game.gems.is_empty() and game.chunks.is_empty(),"Dense extraction records every gem and removes every stone")
	for light in lights: _check(not light.visible and not light.is_processing(),"Even active crack beams vanish in the mass-destruction frame")
	_check(game.effects.loose_chunks.is_empty() and aux._ghosts.size() == 10,"Dense ore still avoids per-stone fracture mesh construction")
	game.round_state.advance(100)
	var report: Dictionary = game.round_state.begin_settlement()
	_check(report.total == expected,"All rarities and brilliant gems receive exact half-value recovery at full capacity")
	game.upgrade_stats = original

func _input_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	game._input(event)

func _touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event,true)
	await process_frame
