extends "res://tests/validate_tools.gd"
## Real ore geometry, economic boundaries, hidden contents, growth and tool compatibility.
const Progress = preload("res://scripts/ore_progression.gd")
const RoundState = preload("res://scripts/mining_round.gd")

func _initialize() -> void:
	_run.call_deferred()
	create_timer(90).timeout.connect(func():
		if not ended: quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	_economy()
	game = TestGame.new()
	# Isolate Gold/geometry growth; validate_bosses covers the additional campaign gates.
	game.campaign_enabled = false
	root.add_child(game)
	for node: Node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.focused = true
	var last_size := 0.0
	var last_pieces := 0
	for stage: Dictionary in Progress.STAGES:
		game.round_state.lifetime_mining_gold = stage.gold
		var start := Time.get_ticks_usec()
		await _spawn(12873)
		var info: Dictionary = game.ore_profile
		print("ORE_BUILD stage=",info.index," pieces=",game.chunks.size()," ms=",(Time.get_ticks_usec()-start)/1000.0)
		_check(info.id == stage.id and game.active_rock_radius == stage.radius,"Cumulative income selects the correct real ore profile")
		_check(game.chunks.size() == info.pieces and info.pieces > last_pieces and info.radius > last_size,"Every stage increases actual world radius and independent stone count")
		last_size = info.radius
		last_pieces = info.pieces
		_check(game.gems.size() == stage.gems.size(),"Ore receives its defined guaranteed gem composition")
		var layers := []
		for i in stage.layers.size(): layers.append(0)
		for chunk in game.chunks:
			layers[chunk.layer_index] += 1
			var expected: float = info.cover_health if chunk.is_gem_cover else Progress.Balance.stone_health(int(info.index),chunk.layer_index,chunk._stone_seed)
			_check(is_equal_approx(chunk.health,expected),"Every real chunk receives its stage, depth and gem-host health")
			_check(chunk._material.get_shader_parameter("ore_theme") == stage.theme,"Theme reaches every stone's actual material")
			_check(chunk.gem_socket_radius > 0 and chunk._containment_planes.size() > 3,"The themed geometry remains a solid with usable internal space")
		_check(layers == stage.layers,"Every stage has the prescribed nested layers")
		var hosts: Array[Node] = []
		var grades := []
		for jewel in game.gems:
			var host: Node = jewel.host_chunk.get_ref()
			grades.append(jewel.grade)
			_check(jewel.is_embedded and not jewel.visible and jewel.collision_layer == 0,"All stage rewards stay invisible and non-interactive until their host breaks")
			_check(host.layer_index > 0 and not hosts.has(host),"Every hidden gem has a distinct host below the outside shell")
			hosts.append(host)
		grades.sort()
		var expected: Array = stage.gems.duplicate()
		expected.sort()
		_check(grades == expected,"Guaranteed rarities match each stage's composition")
		# The initial outside shell must obstruct every hidden gem's direct sight line.
		for jewel in game.gems:
			var hit: Dictionary = game.ray_at(game.camera.unproject_position(jewel.global_position))
			_check(not hit.is_empty() and game.chunks.has(hit.collider) and hit.collider.layer_index == 0,"No hidden reward is exposed through a gap in the themed outer shell")
		var contacts: Array[Dictionary] = game.auxiliary.exposed_contacts()
		_check(not contacts.is_empty(),"All stage sizes remain targetable with real mining rays")
		var contact: Dictionary = contacts[contacts.size()/2]
		var health: float = contact.hit.collider.health
		game._mine_at(contact.screen)
		_check(contact.hit.collider.health < health,"Normal mining damages the themed geometry at its real hit position")
		game.round_state.phase = RoundState.Phase.READY
	await _upgrade_interaction()
	await _build_lifecycle()
	await _transition()
	_stop_audio(game)
	var deadline := Time.get_ticks_msec()+100
	while Time.get_ticks_msec() < deadline: await process_frame
	game.queue_free()
	await process_frame
	ended = true
	print("ORE_PROGRESSION_VALIDATION checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _economy() -> void:
	var ledger := RoundState.new()
	_check(Progress.stage_for(-8) == 0,"A fresh or negative progress input selects starter ore")
	for i in Progress.STAGES.size():
		var threshold: int = Progress.STAGES[i].gold
		_check(Progress.stage_for(threshold) == i,"Exact earned-gold threshold unlocks its stage")
		if i > 0: _check(Progress.stage_for(threshold-1) == i-1,"One gold short does not unlock the next stage")
		var profile := Progress.profile(threshold)
		profile.layers[0] = 999
		_check(Progress.profile(threshold).layers[0] != 999,"Profile callers cannot mutate the balance catalog")
	_check(Progress.stage_for(9000000000000) == 6 and Progress.profile(9000000000000).pieces == 512,"Final stage is bounded even with enormous cumulative income")
	ledger.wallet_gold = 900000
	_check(ledger.lifetime_mining_gold == 0,"Debug funds or wallet changes cannot advance ore progression")
	ledger.start()
	ledger.record_gem(2)
	ledger.advance(100)
	ledger.begin_settlement()
	_check(ledger.lifetime_mining_gold == 0,"Counting the sale preview does not grant progression early")
	ledger.commit_settlement()
	_check(ledger.lifetime_mining_gold == RoundState.GEM_GOLD[2] and not ledger.commit_settlement(),"Committed mining proceeds advance progression exactly once")
	ledger.wallet_gold -= 100
	_check(Progress.stage_for(ledger.lifetime_mining_gold) == Progress.stage_for(RoundState.GEM_GOLD[2]),"Spending gold cannot demote ore")
	ledger.begin_auction()
	ledger._pending_auction.delta = 400
	ledger._pending_auction.payout = 600
	ledger.commit_auction()
	_check(ledger.lifetime_mining_gold == RoundState.GEM_GOLD[2],"Auction gains do not cause abrupt ore difficulty jumps")
	ledger.new_round()
	ledger.start()
	ledger.record_gem(2,1,0.5)
	ledger.advance(100)
	ledger.begin_settlement()
	ledger.commit_settlement()
	_check(ledger.lifetime_mining_gold == RoundState.GEM_GOLD[2]+roundi(RoundState.GEM_GOLD[2]*.5),"Crusher proceeds advance progress by the amount actually earned")
	ledger.begin_auction()
	ledger._pending_auction.delta = -100
	ledger._pending_auction.payout = 0
	ledger.commit_auction()
	_check(ledger.lifetime_mining_gold == RoundState.GEM_GOLD[2]+roundi(RoundState.GEM_GOLD[2]*.5),"Auction loss cannot remove earned progress")
	_check(ledger.new_round() and ledger.lifetime_mining_gold == RoundState.GEM_GOLD[2]+roundi(RoundState.GEM_GOLD[2]*.5),"Cumulative income survives round changes")

func _spawn(seed_value: int) -> void:
	game._spawn_rock(seed_value)
	var remaining: float = game.round_state.remaining
	var slices := 0
	var worst := 0.0
	if game.ore_building:
		_check(not game._round_allows_mining(),"Partly assembled ore cannot be mined before its gems are sealed")
		var previous_phase: int = game.round_state.phase
		game.round_state.phase = RoundState.Phase.MINING
		game._advance_round(10)
		_check(game.round_state.remaining == remaining,"Building a large ore never consumes mining time")
		game.round_state.phase = previous_phase
	while game.ore_building:
		var start := Time.get_ticks_usec()
		game._advance_ore_build()
		worst = maxf(worst,(Time.get_ticks_usec()-start)/1000.0)
		slices += 1
		await process_frame
	if slices > 0: print("ORE_BUILD_SLICES count=",slices," max_ms=",worst)
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	game.hud.set_ore_progress(Progress.status(game.round_state.lifetime_mining_gold))
	await physics_frame
	await physics_frame

func _upgrade_interaction() -> void:
	game.round_state.phase = RoundState.Phase.READY
	game.round_state.lifetime_mining_gold = Progress.STAGES[5].gold
	var baseline: Dictionary = game.upgrade_stats.duplicate()
	game.upgrade_stats.gem_spawn_bonus = 1.0
	game.upgrade_stats.rare_spawn_bonus = 1.0
	game.upgrade_stats.resonance = 1
	game.upgrade_stats.resonance_chance_bonus = 1.0
	game.upgrade_stats.stone_health_reduction = 1
	await _spawn(77129)
	_check(game.gems.size() == Progress.STAGES[5].gem_cap,"Late-game socket bonuses remain bounded to the stage socket cap")
	for chunk in game.chunks:
		if chunk.is_gem_cover:
			_check(chunk.health == Progress.profile(Progress.STAGES[5].gold).cover_health,"Stage growth and stone health upgrades preserve gem host strength")
		else:
			_check(chunk.has_node("SpecialStoneMark") and chunk.get_meta("special_kind","") == "resonance","Incremental construction applies all special stone upgrades")
			_check(chunk.health >= Progress.Balance.STONE_HEALTH[5]-1 and chunk.health <= Progress.Balance.STONE_HEALTH[5]*1.5,"Stone health reduction also applies to incrementally built ores")
	var ancient := 0
	for jewel in game.gems:
		ancient += int(jewel.grade == 5)
		_check(jewel.grade >= 2,"Rare-mineral skills still improve later-stage gem rolls")
	_check(ancient >= 4,"A rare-upgrade roll never downgrades guaranteed ancient gems")
	game.aux_tools.acquire("detonator",100000000)
	game.auxiliary.configure()
	game.auxiliary.reset_round()
	var start := Time.get_ticks_usec()
	_check(game.auxiliary.activate("detonator"),"Detonator works on the largest ore")
	print("LARGEST_DETONATION_MS ",(Time.get_ticks_usec()-start)/1000.0)
	_check(game.chunks.is_empty() and game.gems.is_empty() and game.collecting_gems.size() == Progress.STAGES[5].gem_cap,"Largest ore can be removed without losing any embedded rewards")
	game.upgrade_stats = baseline
	game.auxiliary.clear_world()
	game.round_state.phase = RoundState.Phase.COMPLETE
	game._next_round()
	game.round_state.lifetime_mining_gold = 0
	await _spawn(12873)

func _build_lifecycle() -> void:
	game.round_state.phase = RoundState.Phase.READY
	game.round_state.lifetime_mining_gold = Progress.STAGES[5].gold
	game._spawn_rock(888)
	game._advance_ore_build()
	var retired: Array = game.chunks.duplicate()
	_check(not retired.is_empty() and game.ore_building,"Large ore creation yields with a partially assembled shell")
	game.focused = false
	game._advance_ore_build()
	_check(game.chunks.size() == retired.size(),"Focus loss pauses construction without losing the current cells")
	game.focused = true
	game.round_state.lifetime_mining_gold = Progress.STAGES[1].gold
	game._spawn_rock(999)
	for old in retired:
		_check(old.is_queued_for_deletion() and not old.visible and old.collision_layer == 0,"Replacing a partial build immediately retires all of its visible and physical cells")
	while game.ore_building:
		game._advance_ore_build()
		for jewel in game.gems:
			_check(not jewel.visible and jewel.collision_layer == 0,"Gems never flash or become interactive during multi-frame placement")
		await process_frame
	_check(game.chunks.size() == 102 and game.gems.size() == 7 and game.rock_seed == 999,"Cancelling a large build produces only the new ore and its own loot")
	for old in retired:
		_check(not is_instance_valid(old),"Cancelled ore cells are released on the following frame")
	game.round_state.lifetime_mining_gold = Progress.STAGES[5].gold
	game._spawn_rock(555)
	game._advance_ore_build()
	game.round_state.lifetime_mining_gold = 0
	await _spawn(12873)
	game._advance_ore_build()
	_check(not game.ore_building and game.chunks.size() == 74 and game.gems.size() == 4,"Returning to synchronous starter ore cannot resume an abandoned build")

func _transition() -> void:
	game.round_state.phase = RoundState.Phase.READY
	game.round_state.lifetime_mining_gold = int(Progress.STAGES[1].gold)-1
	await _spawn(12873)
	game.round_state.start()
	game.round_state.record_stone()
	game.round_state.advance(100)
	game.round_state.begin_settlement()
	game._finish_settlement()
	_check(game.ore_profile.index == 0 and game.hud._ore_progress.index == 1,"Settlement unlocks the next ore while leaving the completed rock stable")
	_check(not game.hud._ore_unlock.is_empty(),"A newly discovered ore is announced on the actual settlement HUD")
	game._next_round()
	while game.ore_building:
		game._advance_ore_build()
		await process_frame
	_check(game.ore_profile.index == 1 and game.chunks.size() == 102,"The next round actually spawns the larger unlocked ore")
	for size: Vector2i in [Vector2i(360,800),Vector2i(800,450)]:
		root.size = size
		await process_frame
		game._resize()
		game.hud._layout()
		var area: float = game.hud._ore_progress_width()
		var text_width: float = game.hud._bold.get_string_size("06  태고의 화산암",HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		text_width += game.hud._font.get_string_size("424조각 · 6겹",HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		_check(text_width < area-8,"Stage name and piece count remain separate on narrow screens")
