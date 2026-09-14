extends RefCounted
## Bounded extraction transaction. Mining input and the round clock pause while
## this short transaction commits; every stone / gem still uses the same ledger.
var targets: Array = []
var surviving: Dictionary = {}
var removed: Array[StaticBody3D] = []
var points: Array[Vector3] = []
var cursor := 0
var cleanup_cursor := 0
var filtered := false
var complete := false
var recovery := 1.0
var crush := false
var damage_limit := -1.0
var collected_before := 0
var exposed_depth := 1
var reward := {"gold":0,"heal":0.0}
var context := {"secondary":true,"reaction_marks":{},"reaction_budget":{"used":0}}
var receipt: Dictionary = {}

func begin(game: Node3D, candidates: Array, value_recovery: float, crusher: bool, damage: float) -> void:
	targets = candidates.duplicate()
	recovery = value_recovery
	crush = crusher
	damage_limit = damage
	collected_before = game.collected_count
	exposed_depth = game._visible_ore_depth
	for chunk in game.chunks: surviving[chunk] = true
	# An all-ore kill disappears in the activation frame. Individual accounting
	# and resource retirement then happen under a strict per-frame CPU budget.
	if targets.size() > 256 and targets.size() == game.chunks.size() and targets.all(func(c): return is_instance_valid(c) and (damage_limit < 0.0 or c.health <= damage_limit)):
		game.shell.hide()

func advance(game: Node3D, budget_usec: int) -> void:
	var deadline := Time.get_ticks_usec()+budget_usec
	while cursor < targets.size() and Time.get_ticks_usec() < deadline:
		var body := targets[cursor] as StaticBody3D
		cursor += 1
		if not is_instance_valid(body) or not surviving.has(body) or body.destroyed: continue
		if damage_limit >= 0.0 and body.health > damage_limit:
			body.health -= damage_limit
			body.impact_count += 1
			continue
		var point: Vector3 = body.mesh_instance.to_global(body.face_center)
		body.set_meta("aux_received_damage",body.health)
		body.destroyed = true
		body.health = 0.0
		body.collision_layer = 0
		body.hide()
		body.set_process(false)
		if is_instance_valid(body.light_node): body.light_node.clear()
		if body.cover_gem != null:
			var jewel: StaticBody3D = body.cover_gem.get_ref()
			if is_instance_valid(jewel) and game.gems.has(jewel):
				var exit: Vector3 = point+game.camera.global_basis.z*.30
				if jewel.release_from_chunk(game,game.to_local(exit)):
					game._collect_gem(jewel,exit,recovery,true)
		if not crush and game.round_enabled:
			if not body.is_gem_cover: game.round_state.record_stone()
			var earned: Dictionary = game.mining_skills.on_break(false,false)
			reward.gold += int(earned.gold)
			reward.heal += float(earned.heal)
			var kind := str(body.get_meta("special_kind",""))
			if kind == "healing": reward.heal += game.SkillBalance.value("healing_amount")*(1.0+game.mining_skills.amount("healing_amount_bonus"))
			if kind == "gold_stone": reward.gold += roundi(game.SkillBalance.value("gold_stone_amount")*(1.0+game.mining_skills.amount("gold_stone_bonus")))
		surviving.erase(body)
		removed.append(body)
		points.append(point)
		exposed_depth = maxi(exposed_depth,body.layer_index+1)
		game.broken_count += 1
	if cursor < targets.size(): return
	if not filtered:
		game.chunks.assign(game.chunks.filter(func(chunk): return surviving.has(chunk)))
		filtered = true
	while cleanup_cursor < removed.size() and Time.get_ticks_usec() < deadline:
		var body := removed[cleanup_cursor]
		cleanup_cursor += 1
		if not game.chunks.is_empty(): game._reveal_ore_depth(body.layer_index+1,body)
		if not crush and not game.chunks.is_empty() and int(context.reaction_budget.used) < 96:
			var kind := str(body.get_meta("special_kind",""))
			if kind == "bomb": game._queue_special(body,body.global_position,game.mining_skills.bomb_damage(),context)
			elif kind == "resonance": game._queue_special(body,body.global_position,float(body.get_meta("aux_received_damage"))*(game.SkillBalance.value("resonance_damage")+game.mining_skills.amount("resonance_damage_bonus")),context)
		game._retire_chunk(body)
	if cleanup_cursor < removed.size(): return
	if game.round_enabled:
		game.hud.set_stones(game.round_state.ordinary_stones)
		game._apply_skill_reward(reward,game.get_viewport().get_visible_rect().size*.5)
	if not crush:
		for i in mini(6,points.size()):
			var at := points[i*points.size()/mini(6,points.size())]
			game.effects.impact(at,(at-game.shell.global_position).normalized(),true,Color("819093"))
	receipt = {"stones":removed.size(),"gems":game.collected_count-collected_before}
	complete = true
