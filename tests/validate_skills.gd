extends SceneTree
## Reference graph, conditional skills, real world reactions and purchase UI.
const Skills = preload("res://scripts/skill_tree.gd")
const Runtime = preload("res://scripts/mining_skills.gd")
const Round = preload("res://scripts/mining_round.gd")
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_validate_graph()
	_validate_stamina_descriptions()
	_validate_combat()
	_validate_stamina_and_rewards()
	await _validate_game()
	print("SKILL_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _validate_stamina_descriptions() -> void:
	var model := Skills.new()
	_check(model.get_node("vitality").description == "최대 스태미나 +40" and model.get_node("vitality").effects.duration == 4.0, "Capacity tooltip scales presentation without changing its effect")
	_check(model.get_node("drain_1").description == "초당 스태미나 소모 -0.6" and model.get_node("drain_1").effects.drain_reduction == 0.06, "Drain reduction uses the same stamina scale")
	_check(model.get_node("spent_range").description.contains("스태미나가 120") and model.get_node("spent_threshold").description.ends_with("-40"), "Spent-stamina thresholds match the HUD units")
	_check(model.get_node("break_heal").description.contains("스태미나 3.5 회복") and model.get_node("break_heal_amount").description.ends_with("+3.5"), "Break-healing amounts retain their fraction")
	_check(model.get_node("recovery").description.contains("스태미나 5 회복") and model.get_node("recovery_more").description.ends_with("+5"), "Gem-healing amounts share the HUD scale")
	var healing_step: String = model.get_node("healing_amount_1").description
	_check(model.get_node("healing").description.contains("스태미나를 10") and healing_step.ends_with("%") and healing_step.get_slice("+", 1).trim_suffix("%").to_float() == 25.0, "Healing-stone amounts scale while percent upgrades remain percentages")
	_check(Main.AuxTools.definition("beer").headline == "최대 스태미나 +60", "Beer capacity display matches its unchanged six-point effect")

func _validate_graph() -> void:
	var model := Skills.new()
	var cells := {}
	var ids := {}
	var categories := {}
	for node: Dictionary in model.get_nodes():
		_check(not ids.has(node.id), "Unique id: " + str(node.id))
		_check(not cells.has(node.grid), "Unoccupied integer cell: %s %s (previous %s)" % [node.id, node.grid, cells.get(node.grid, "")])
		_check(node.grid is Vector2i and not str(node.icon).is_empty() and not str(node.description).is_empty(), "Grid/icon/description: " + str(node.id))
		ids[node.id] = true
		cells[node.grid] = node.id
		categories[node.category] = int(categories.get(node.category, 0)) + 1
	_check(ids.size() == 138, "All reference boxes plus the central starting pickaxe are present")
	# A connection must not look as though it also unlocks an unrelated card.
	for edge: Array in model.get_edges():
		var a := Vector2(model.get_node(edge[0]).grid)
		var b := Vector2(model.get_node(edge[1]).grid)
		var clear := true
		for cell: Vector2i in cells:
			if cells[cell] in edge:
				continue
			var p := Vector2(cell)
			var h := 0.28
			for segment: Array in [[Vector2(-h,-h), Vector2(h,-h)], [Vector2(h,-h), Vector2(h,h)], [Vector2(h,h), Vector2(-h,h)], [Vector2(-h,h), Vector2(-h,-h)]]:
				if Geometry2D.segment_intersects_segment(a, b, p + segment[0], p + segment[1]) != null:
					clear = false
		_check(clear, "Connection avoids unrelated cards: %s" % str(edge))
	var visible: Array[String] = []
	for id: String in ids:
		if model.is_visible(id):
			visible.append(id)
	visible.sort()
	_check(visible == ["income_2", "origin", "rich_ore", "speed", "vitality"], "Only the root and four reference branch entries are initially visible")
	_check(not model.purchase("critical", 999999).ok and not model.purchase("speed", 0).ok, "Hidden and unaffordable purchases are rejected")
	_check(model.stats().damage == 1.0 and model.stats().duration == 30.0, "The owned starting pickaxe preserves the initial 1 damage / 30 health")
	var gold := 1000000000
	var bought := 0
	while bought < ids.size() - 1:
		var progress := false
		for node: Dictionary in model.get_nodes():
			if model.can_purchase(node.id, gold):
				var purchase: Dictionary = model.purchase(node.id, gold)
				_check(purchase.ok and purchase.gold == gold - node.cost, "One exact debit: " + str(node.id))
				gold = purchase.gold
				_check(not model.purchase(node.id, gold).ok, "No duplicate purchase: " + str(node.id))
				bought += 1
				progress = true
		if not progress:
			break
	_check(bought == ids.size() - 1, "Every node is reachable through neighbor purchases")
	var s := model.stats()
	_check(s.duration == 46.0 and is_equal_approx(s.drain_rate, 0.82) and s.revive_count == 2, "Four max-health, three drain and two revival stages aggregate")
	_check(is_equal_approx(s.gem_spawn_bonus, 0.06) and is_equal_approx(s.rare_spawn_bonus, 0.12), "Five mineral and three rarity probability nodes aggregate")
	_check(is_equal_approx(s.healing_amount_bonus, 0.5) and is_equal_approx(s.crit_chance_bonus, 0.15), "Corrected healing branch and three critical chances aggregate")
	print("REFERENCE_GRAPH nodes=", ids.size(), " edges=", model.get_edges().size(), " categories=", categories)

func _runtime(changes: Dictionary) -> RefCounted:
	var value := Runtime.new()
	var s: Dictionary = Skills.new().stats()
	s.merge(changes, true)
	value.configure(s)
	value.random.seed = 91077
	return value

func _validate_combat() -> void:
	var r := _runtime({"combo": 1.0, "combo_speed": 1.0})
	for i in 9:
		r.on_break(false, false)
	_check(r.combo == 0, "Combo requires ten broken chunks")
	r.on_break(false, false)
	_check(r.combo == 1 and r.combo_remaining > 0, "Tenth break grants a timed combo")
	var early: float = r.combo_remaining
	for i in 50:
		r.on_break(false, false)
	_check(r.combo == 6 and r.combo_remaining < early and r.speed(30, 30) > 1.0, "Growing combo shortens its refresh deadline and unlocks speed above five stacks")
	var damage: Dictionary = r.damage({}, 1, false, false, 1.0, 1)
	_check(is_equal_approx(damage.damage, 1.06), "Six stacks add six percent base attack")
	for i in 10000: r.on_break(false,false)
	_check(r.combo > 1000 and is_equal_approx(r.damage({},1,false,false,1,1).damage,3.0), "Thousands of chained breaks retain the visible combo while damage stops at +200 percent")
	r.advance(10.0)
	_check(r.combo == 0 and r.combo_kills == 0, "Combo and partial stack progress expire")
	r = _runtime({"critical": 1.0, "crit_chance_bonus": 1.0, "extra": 1.0, "extra_chance_bonus": 1.0, "extra_count_bonus": 3.0, "extra_critical": 1.0})
	for i in 4:
		r.begin_attack(123)
	_check(r.extra_charges == 0, "Extra hits cannot trigger before the fifth basic attack")
	var context: Dictionary = r.begin_attack(123)
	_check(context.critical and r.extra_charges == 4, "Fifth critical grants all upgraded extra-hit charges")
	r.stats.crit_chance_bonus = -0.10
	for i in 4:
		context = r.begin_attack(123)
		_check(context.extra and context.critical, "Every charged extra inherits the qualifying fifth critical")
	_check(r.extra_charges == 0 and r.attacks == 5, "Extra hits do not recursively charge more extra hits")
	r = _runtime({"execute": 1.0, "first_damage": 0.3, "ore_damage": 0.25, "finisher": 1.0, "crowd": 1.0, "streak": 1.0})
	r.begin_attack(71)
	damage = r.damage({}, 71, true, true, 0.2, 12)
	_check(damage.execute and is_equal_approx(damage.damage, 2.35), "First/ore/low-health/capped crowd bonuses combine before execution")
	_check(not r.damage({}, 71, false, true, 0.2, 1).execute, "Execution never rolls on previously hit stone")
	r.begin_attack(71)
	_check(r.streak == 1 and is_equal_approx(r.damage({}, 71, false, false, 1, 1).damage, 1.08), "Consecutive direct target increases damage")
	r.begin_attack(99)
	_check(r.streak == 0, "Changing direct target resets focus stacks")
	r = _runtime({"low_health": 1.0, "spent_range": 1.0, "gem_buff": 1.0, "gem_pickup_gold": 4, "recovery_per_gem": 2.0})
	_check(r.speed(5, 30) > r.speed(30, 30) and r.radius(15) > r.radius(0), "Low remaining health and spent-health threshold affect separate stats")
	var reward: Dictionary = r.on_gem()
	_check(reward.gold == 4 and reward.heal == 2.0 and r.buff in [0, 1, 2] and r.buff_remaining == 5.0, "Gem grants gold, healing and one timed blessing")
	r.advance(5.1)
	_check(r.buff == -1, "Blessing expires")
	r = _runtime({"gold_drop": 1.0, "drop_chance_bonus": 1.0, "break_heal": 1.0, "break_heal_chance_bonus": 1.0, "crit_gold": 3, "execute_gold": 5})
	reward = r.on_break(true, true)
	_check(reward.gold == 11 and is_equal_approx(reward.heal,0.35), "Independent drop, critical, execution and heal rewards accumulate once")
	r.reset_round()
	_check(r.attacks == 0 and r.extra_charges == 0 and r.combo == 0, "New rounds clear temporary combat state")

func _validate_stamina_and_rewards() -> void:
	var session := Round.new()
	session.apply_stats({"drain_rate": 0.5, "revive_count": 2, "revive_fraction": 0.2, "income_multiplier": 1.2, "golden_chance": 1.0, "golden_pity": 0.02})
	session.golden_failures = 4
	session.start()
	for i in 3:
		session.record_stone()
	session.record_gem(0, 1.5)
	session.record_bonus_gold(7)
	_check(not session.advance(60) and session.remaining == 6 and session.revives_used == 1 and session.spent == 30, "Slower drain and first revival preserve exact spent health")
	_check(not session.advance(12) and session.revives_used == 2 and session.remaining == 6, "Second revival is independent of the first")
	_check(session.advance(12) and session.phase == Round.Phase.DRAINING, "Exhausting the last life enters settlement exactly once")
	var report: Dictionary = session.begin_settlement()
	_check(report.total == 80 and report.golden_day and report.subtotal == 26, "(3 stone + 23 brilliant gem + 7 bonus) × 1.2 × 2 = 80 Gold")
	var sum := 0
	for row: Dictionary in report.rows:
		sum += int(row.gold)
	_check(sum == report.total and session.golden_failures == 0, "Visible rows reconcile and winning resets pity")
	var state := session.reward_random.state
	_check(session.begin_settlement().total == 80 and session.reward_random.state == state, "Reopening settlement cannot reroll golden day")
	_check(session.commit_settlement() and not session.commit_settlement() and session.wallet_gold == 80, "Payment is idempotent")
	session.new_round()
	_check(session.revives_used == 0 and session.spent == 0 and session.remaining == 30 and session.bonus_gold == 0, "Only a new round restores lives and clears cargo")
	session.apply_stats({"golden_chance": 0.000001, "golden_pity": 0.01})
	session.reward_random.seed = 343
	session.start()
	session.record_stone()
	session.advance(30)
	report = session.begin_settlement()
	_check(not report.golden_day and session.golden_failures == 1, "A failed eligible settlement increases pity")

func _validate_game() -> void:
	root.size = Vector2i(1152, 800)
	var game := Main.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pickaxe.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	await physics_frame
	await process_frame
	game.round_state.wallet_gold = 500
	game._open_upgrades()
	await process_frame
	_check(game.skill_ui.get_visible_node_ids().size() == 5, "Real UI respects the initial fog of undiscovered nodes")
	for dimensions: Vector2i in [Vector2i(360, 800), Vector2i(800, 450), Vector2i(1152, 800)]:
		root.size = dimensions
		await process_frame
		var ui: Node = game.skill_ui
		for id: String in ui.get_visible_node_ids():
			var card: Rect2 = ui._node_rects[id]
			_check(card.position.x >= 0 and card.end.x <= ui._view.x and card.position.y >= ui._header_height + 50 and card.end.y <= ui._view.y, "Initial frontier fits below the header at %s: %s" % [dimensions, id])
	var initial_point: Vector2 = game.skill_ui.get_node_screen("speed")
	var hover := InputEventMouseMotion.new()
	hover.position = initial_point
	root.push_input(hover, true)
	await process_frame
	await _click(initial_point)
	_check(game.skill_ui.selected_id == "speed" and game.round_state.wallet_gold == 500, "Node click only opens the check button")
	await _click(game.skill_ui.get_node_screen("vitality"))
	_check(game.skill_ui.selected_id.is_empty() and game.round_state.wallet_gold == 500, "Another click cancels without spending")
	await _click(game.skill_ui.get_node_screen("speed"))
	await _click(game.skill_ui.get_confirmation_rect().get_center())
	_check(game.upgrades.is_unlocked("speed") and game.round_state.wallet_gold == 440 and is_equal_approx(game.upgrade_stats.attack_speed, 1.16), "The actual confirmation applies gameplay and debits Gold")
	_check(game.skill_ui.get_visible_node_ids().has("reach") and not game.skill_ui.get_visible_node_ids().has("critical"), "Purchase reveals exactly the next graph frontier")
	game.skill_ui.close_tree()
	game.round_state.apply_stats({"drain_rate": 0.5})
	game._process(0.0)
	_check(game.round_state.remaining == 30.0 and game.round_state.seconds_remaining() == 60.0 and game.hud.stamina_text() == "300 / 300", "Slower drain extends mining time without inflating the displayed stamina capacity")
	# Isolate deterministic world reactions from independently tested chance rolls.
	game.upgrade_stats = Skills.new().stats()
	game.mining_skills.configure(game.upgrade_stats)
	game.round_state.apply_stats(game.upgrade_stats)
	game._spawn_rock(98173)
	game.spawn_time = 1.0
	game._start_round()
	game.round_state.remaining = 15.0
	var source: StaticBody3D = game.chunks[0]
	source.configure_special("resonance")
	source.max_health = 20
	source.health = 20
	var health_before := {}
	for chunk in game.chunks:
		health_before[chunk.get_instance_id()] = chunk.health
	var point: Vector3 = source.to_global(source.face_center)
	game._damage_chunk({"collider": source, "position": point, "normal": source.direction}, Vector2(400, 350))
	_check(not game._reactions.is_empty(), "A real resonance hit queues adjacent damage")
	game._drain_reactions()
	var neighbors_damaged := 0
	for chunk in game.chunks:
		if chunk != source and chunk.health < float(health_before[chunk.get_instance_id()]):
			neighbors_damaged += 1
	_check(neighbors_damaged > 0 and neighbors_damaged <= 3, "The real world applies at most three reaction targets per frame")
	game._reactions.clear()
	var executed: StaticBody3D = game.chunks[3]
	executed.configure_special("resonance")
	executed.health = 1000000.0
	executed.max_health = executed.health
	executed.impact_count = 0
	game.upgrade_stats.execute = 1.0
	game.mining_skills.configure(game.upgrade_stats)
	var execution_context := {}
	point = executed.to_global(executed.face_center)
	game._damage_chunk({"collider":executed,"position":point,"normal":executed.direction},Vector2(400,350),execution_context)
	_check(executed.destroyed and is_equal_approx(float(execution_context.primary_damage),1.0), "Execution destroys its own million-health target without inflating primary shock damage")
	for reaction: Dictionary in game._reactions:
		_check(float(reaction.damage) <= 1.0, "Execution cannot copy a target's full health into neighboring resonance damage")
	game._reactions.clear()
	game.upgrade_stats.execute = 0.0
	game.mining_skills.configure(game.upgrade_stats)
	var healer: StaticBody3D = game.chunks[1]
	healer.configure_special("healing")
	healer.health = 0.25
	point = healer.to_global(healer.face_center)
	var before: float = game.round_state.remaining
	game._damage_chunk({"collider": healer, "position": point, "normal": healer.direction}, Vector2(400, 350))
	_check(game.round_state.remaining == before + 1.0, "A real healing chunk restores stamina on destruction")
	var gold_chunk: StaticBody3D = game.chunks[2]
	gold_chunk.configure_special("gold_stone")
	gold_chunk.health = 0.25
	point = gold_chunk.to_global(gold_chunk.face_center)
	game._damage_chunk({"collider": gold_chunk, "position": point, "normal": gold_chunk.direction}, Vector2(400, 350))
	_check(game.round_state.bonus_gold == 90, "A real gold chunk adds its gold once to the round ledger")
	var bomb: StaticBody3D = game.chunks[3]
	bomb.configure_special("bomb")
	bomb.health = 0.25
	point = bomb.to_global(bomb.face_center)
	game._damage_chunk({"collider": bomb, "position": point, "normal": bomb.direction}, Vector2(400, 350))
	_check(not game._reactions.is_empty(), "Destroying a bomb queues real neighboring damage")
	game._spawn_rock(98174)
	_check(game._reactions.is_empty() and game.round_state.remaining == before + 1.0, "Changing rocks clears reactions without resetting round stamina")
	# Isolate rare-roll upgrades on starter ore; boss tests cover campaign growth and rank caps.
	game.campaign_enabled = false
	game.upgrade_stats.rare_spawn_bonus = 1.0
	game.upgrade_stats.brilliant = 1.0
	game.upgrade_stats.brilliant_chance_bonus = 1.0
	game.upgrade_stats.gem_spawn_bonus = 1.0
	game._spawn_rock(98175)
	var valid: bool = game.gems.size() == game.ore_profile.gem_cap
	for gem in game.gems:
		valid = valid and gem.grade >= 2 and gem.is_embedded and gem.get_meta("brilliant", false) and float(gem.get_meta("value_multiplier", 1.0)) > 1.0
	_check(valid, "At 100% spawn chance, the stage cap contains distinct hidden, higher-grade brilliant gems without overfilling either layer")
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await process_frame
	var deadline := Time.get_ticks_usec() + 40000
	while Time.get_ticks_usec() < deadline:
		await process_frame

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SKILL_FAILED: " + message)
