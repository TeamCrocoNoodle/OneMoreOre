extends "res://tests/capture_tools.gd"
## Rendering fixtures explicitly inject eligibility; all bodies and hits are production code.
const Campaign = preload("res://scripts/boss_campaign.gd")
const Progress = preload("res://scripts/ore_progression.gd")
const RoundState = preload("res://scripts/mining_round.gd")
const Gem = preload("res://scripts/gem.gd")
var bosses: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(120).timeout.connect(func():
		if not finished: _fail("Boss capture timed out")
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
	game.focused = true
	await physics_frame
	game._process(0)
	game.hud._process(1)
	await _save("boss_campaign_starter_white")
	for stage in 7:
		await _start_boss(stage)
		await _save("boss_%02d_%s" % [stage+1,game.boss.info.id])
		bosses.append({"stage":stage,"id":game.boss.info.id,"pieces":game.chunks.size(),"test_injected_eligibility":true,"test_seed":game.rock_seed})
		game.shell.rotate_y(1.0)
		await _save("boss_%02d_rotated" % (stage+1))
		game.shell.rotate_y(-1.0)
		match stage:
			0:
				var chunk: StaticBody3D = game.chunks[0]
				_hit(chunk,chunk.health)
				game.boss.advance(1.65)
				await _save("boss_01_regeneration")
			2:
				game.boss.advance(2.7)
				await _save("boss_03_moved_weaknesses")
			3:
				for wire: StaticBody3D in game.boss.visual.wires:
					var screen: Vector2 = game.camera.unproject_position(wire.get_child(6).global_position)
					for excavation in 6:
						var contact: Dictionary = game.ray_at(screen)
						if contact.get("collider") == wire: break
						var blocker = contact.get("collider")
						if blocker is StaticBody3D and game.chunks.has(blocker): _hit(blocker,blocker.health)
						await physics_frame
						await physics_frame
				game.effects._process(2)
				await _save("boss_04_uncovered_wires")
				game.boss.cut_wire(game.boss.wire_effects.find("accelerate"))
				game.boss.advance(4)
				await _save("boss_04_accelerated")
				await _resize(Vector2i(360,800))
				await _save("boss_04_portrait")
				await _resize(Vector2i(1152,800))
			4:
				game.boss.spikes_out = true
				game.boss.visual.animate(0,true,false)
				game.boss._refresh_hud()
				await _save("boss_05_spikes")
			5:
				game.boss._throw_stone()
				game.boss.advance(1.50)
				await _save("boss_06_projectiles")
				game.boss.volley_rest = true
				game.boss._refresh_hud()
				await _save("boss_06_rest")
				await _resize(Vector2i(800,450))
				await _save("boss_06_landscape")
				await _resize(Vector2i(1152,800))
			6:
				for chunk in game.chunks.duplicate():
					if game.boss.active: _hit(chunk,chunk.health)
				game._begin_settlement()
				game.hud._process(20)
				game.effects._process(2)
				await _save("boss_07_final_victory")
	# Actual newly unlocked mineral, followed by an isolated close-up of the same model.
	game.campaign.cleared = 6
	game.round_state.lifetime_mining_gold = Progress.STAGES[6].gold
	game._next_round()
	await _build()
	game._process(0)
	game.hud._process(1)
	await _save("boss_exotic_ore")
	game.shell.hide()
	var exotic := Gem.new()
	exotic.configure(Gem.EXOTIC,0)
	exotic.collected = true
	game.add_child(exotic)
	exotic.global_position = game.camera.project_position(root.get_visible_rect().size*Vector2(.50,.47),4)
	exotic.scale = Vector3.ONE*6
	exotic.rotation = Vector3(-.05,-.28,-.08)
	await _save("boss_exotic_crystal")
	exotic.hide()
	game.shell.show()
	# Explicit maximum-row presentation fixture, using the real settlement model.
	var ledger := RoundState.new()
	ledger.apply_stats({"income_multiplier":1.2})
	ledger.start()
	ledger.record_stone()
	for grade in 7: ledger.record_gem(grade)
	ledger.record_boss_reward(Campaign.BOSSES[6].reward,"이형의 심장")
	ledger.phase = RoundState.Phase.DRAINING
	var receipt := ledger.begin_settlement()
	game.hud.set_boss_result("이형의 심장",true,true,6)
	game.hud.show_settlement(receipt)
	game.hud.finish_settlement()
	await _resize(Vector2i(800,450))
	await _save("boss_full_settlement_landscape")
	await _resize(Vector2i(360,800))
	await _save("boss_full_settlement_portrait")
	var output := FileAccess.open("res://artifacts/boss_capture_report.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"bosses":bosses,"captures":files,"snapshots":snapshots},"\t"))
	output.close()
	finished = true
	print("BOSS_CAPTURE_OK files=",files.size())
	_stop_audio(game)
	await create_timer(.15).timeout
	game.queue_free()
	await process_frame
	quit()

func _start_boss(stage: int) -> void:
	game.boss.clear()
	game.campaign.cleared = stage
	game.campaign.new_round()
	game.campaign.ore_clears[stage] = Campaign.BOSSES[stage].goal
	game.campaign.round_clears[stage] = 1
	game.round_state = RoundState.new()
	game.round_state.lifetime_mining_gold = Progress.STAGES[stage].gold
	game._apply_upgrade_stats()
	game.hud.begin_round(1,0)
	game.ore_profile = Progress.profile(game.round_state.lifetime_mining_gold,stage)
	game.round_state.start()
	game._pending_boss = true
	game._try_spawn_boss()
	await _build()
	game._process(0)
	game.hud._process(1)
	game.aim_position = root.get_visible_rect().size*Vector2(.65,.62)
	game.pickaxe.show()
	game.pickaxe.set_target(game.aim_position)
	game.pickaxe._process(0)

func _build() -> void:
	while game.ore_building:
		game._advance_ore_build()
		await process_frame
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	await physics_frame
	await physics_frame

func _hit(chunk: StaticBody3D, damage: float) -> void:
	var point: Vector3 = chunk.to_global(chunk.face_center)
	game._damage_chunk({"collider":chunk,"position":point,"normal":game.camera.global_basis.z},game.camera.unproject_position(point),{},damage)
