extends "res://tests/validate_tools.gd"
## Economy, real UI confirmation, all six cursor tools, and bounded percussion.
const Tools = preload("res://scripts/main_tools.gd")
const Skills = preload("res://scripts/skill_tree.gd")
const Runtime = preload("res://scripts/mining_skills.gd")
const ToolAudio = preload("res://scripts/tool_audio_bank.gd")

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	_validate_model()
	_validate_audio()
	game = TestGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	await physics_frame
	await _validate_shop()
	await _validate_motion()
	_validate_area()
	await _validate_burst()
	_check(game.audio._players.size() == 14,"Tool switches and bursts retain the fixed voice pool")
	_stop_audio(game)
	# Let the real audio mixing thread release its deferred playback references.
	var deadline := Time.get_ticks_msec()+100
	while Time.get_ticks_msec() < deadline:
		await process_frame
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	ended = true
	print("MAIN_TOOLS_VALIDATION checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _validate_model() -> void:
	var model := Tools.new()
	var base := Skills.new().stats()
	var original := base.duplicate()
	_check(model.equipped == "pickaxe" and model.is_owned("pickaxe"),"First pickaxe is supplied for free")
	_check(not model.acquire("missing",9000).ok and not model.equip("drill"),"Unknown and unowned tools cannot be acquired/equipped")
	var previous_price := -1
	var previous_power := 0.0
	for entry: Dictionary in Tools.CATALOG:
		_check(entry.price > previous_price and entry.power > previous_power,"Prices and per-contact power increase in reference order")
		previous_price = entry.price
		previous_power = entry.power
		if entry.price > 0:
			_check(not model.acquire(entry.id,entry.price-1).ok,"An insufficient balance cannot acquire "+entry.id)
			var purchase := model.acquire(entry.id,entry.price+7)
			_check(purchase.ok and purchase.gold == 7 and model.equipped == entry.id,"Purchase debits once and auto-equips "+entry.id)
			_check(not model.acquire(entry.id,9999).ok,"Owned tool cannot be charged twice")
		var values := model.apply_to(base)
		_check(values.damage == entry.power and values.attack_speed == entry.speed and values.tool_radius == entry.radius,"Each tool composes its exact damage, speed and range modifiers")
		_check(base == original and values == model.apply_to(base),"Reapplication preserves skill data and cannot accumulate multipliers")
	_check(model.equip("pickaxe") and model.apply_to(base).damage == 1.0,"Free re-equip restores the baseline")
	var runtime := Runtime.new()
	model.equip("axe")
	runtime.configure(model.apply_to(base))
	var with_axe := 0
	var with_skill := 0
	# Repeat the exact same random sequence; axe can crit before the skill unlock.
	runtime.random.seed = 5123
	for i in 2000: with_axe += int(runtime.begin_attack(i).critical)
	var values := model.apply_to(base)
	values["critical"] = 1.0
	runtime.configure(values)
	runtime.random.seed = 5123
	for i in 2000: with_skill += int(runtime.begin_attack(i).critical)
	_check(with_axe > 0 and with_skill > with_axe,"Axe critical chance works standalone and adds to the critical skill")
	model.equip("pickaxe")
	runtime.configure(model.apply_to(base))
	var narrow := runtime.radius(0)
	model.equip("hammer")
	runtime.configure(model.apply_to(base))
	_check(is_equal_approx(runtime.radius(0),narrow*1.85),"Hammer multiplies the actual mining radius")

func _validate_audio() -> void:
	var hashes: Array[int] = []
	for entry: Dictionary in Tools.CATALOG:
		var bank: Dictionary = ToolAudio.BANKS[entry.id]
		var streams: Array = bank.hits+bank.ores+[bank["break"],bank.swing]
		_check(streams.size() == 7,"Each tool has three stone hits, two ore hits, fracture and motion")
		for stream: AudioStreamWAV in streams:
			_check(stream.mix_rate == 48000 and stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS,"Authored tool PCM imports as 48 kHz stereo 16 bit")
			var fingerprint := hash(stream.data)
			_check(not hashes.has(fingerprint) and stream.get_length() > 0.09,"Every tool sound is a distinct nonempty PCM waveform")
			hashes.append(fingerprint)
			var quiet := true
			for byte in stream.data.slice(stream.data.size()-64): quiet = quiet and byte == 0
			_check(quiet,"PCM ends at digital silence without a truncation click")

func _validate_shop() -> void:
	game.round_state.wallet_gold = int(Tools.CATALOG[1].price)
	game._open_upgrades()
	game.skill_ui.select_tab("tools")
	var display: Control = game.skill_ui.tools_panel
	await _click(display.get_price_tag_rect(1).get_center())
	_check(display.selected_index == 1 and game.round_state.wallet_gold == int(Tools.CATALOG[1].price),"Tool selection only opens the review")
	game.skill_ui._tab_buttons.skills.grab_focus()
	await _key(KEY_ENTER)
	_check(game.skill_ui.selected_tab == "skills" and game.round_state.wallet_gold == int(Tools.CATALOG[1].price),"Enter on a focused header tab cannot accidentally buy the reviewed tool")
	game.skill_ui.select_tab("tools")
	await _click(display.get_price_tag_rect(1).get_center())
	var skill_tab: Vector2 = game.skill_ui.get_tab_rect("skills").get_center()
	await _touch(skill_tab,true)
	await _touch(skill_tab,false)
	_check(game.skill_ui.selected_tab == "skills" and game.round_state.wallet_gold == int(Tools.CATALOG[1].price),"Touch can switch header tabs while a tool review is open")
	game.skill_ui.select_tab("tools")
	await _click(display.get_price_tag_rect(1).get_center())
	await _click(display.global_position+Vector2(8,8))
	_check(display.selected_index == -1 and not game.main_tools.is_owned("axe"),"Outside click cancels without spending")
	await _click(display.get_price_tag_rect(1).get_center())
	await _click(display.get_confirmation_rect().get_center())
	_check(game.round_state.wallet_gold == 0 and game.main_tools.equipped == "axe" and game.pickaxe.tool_id == "axe" and game.audio.tool_id == "axe","The real check button buys, equips, swaps geometry and swaps audio")
	await _click(display.get_confirmation_rect().get_center())
	_check(game.round_state.wallet_gold == 0,"Repeated confirmation cannot charge an equipped item")
	display.cancel_selection()
	await _click(display.get_price_tag_rect(2).get_center())
	_check(display._confirm.disabled,"Unaffordable tool has a disabled confirmation")
	await _joy(JOY_BUTTON_A)
	_check(not game.main_tools.is_owned("hammer"),"Controller cannot bypass the gold check")
	await _key(KEY_ESCAPE)
	_check(game.skill_ui.is_open and display.selected_index == -1,"Escape closes the tool review before the upgrade window")
	# Real touch selection and confirm, using owned baseline, including drag cancellation.
	await _touch(display.get_price_tag_rect(0).get_center(),true)
	await _touch(display.get_price_tag_rect(0).get_center(),false)
	_check(display.selected_index == 0,"Touch opens the actual tool review")
	var confirm: Vector2 = display.get_confirmation_rect().get_center()
	await _touch(confirm,true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = confirm+Vector2(0,-40)
	root.push_input(drag,true)
	await _touch(confirm,false)
	_check(game.main_tools.equipped == "axe","Dragging over the check does not equip")
	await _touch(confirm,true)
	await _touch(confirm,false)
	_check(game.main_tools.equipped == "pickaxe" and game.round_state.wallet_gold == 0,"Touch confirms free re-equipping of an owned tool")
	display.cancel_selection()
	await _click(display.get_price_tag_rect(1).get_center())
	await _joy(JOY_BUTTON_A)
	_check(game.main_tools.equipped == "axe" and game.round_state.wallet_gold == 0,"Controller confirms owned tool without spending")
	for dimensions: Vector2i in [Vector2i(360,800),Vector2i(800,450)]:
		root.size = dimensions
		await process_frame
		game._resize()
		_check(root.get_visible_rect().encloses(display.get_confirmation_rect()),"The review check stays fully on screen in portrait and small landscape")
		_check(display._detail_rect.encloses(display._hero_rect),"Responsive review contains its full 3D hero")
	var close: Vector2 = game.skill_ui._close.get_global_rect().get_center()
	await _touch(close,true)
	await _touch(close,false)
	_check(not game.skill_ui.is_open,"Touch can close the upgrade window from an open tool review")
	root.size = Vector2i(1152,800)
	await process_frame
	game._resize()
	_check(not game._tool_action("pickaxe"),"Closed upgrade window rejects purchase/equip commands")

func _validate_motion() -> void:
	var pointer := root.get_visible_rect().size*Vector2(0.53,0.48)
	var impacts := [0]
	var aligned := [true]
	game.pickaxe.impacted.connect(func():
		impacts[0] += 1
		var tip: Vector2 = game.camera.unproject_position(game.pickaxe.to_global(game.pickaxe.get_tip_local()))
		aligned[0] = aligned[0] and tip.distance_to(game.pickaxe.get_target_screen()) < 0.5
	)
	for entry: Dictionary in Tools.CATALOG:
		if not game.main_tools.is_owned(entry.id): game.main_tools.acquire(entry.id,int(entry.price))
		game.main_tools.equip(entry.id)
		game._apply_upgrade_stats()
		game.pickaxe.set_target(pointer)
		game.pickaxe._process(0.0)
		var retained: Node = game.pickaxe._visual
		var old := int(impacts[0])
		game.pickaxe.swing()
		for i in 60:
			game.pickaxe.set_target(pointer+Vector2(i*0.5,0))
			game.pickaxe._process(0.01)
		_check(impacts[0]-old == entry.burst and not game.pickaxe.is_swinging,"One activation yields the exact contact count for "+entry.id)
		_check(game.pickaxe._visual == retained and retained.tool_id == entry.id,"Animation retains its authored geometry without rebuilding "+entry.id)
		_check(game.audio._hits[0] == ToolAudio.BANKS[entry.id].hits[0],"Equipping selects preloaded tool PCM")
		if entry.id == "drill":
			_check(absf(retained.rotor.rotation.y) > 0.01,"The drill's actual helical bit rotates")
	_check(aligned[0],"All six rendered tips land at the live cursor at every emitted contact")
	var counts: Array[int] = []
	for id: String in ["pickaxe","drill"]:
		game.main_tools.equip(id)
		game._apply_upgrade_stats()
		var before := int(impacts[0])
		for frame in 120:
			if not game.pickaxe.is_swinging: game.pickaxe.swing()
			game.pickaxe._process(0.01)
		counts.append(int(impacts[0])-before)
		game.pickaxe.cancel_swing()
	_check(counts[1] >= counts[0]*2,"The drill actually delivers at least twice as many contacts in the same held-input interval")
	game.main_tools.equip("jackhammer")
	game._apply_upgrade_stats()
	game.pickaxe.swing()
	game.pickaxe._process(0.08)
	game.pickaxe._process(0.05)
	_check(game.pickaxe._visual.piston.position.y > 0.05,"The jackhammer chisel retracts between pulses")
	game.pickaxe.cancel_swing()
	game._tool_impact_queue.clear()
	game.impact_pending = false

func _validate_area() -> void:
	var center := root.get_visible_rect().size*0.5
	var candidate := {}
	for y in range(-180,201,36):
		for x in range(-180,201,36):
			var point := center+Vector2(x,y)
			var hit: Dictionary = game.ray_at(point)
			if hit.is_empty() or not game.chunks.has(hit.collider): continue
			game.main_tools.equip("pickaxe")
			game.mining_skills.configure(game.main_tools.apply_to(game.upgrades.stats()))
			var normal: Array[Dictionary] = game._area_targets(point,hit)
			game.main_tools.equip("hammer")
			game.mining_skills.configure(game.main_tools.apply_to(game.upgrades.stats()))
			var wide: Array[Dictionary] = game._area_targets(point,hit)
			if wide.size() > normal.size():
				candidate = {"aim":point,"hits":wide,"body":hit.collider}
				break
		if not candidate.is_empty(): break
	_check(not candidate.is_empty(),"The hammer reaches additional real surface pieces beyond the baseline radius")
	if candidate.is_empty(): return
	for body in game.chunks:
		body.health = 100
		body.max_health = 100
	game.main_tools.equip("hammer")
	game._apply_upgrade_stats()
	game._mine_at(candidate.aim)
	_check(is_equal_approx(candidate.body.health,100.0-float(Tools.CATALOG[2].power)),"Hammer primary damage uses its equipped power")
	for contact: Dictionary in candidate.hits:
		_check(is_equal_approx(contact.hit.collider.health,100.0-float(Tools.CATALOG[2].power)),"The hammer's wider range applies actual secondary damage")

func _validate_burst() -> void:
	var targets: Array[Dictionary] = []
	for body in game.chunks:
		var point: Vector2 = game.camera.unproject_position(body.mesh_instance.to_global(body.face_center))
		if not game._aim_over_hud(point) and game.ray_at(point).get("collider") == body:
			targets.append({"body":body,"screen":point})
	_check(not targets.is_empty(),"Real stone surface is available for percussion validation")
	if targets.is_empty(): return
	var target: Dictionary = targets[0]
	target.body.health = 100
	target.body.max_health = 100
	game.main_tools.equip("jackhammer")
	game._apply_upgrade_stats()
	game._wait_for_mine_release = false
	game.swing_cooldown = 0
	game.aim_position = target.screen
	game._request_swing()
	game.pickaxe._process(0.5)
	_check(game._tool_impact_queue.size() == 3,"A slow render frame preserves all three percussion contacts")
	game.swing_cooldown = 0
	game._request_swing()
	_check(not game.pickaxe.is_swinging,"An undrained burst prevents unbounded queued activations")
	for i in 3: game._physics_process(0.0)
	_check(is_equal_approx(target.body.health,100.0-3.0*float(Tools.CATALOG[3].power)) and game._tool_impact_queue.is_empty(),"Three queued contacts perform three actual raycast damage applications")
	game.swing_cooldown = 0
	game._request_swing()
	game.pickaxe._process(0.08)
	game._physics_process(0.0)
	var after_first: float = target.body.health
	game.round_state.remaining = 0.01
	game._advance_round(0.01)
	_check(not game.pickaxe.is_swinging and game._tool_impact_queue.is_empty(),"Deadline immediately cancels the remaining burst")
	game.pickaxe._process(0.5)
	game._physics_process(0.0)
	_check(target.body.health == after_first,"The remaining two pulses cannot damage stone after timeout")
	# Ownership and equipment survive the actual new-round path.
	game.round_state.phase = game.RoundModel.Phase.COMPLETE
	game._next_round()
	_check(game.main_tools.equipped == "jackhammer" and game.main_tools.is_owned("axe"),"The next mining round retains bought and equipped main tools")
	game.pickaxe.swing()
	game.pickaxe._process(0.5)
	game._spawn_rock(31871)
	_check(game._tool_impact_queue.is_empty() and not game.pickaxe.is_swinging,"Replacing a rock discards a pending burst instead of hitting the new rock")
	game.pickaxe.swing()
	game.pickaxe._process(0.5)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(game._tool_impact_queue.is_empty() and not game.pickaxe.is_swinging,"Losing focus clears queued burst contacts immediately")

func _touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event,true)
	await process_frame
