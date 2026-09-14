extends "res://tests/validate_tools.gd"
const Campaign = preload("res://scripts/boss_campaign.gd")
const Progress = preload("res://scripts/ore_progression.gd")
const RoundState = preload("res://scripts/mining_round.gd")
const Rarity = preload("res://scripts/gem_rarity.gd")
const BossAudio = preload("res://scripts/boss_audio_bank.gd")

func _initialize() -> void:
	_run.call_deferred()
	create_timer(180).timeout.connect(func():
		if not ended: push_error("BOSS_VALIDATION_TIMEOUT"); quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	_campaign_rules()
	game = TestGame.new()
	root.add_child(game)
	game.focused = true
	for node: Node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	await _rarity_gates()
	await _campaign_flow()
	await _regenerator()
	await _guards()
	await _weaknesses()
	await _wires()
	await _thorns()
	await _artillery()
	await _final_victory()
	_audio_contract()
	_stop_audio(game)
	await create_timer(.15).timeout
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(.10).timeout
	ended = true
	print("BOSS_VALIDATION checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _campaign_rules() -> void:
	var campaign := Campaign.new()
	_check(campaign.cleared == 0 and not campaign.won,"New campaigns begin with only white gems unlocked")
	_check(not campaign.eligible(0),"A fresh campaign cannot enter a boss")
	campaign.record_ore(0)
	_check(not campaign.eligible(0),"One ore is insufficient for the first provisional threshold")
	for i in range(1,int(Campaign.BOSSES[0].goal)): campaign.record_ore(0)
	_check(campaign.begin(0) and not campaign.begin(0),"Both cumulative and current-round conditions gate entry exactly once")
	_check(campaign.finish(false) == 0 and campaign.cleared == 0,"Defeat grants neither bounty nor rarity")
	_check(not campaign.eligible(0),"A failed attempt cannot be farmed again in the same round")
	campaign.new_round()
	_check(campaign.ore_clears[0] == int(Campaign.BOSSES[0].goal) and not campaign.eligible(0),"A retry retains cumulative clears but needs a fresh round clear")
	for i in range(1,int(Campaign.BOSSES[0].goal)): campaign.record_ore(0)
	_check(campaign.begin(0),"A new successful excavation permits a boss retry")
	_check(campaign.finish(true) == int(Campaign.BOSSES[0].reward) and campaign.cleared == 1 and campaign.finish(true) == 0,"Victory awards a fixed bounty once and unlocks green")
	_check(not campaign.eligible(0),"Previously defeated bosses are not offered again")
	for cleared in 8:
		var expected := mini(cleared,6)
		_check(Progress.profile(0,cleared).index == expected,"Boss victories advance the ore even below its former Gold threshold")
		_check(Progress.profile(999999999,cleared).index == expected,"Gold cannot skip an undefeated boss or overflow the final ore")
		var progress := Progress.status(0,cleared)
		_check(progress.index == expected and progress.earned == 0,"Progress display follows the boss unlock without inventing mining income")

func _rarity_gates() -> void:
	for stage in 7:
		game.campaign.cleared = stage
		game.round_state.lifetime_mining_gold = 999999999
		game.upgrade_stats.rare_spawn_bonus = 1.0
		game.round_state.phase = RoundState.Phase.READY
		game._spawn_rock(16840+stage)
		await _finish_build()
		_check(game.ore_profile.index == stage,"Even enormous earnings cannot skip an undefeated boss's ore gate")
		var highest := 0
		for jewel in game.gems:
			highest = maxi(highest,jewel.grade)
			_check(jewel.grade <= stage and jewel.is_embedded and not jewel.visible,"Rare skills cannot leak locked gems; all rewards remain sealed")
		_check(highest == stage,"Each unlocked ore can contain its highest available grade")
	_check(game.model_gallery._gem_textures.size() == 7,"Shared modeled UI includes the seventh crystal")
	var crystal: StaticBody3D = game.gems.back()
	_check(crystal.grade == 6 and bool(crystal._material.get_shader_parameter("exotic")),"Exotic gems use their authored opaline shader")
	game._start_round()
	var cover: StaticBody3D = crystal.get_parent().get_parent()
	_hit(cover,1)
	_hit(cover,cover.max_health*.90-1)
	_check(cover.light_node.current_tier == 6 and bool(cover.light_node._beam_material.get_shader_parameter("prismatic")),"A nearly exposed Exotic gem emits the new prismatic crack light")
	_hit(cover,cover.health)
	await create_timer(.45).timeout
	game._update_collections(1.0)
	_check(game.round_state.gem_counts[6] == 1 and game.hud.displayed_counts[6] == 1,"The actual Exotic model reaches its seventh tray slot and counts once")
	game._apply_upgrade_stats()

func _campaign_flow() -> void:
	game.campaign = Campaign.new()
	game.round_state = RoundState.new()
	game._apply_upgrade_stats()
	game.hud.begin_round(1,0)
	game._spawn_rock(18401)
	await _finish_build()
	game._start_round()
	game.campaign.ore_clears[0] = int(Campaign.BOSSES[0].goal)-2 # Two real clears exercise the transition after prior progress.
	# Keep actual earnings below the next ore threshold: the boss unlock is sufficient.
	for excavation in 2:
		for chunk in game.chunks.duplicate(): _hit(chunk,chunk.health)
		await create_timer(.45).timeout
		game._update_collections(1.0)
		_check(game.campaign.ore_clears[0] == int(Campaign.BOSSES[0].goal)-1+excavation,"Actual complete excavations increment campaign progress exactly once")
		game._check_exhausted()
		_check(game.campaign.ore_clears[0] == int(Campaign.BOSSES[0].goal)-1+excavation,"Repeated exhaustion checks cannot duplicate progress")
		game.round_state.remaining = 5
		game.completion_time = game.ORE_RESPAWN_DELAY - .01
		game._process(.02)
		await _finish_build()
	_check(game.boss.active and game.boss.stage == 0 and game.round_state.remaining == game.round_state.duration,"The normal completion transition enters the first boss and restores health")
	for generation in 3:
		for chunk in game.chunks.duplicate():
			if game.boss.active: _hit(chunk,chunk.health)
		game.boss.advance(1.61)
		for frame in 30: game.boss.advance(.01)
	_check(game.campaign.cleared == 1 and game.round_state.phase == RoundState.Phase.DRAINING,"A real boss completion leads to settlement without starting another ore")
	await _settle_and_check_next_ore(1)

func _settle_and_check_next_ore(expected_stage: int, victory: bool = true) -> void:
	var earned_before: int = game.round_state.lifetime_mining_gold
	var wallet_before: int = game.round_state.wallet_gold
	var round_before: int = game.round_state.round_index
	var expected: Dictionary = Progress.STAGES[expected_stage]
	game._begin_settlement()
	var sale: int = game.round_state.last_report.total
	game.hud.finish_settlement()
	await process_frame
	_check(game.round_state.phase == RoundState.Phase.COMPLETE and game.skill_ui.is_open == victory,"Boss victory settles and opens upgrades; defeat only settles")
	_check(game.round_state.lifetime_mining_gold == earned_before+sale and game.round_state.wallet_gold == wallet_before+sale,"Stage advancement pays only the actual sale and bounty")
	_check(game.round_state.lifetime_mining_gold < int(Progress.STAGES[expected_stage if victory else expected_stage+1].gold),"The transition regression stays below the next ore Gold threshold")
	var progress: Dictionary = game._progress_status()
	_check(progress.index == expected_stage and bool(progress.boss_gate) and progress.earned == earned_before+sale,"HUD unlock and boss progress agree before the next ore is built")
	if game.skill_ui.is_open: game.skill_ui.close_tree()
	game._next_round()
	await _finish_build()
	_check(game.round_state.round_index == round_before+1 and game.campaign.cleared == expected_stage,"Starting the next round retains exactly the defeated bosses")
	_check(game.ore_profile.index == expected_stage and game.ore_profile.id == expected.id and game.ore_profile.theme == expected.theme,"The next labor round builds the newly unlocked ore theme")
	var pieces := 0
	for count: int in expected.layers: pieces += count
	_check(is_equal_approx(game.active_rock_radius,float(expected.radius)) and game.chunks.size() == pieces,"The actual ore radius and full stone count advance with its stage")
	var highest := 0
	var sealed := true
	for crystal in game.gems:
		highest = maxi(highest,crystal.grade)
		sealed = sealed and crystal.grade <= expected_stage and crystal.is_embedded and not crystal.visible
	_check(highest == expected_stage and sealed,"The new ore hides its newly unlocked gems without leaking a higher rarity")
	_check(game.hud._ore_progress.index == expected_stage and bool(game.hud._ore_progress.boss_gate) and game.campaign.round_clears[expected_stage] == 0,"HUD and next-boss counting track the newly spawned ore")
	print("BOSS_ORE_TRANSITION stage=%d victory=%s gold=%d ore=%s pieces=%d rarity=%d" % [expected_stage+1,victory,game.round_state.lifetime_mining_gold,game.ore_profile.id,game.chunks.size(),highest])

func _fresh_boss(stage: int) -> void:
	if game.skill_ui.is_open: game.skill_ui.close_tree()
	game.boss.clear()
	game.campaign.cleared = stage
	game.campaign.new_round()
	game.campaign.ore_clears[stage] = Campaign.BOSSES[stage].goal
	game.campaign.round_clears[stage] = 1
	game.round_state = RoundState.new()
	for node: Dictionary in game.upgrades.get_nodes():
		if node.category == "ore": game.upgrades._owned[node.id] = true
	game.round_state.lifetime_mining_gold = Progress.STAGES[stage].gold
	game._apply_upgrade_stats()
	game.hud.begin_round(1,0)
	game.ore_profile = Progress.profile(game.round_state.lifetime_mining_gold,stage)
	game.round_state.start()
	game.round_state.remaining = 7
	game._pending_boss = true
	_check(game._try_spawn_boss(),"Production ore transition starts the eligible boss")
	_check(game.round_state.remaining == game.round_state.duration and game.ore_building,"Boss entry fully restores health before building")
	_check(game.upgrade_stats.gem_spawn_bonus == 0 and game.upgrade_stats.damage > 0,"Ore-branch effects pause during bosses while attack upgrades remain active")
	game._advance_round(5)
	_check(game.round_state.remaining == game.round_state.duration,"Boss preparation consumes no health")
	await _finish_build()
	_check(game.boss.active and game.boss.visual.body.get_child_count() > 0 and game.boss.visual.scenery.get_child_count() > 0,"Every boss has an authored body sculpture and stage set")
	_check(game.gems.is_empty(),"Boss bodies do not silently dispense a locked rarity")
	game.focused = false
	var before: float = game.boss.clock
	game.boss.advance(2)
	_check(game.boss.clock == before,"Focus loss pauses every boss mechanic")
	game.focused = true
	game._open_upgrades()
	_check(not game.skill_ui.is_open,"Upgrade purchases cannot bypass boss combat")
	game.aux_tools.acquire("crusher",game.aux_tools.definition("crusher").price)
	_check(game.aux_tools.is_owned("crusher"),"Boss auxiliary rejection uses an actually owned crusher")
	game.auxiliary.configure()
	_check(not game.auxiliary.can_activate("crusher"),"Crusher cannot skip a boss or its unlock conditions")

func _finish_build() -> void:
	while game.ore_building:
		game._advance_ore_build()
		await process_frame
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	await physics_frame
	await physics_frame

func _hit(chunk: StaticBody3D, damage: float, context: Dictionary = {}) -> void:
	var point: Vector3 = chunk.to_global(chunk.face_center)
	game._damage_chunk({"collider":chunk,"position":point,"normal":game.camera.global_basis.z},game.camera.unproject_position(point),context,damage)

func _regenerator() -> void:
	await _fresh_boss(0)
	var slot := 0
	var armor: StaticBody3D = game.boss._body(slot)
	var original_stats: Dictionary = game.upgrade_stats.duplicate()
	game.upgrade_stats.execute = 1.0
	game.mining_skills.configure(game.upgrade_stats)
	_hit(armor,-1.0)
	_check(not armor.destroyed and armor.health > armor.max_health*.8, "Even guaranteed first-hit execution cannot bypass boss armor")
	game.upgrade_stats = original_stats
	game.mining_skills.configure(original_stats)
	armor.health = armor.max_health
	for generation in 3:
		var chunk: StaticBody3D = game.boss._body(slot)
		_check(is_equal_approx(chunk.max_health,float(Campaign.BOSSES[0].health)*pow(.5,generation)),"Each regeneration halves maximum health")
		_hit(chunk,chunk.health)
		game.boss.advance(1.61)
	_check(game.boss._body(slot) == null and game.boss.cells[slot].regen_at < 0,"A stone regenerates at most twice")
	# Fully clearing all remaining generations must eventually win, including delayed cells.
	for pass_index in 4:
		for chunk in game.chunks.duplicate():
			if game.boss.active: _hit(chunk,chunk.health)
		game.boss.advance(1.61)
		for i in 30: game.boss.advance(.01)
	_check(game.campaign.cleared == 1 and not game.boss.active,"Clearing the final regeneration wins the first encounter")
	_check(game.round_state.boss_reward == int(Campaign.BOSSES[0].reward),"The first boss bounty is added to the real settlement ledger")

func _guards() -> void:
	await _fresh_boss(1)
	var protected: StaticBody3D
	for chunk in game.chunks:
		if chunk.get_meta("boss_protected",false): protected = chunk; break
	_check(protected != null,"The bastion has actual protected neighboring stones")
	var health: float = protected.health
	_hit(protected,999)
	_check(protected.health == health,"Shielded stones ignore direct damage")
	game.remove_with_auxiliary([protected])
	_check(protected.health == health,"Area auxiliary damage also respects protection")
	for slot in game.boss.guards.duplicate():
		var guard: StaticBody3D = game.boss._body(slot)
		_hit(guard,guard.health)
	_check(not protected.get_meta("boss_protected",true),"Destroying the guard stones removes immunity")
	_hit(protected,1)
	_check(protected.health == health-1,"Previously protected stones become mineable")
	for chunk in game.chunks.duplicate():
		if game.boss.active: _hit(chunk,chunk.health)
	await _settle_and_check_next_ore(2)

func _weaknesses() -> void:
	await _fresh_boss(2)
	var old: Array = game.boss.weak_slots.duplicate()
	var wounded: StaticBody3D = game.boss._body(old[0])
	_hit(wounded,wounded.max_health*.25)
	var remaining: float = wounded.health
	game.boss.advance(2.7)
	_check(game.boss.weak_slots.size() == 5 and game.boss.weak_slots != old,"Five weaknesses move to neighboring intact stones")
	_check(is_equal_approx(game.boss._body(game.boss.weak_slots[0]).health,remaining),"Moving a weakness preserves the damage already dealt to it")
	var guard := 0
	while game.boss.active and guard < 10:
		guard += 1
		var target: StaticBody3D = game.boss._body(game.boss.weak_slots[0])
		_hit(target,target.health)
		game.boss.advance(.02)
	_check(game.campaign.cleared == 3 and game.chunks.is_empty(),"Destroying all five moving weaknesses collapses the entire boss")
	await _settle_and_check_next_ore(3)

func _wires() -> void:
	await _fresh_boss(3)
	game._advance_round(5)
	_check(game.round_state.remaining == game.round_state.duration,"The bomb encounter uses its explicit sixty-second timer")
	game.boss.advance(1)
	var fast: int = game.boss.wire_effects.find("accelerate")
	var slow: int = game.boss.wire_effects.find("slow")
	var stop: int = game.boss.wire_effects.find("defuse")
	_check(not game.boss.cut_wire(stop) and game.boss.active,"The winning wire cannot bypass the boss's intact armor")
	for chunk in game.chunks.duplicate():
		if game.boss.bomb_armor_remaining() <= 0: break
		_hit(chunk,chunk.health)
	_check(game.boss.bomb_armor_remaining() == 0,"Breaking the required armor releases the defusal wires")
	# Dig through the covering stone, then strike the real wire with the same input ray.
	var wire: StaticBody3D = game.boss.visual.wires[fast]
	var point: Vector3 = wire.get_child(6).global_position
	var screen: Vector2 = game.camera.unproject_position(point)
	# Remaining covering stones still obstruct the physical wire after its seal releases.
	for excavation in 6:
		var contact: Dictionary = game.ray_at(screen)
		if contact.get("collider") == wire: break
		var blocker = contact.get("collider")
		if blocker is StaticBody3D and game.chunks.has(blocker): _hit(blocker,blocker.health)
		await physics_frame
		await physics_frame
	_check(game.ray_at(screen).get("collider") == wire,"Defusal wires have reachable physical click targets")
	game._mine_at(screen)
	_check(game.boss.wire_cut[fast],"Normal mining input cuts the selected physical wire")
	game.boss.advance(2)
	_check(is_equal_approx(game.boss.bomb_remaining,59),"The acceleration wire first pauses the timer")
	game.boss.advance(1)
	_check(is_equal_approx(game.boss.bomb_remaining,57),"After the pause the timer runs at double speed")
	game.boss.cut_wire(slow)
	game.boss.advance(2)
	_check(is_equal_approx(game.boss.bomb_remaining,56),"The slow wire temporarily changes the rate to one half")
	game.boss.cut_wire(stop)
	_check(game.campaign.cleared == 4 and not game.boss.active,"The correct wire immediately defuses the boss")
	await _settle_and_check_next_ore(4)
	await _fresh_boss(3)
	game.boss.advance(61)
	_check(not game.boss.active and game.campaign.cleared == 3 and game.round_state.boss_reward == 0,"Deadline expiry is a defeat without unlock or bounty")
	await _settle_and_check_next_ore(3,false)

func _thorns() -> void:
	await _fresh_boss(4)
	game.boss.spikes_out = true
	var health: float = game.round_state.remaining
	var context := {"count":2}
	_hit(game.chunks[0],.1,context)
	_hit(game.chunks[1],.1,context)
	_check(is_equal_approx(game.round_state.remaining,health-maxf(2.0,game.round_state.duration*.08)),"A multi-target manual swing pays spike damage once")
	game.boss.spike_next = .01
	game.boss.advance(.02)
	_check(not game.boss.spikes_out and game.boss.spike_next >= 3,"Retracted spikes leave a safe window of at least three seconds")
	health = game.round_state.remaining
	_hit(game.chunks[0],.1)
	_check(game.round_state.remaining == health,"Safe-window attacks do not damage the player")
	for chunk in game.chunks.duplicate():
		if game.boss.active: _hit(chunk,chunk.health)
	await _settle_and_check_next_ore(5)

func _artillery() -> void:
	await _fresh_boss(5)
	var stone: StaticBody3D = game.chunks[0]
	var health: float = stone.health
	_hit(stone,999)
	_check(stone.health == health,"Artillery body is immune while throwing")
	game.boss._throw_stone()
	var projectile: StaticBody3D = game.boss.projectiles[0].node
	_check(game.boss._stock().size() == game.boss.cells.size() and not projectile.has_meta("boss_slot"),"Projectiles are separate stones and cannot reduce the boss body to parry strength")
	game.boss.volley_timer = 99
	game.boss._advance_artillery(1.65)
	await physics_frame
	await physics_frame
	var screen: Vector2 = game.camera.unproject_position(projectile.to_global(projectile.gem_socket_center))
	_check(game.ray_at(screen).get("collider") == projectile,"The approaching projectile is a real ray-targetable stone in front of the ore")
	projectile.health = 1
	game._mine_at(screen)
	_check(game.boss.parry_count == 1 and not game.chunks.has(projectile),"Flying stones can be broken before reaching the player")
	game.boss._throw_stone()
	var player_health: float = game.round_state.remaining
	game.boss._advance_artillery(2.7)
	_check(game.round_state.remaining < player_health,"A stone reaching the camera damages player health")
	game.boss.volley_rest = true
	stone = game.boss._stock()[0]
	health = stone.health
	_hit(stone,1)
	_check(stone.health == health-1,"Body stones are vulnerable during the rest phase")
	game.boss.defeat()
	_check(game.campaign.cleared == 5,"An artillery defeat cannot unlock Exotic")
	await _settle_and_check_next_ore(5,false)
	await _fresh_boss(5)
	game.boss.volley_rest = true
	for chunk in game.chunks.duplicate():
		if game.boss.active: _hit(chunk,chunk.health)
	await _settle_and_check_next_ore(6)

func _final_victory() -> void:
	await _fresh_boss(6)
	for chunk in game.chunks.duplicate():
		if game.boss.active: _hit(chunk,chunk.health)
	_check(game.campaign.won and game.campaign.cleared == 7 and not game._round_allows_mining(),"Destroying the final provisional boss ends the campaign in victory")
	game._begin_settlement()
	game.hud._process(20)
	await process_frame
	_check(game.round_state.phase == RoundState.Phase.COMPLETE and game.round_state.wallet_gold >= int(Campaign.BOSSES[6].reward),"Final victory still pays its real one-time gold settlement")
	var previous_round: int = game.round_state.round_index
	game._next_round()
	game._open_upgrades()
	_check(game.round_state.round_index == previous_round and not game.skill_ui.is_open,"Victory cannot silently restart mining or open upgrades")
	_check(game.hud._campaign_won and not game.hud._replay.visible,"The final result UI has no next-mining action")
	game.hud._request_next()
	_check(game.hud.settlement_visible,"Controller confirmation cannot dismiss the terminal victory result")

func _audio_contract() -> void:
	_check(BossAudio.CUES.size() == 35 and game.boss.audio.players.size() == 8,"Seven bosses share a fixed eight-voice pool with five authored cues each")
	for id: String in BossAudio.CUES:
		var stream: AudioStreamWAV = BossAudio.CUES[id]
		_check(stream.mix_rate == 48000 and stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS,"Boss audio is uncompressed 48 kHz stereo PCM16")
