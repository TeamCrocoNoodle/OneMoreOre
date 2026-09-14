extends SceneTree
const B = preload("res://scripts/game_balance.gd")
const S = preload("res://scripts/skill_tree.gd")
const M = preload("res://scripts/main_tools.gd")
const A = preload("res://scripts/aux_tools.gd")
const O = preload("res://scripts/ore_progression.gd")
const R = preload("res://scripts/mining_round.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var tree := S.new()
	var budget := 0
	for node in tree.get_nodes(): budget += int(node.cost)
	var start_budget := budget
	while budget > 0:
		var prior := budget
		for node in tree.get_nodes():
			if tree.can_purchase(node.id,budget): budget = int(tree.purchase(node.id,budget).gold)
		if budget == prior: break
	_check(budget == 0 and tree._owned.size() == 138,"Exact total cost buys all 137 paid nodes through real neighbor discovery")
	var main := M.new()
	var aux := A.new()
	_check(main.acquire("gold_pickaxe",M.CATALOG[-1].price).ok,"The final main tool can be bought without forcing collection of obsolete tools")
	for entry in A.CATALOG:
		_check(aux.acquire(entry.id,entry.price).ok,"Auxiliary purchase succeeds: "+entry.id)
	var stats := aux.apply_to(main.apply_to(tree.stats()))
	_check(aux.get_catalog().all(func(entry: Dictionary) -> bool: return entry.owned and entry.equipped),"All seven auxiliaries are equipped together")
	_check(main.equipped == "gold_pickaxe" and main.get_catalog().filter(func(entry: Dictionary) -> bool: return entry.equipped).size() == 1,"Only the gold pickaxe occupies the main slot")
	var final_dps := float(M.CATALOG[-1].power)*float(M.CATALOG[-1].speed)/.34
	for entry in M.CATALOG.slice(0,5):
		var dps := float(entry.power)*float(entry.speed)/(.46/3 if entry.id == "jackhammer" else .34)
		_check(final_dps > dps*1.8,"Gold has a substantial contact DPS advantage over "+entry.id)
	_check(B.STONE_HEALTH[6] > float(stats.damage)*2,"The final ore retains resistance even against a fully upgraded basic strike")
	_check(B.COVER_HEALTH[6] >= float(stats.damage)*8,"Final gem hosts survive isolated strikes so cracks and rarity light remain readable")
	var prior_pieces := 0
	for stage in 7:
		var profile := O.profile(0,stage)
		_check(profile.pieces == 74*(1 << stage),"Every ore doubles the actual independent stone count")
		if stage > 0:
			_check(B.STONE_HEALTH[stage] >= B.STONE_HEALTH[stage-1]*2.5,"At double the stone count, new-ore total resistance grows at least fivefold")
		_check(B.BOSS_HEALTH[stage] > B.COVER_HEALTH[stage],"Boss armor exceeds even its stage's gem cover resistance")
		prior_pieces = profile.pieces
	_check(prior_pieces == 4736,"The last ore contains thousands of individually mineable stones")
	var new_ore := O.profile(0,6)
	var entry_power := 6.0*B.MAIN_POWER[4]
	_check(B.bulk_damage("detonator",entry_power,new_ore.pieces) < B.STONE_HEALTH[6],"A previous-stage drill cannot instantly bypass new-ore resistance with explosives")
	_check(B.bulk_damage("detonator",float(stats.damage),new_ore.pieces) > B.bulk_damage("detonator",entry_power,new_ore.pieces),"Auxiliary blasting grows with the equipped main tool")
	var round_state := R.new()
	round_state.apply_stats(stats)
	round_state.start()
	var elapsed := 0.0
	while round_state.phase == R.Phase.MINING and elapsed < 1000:
		round_state.advance(.1)
		round_state.recover(100000)
		elapsed += .1
	var bound := round_state.duration*(1+B.RECOVERY_BUDGET+round_state.revive_count*round_state.revive_fraction)/round_state.drain_rate
	_check(elapsed <= bound+.2 and round_state.phase == R.Phase.DRAINING,"Unlimited healing events cannot prevent settlement")
	_check(is_equal_approx(round_state.recovered,round_state.duration*B.RECOVERY_BUDGET),"Healing pays exactly one round reserve, including at very high mining throughput")
	round_state.begin_settlement()
	round_state.commit_settlement()
	round_state.new_round()
	_check(round_state.recovered == 0,"Next round restores its healing reserve once")
	round_state.start()
	round_state.advance(10)
	var recovered := round_state.recovered
	round_state.refill_for_boss()
	_check(round_state.remaining == round_state.duration and round_state.recovered == recovered,"Boss entry restores health independently of the normal healing budget")
	_check(round_state.recover(INF) == 0 and round_state.recover(NAN) == 0 and round_state.recover(-1) == 0,"Invalid healing cannot corrupt time or reserve")
	var rng := RandomNumberGenerator.new()
	rng.seed = 49211
	for stage in 7:
		var profile := O.profile(B.ORE_GOLD[stage],stage)
		for attempt in 50:
			var loot := O.gem_plan(profile,stats,rng)
			_check(loot.grades.size() >= profile.gems.size() and loot.grades.size() <= profile.gem_cap,"Loot quantity respects the shared guarantee and socket cap")
			_check(loot.grades.all(func(grade: int) -> bool: return grade <= stage),"Skill rolls cannot bypass a boss rarity gate")
			_check(not loot.bands.has(0),"All planned gems remain inside the ore")
	_check(B.gold_label(10000000) == "10,000,000","Large shop prices retain all digits with readable grouping")
	print("BALANCE_VALIDATION checks=%d failures=%d tree_cost=%d max_round_seconds=%.1f" % [checks,failures,start_budget,bound])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
