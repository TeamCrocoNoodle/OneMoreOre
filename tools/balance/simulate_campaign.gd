extends SceneTree
## Offline pacing model. Uses production purchases, skills, cargo and loot rules.
## A virtual spherical shell approximates aim/occlusion; it is not a physics playtest.
const B = preload("res://scripts/game_balance.gd")
const S = preload("res://scripts/skill_balance.gd")
const SkillTreeModel = preload("res://scripts/skill_tree.gd")
const Main = preload("res://scripts/main_tools.gd")
const Aux = preload("res://scripts/aux_tools.gd")
const Ore = preload("res://scripts/ore_progression.gd")
const Boss = preload("res://scripts/boss_campaign.gd")
const Skills = preload("res://scripts/mining_skills.gd")
const Round = preload("res://scripts/mining_round.gd")
const Pickaxe = preload("res://scripts/pickaxe.gd")

var tree_model := SkillTreeModel.new()
var main := Main.new()
var aux := Aux.new()
var campaign := Boss.new()
var skills := Skills.new()
var ledger := Round.new()
var random := RandomNumberGenerator.new()
var stats: Dictionary
var info: Dictionary
var cells: Array[Dictionary] = []
var geometry_cache: Dictionary = {}
var purchases: Array[Dictionary] = []
var milestones: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var seconds := 0.0
var active_seconds := 0.0
var broken := 0
var shots := 0
var target := -1
var front := Vector3.FORWARD
var laser := 0.0
var crusher := 0.0
var detonated := false
var pin_used := false
var live := 0
var round_start := 0.0
var next_snapshot := 1800.0
var efficiency := 1.0
var policy := "balanced"
var seed_value := 101
var all_unlocked_minute := -1.0
var in_boss := false
var clear_delay := 2.4
var failed_bosses := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.get_slice("=",1))
		if arg.begins_with("--efficiency="): efficiency = float(arg.get_slice("=",1))
		if arg.begins_with("--policy="): policy = arg.get_slice("=",1)
	random.seed = seed_value
	skills.random.seed = seed_value+11
	ledger.reward_random.seed = seed_value+23
	ledger.auction.rng.seed = seed_value+31
	while seconds < 8*3600 and not campaign.won:
		_run_round()
	var result := {"seed":seed_value,"efficiency":efficiency,"policy":policy,"minutes":snappedf(seconds/60,0.1),"active_minutes":snappedf(active_seconds/60,0.1),"won":campaign.won,"all_unlocked_minute":all_unlocked_minute,"paid_nodes":tree_model._owned.size()-1,"main":main.equipped,"aux":aux._owned.size(),"lifetime_gold":ledger.lifetime_mining_gold,"wallet":ledger.wallet_gold,"rounds":ledger.round_index,"boss_failures":failed_bosses,"milestones":milestones,"snapshots":snapshots,"purchases":purchases}
	DirAccess.make_dir_recursive_absolute("res://artifacts/balance")
	var path := "res://artifacts/balance/campaign_%s_%d_%d.json" % [policy,seed_value,roundi(efficiency*100)]
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("BALANCE ",JSON.stringify(result.duplicate().merged({"purchases":purchases.size(),"snapshots":snapshots.size()},true)))
	quit(0 if campaign.won else 1)

func _configure() -> void:
	var disabled: Array[String] = []
	if in_boss: disabled.append("ore")
	stats = aux.apply_to(main.apply_to(tree_model.stats(disabled)))
	skills.configure(stats)
	ledger.apply_stats(stats)

func _run_round() -> void:
	_buy()
	_configure()
	if ledger.phase == Round.Phase.COMPLETE: ledger.new_round()
	campaign.new_round()
	skills.reset_round()
	ledger.start()
	round_start = seconds
	laser = random.randf_range(Aux.LASER_MIN,Aux.LASER_MAX)
	crusher = 0
	detonated = false
	_spawn()
	while ledger.phase == Round.Phase.MINING and seconds-round_start < 700:
		if live <= 0:
			campaign.record_ore(int(info.index))
			_tick(clear_delay)
			if ledger.phase != Round.Phase.MINING: break
			if campaign.eligible(int(info.index)):
				_run_boss()
				break
			_spawn()
			continue
		if aux.is_owned("detonator") and not detonated:
			detonated = true
			_bulk(1.0,false)
			clear_delay = 1.1
			continue
		if aux.is_owned("crusher") and crusher <= 0:
			crusher = Aux.CRUSHER_COOLDOWN
			_bulk(Aux.CRUSHER_RECOVERY,true)
			clear_delay = .85
			continue
		var exposed := _exposed()
		if exposed.is_empty():
			for i in cells.size():
				if cells[i].hp > 0 and (cells[i].parent < 0 or cells[cells[i].parent].hp <= 0):
					front = cells[i].dir
					break
			_tick(.65/efficiency)
			continue
		if target not in exposed:
			target = exposed[0]
			for i: int in exposed:
				if cells[i].dir.dot(front) > cells[target].dir.dot(front): target = i
			_tick(.14/efficiency)
			if ledger.phase != Round.Phase.MINING: break
		if aux.is_owned("laser") and laser <= 0:
			_kill(exposed[random.randi_range(0,exposed.size()-1)],false,false)
			laser = random.randf_range(Aux.LASER_MIN,Aux.LASER_MAX)
			continue
		if aux.is_owned("pin") and not pin_used:
			pin_used = true
			if random.randf() < Aux.PIN_CHANCE:
				_tick(Pickaxe.SWING_DURATION*Aux.PIN_HITS/maxf(.1,float(stats.attack_speed))/efficiency)
				for i: int in exposed:
					if cells[i].pos.distance_to(cells[target].pos) <= Aux.PIN_RADIUS: _kill(i,false,false)
				continue
		_strike(exposed)
	# Settlement animation, moving the pointer, choosing next. Shopping adds separate time.
	ledger.phase = Round.Phase.DRAINING
	var report: Dictionary = ledger.begin_settlement()
	ledger.commit_settlement()
	seconds += 7.0+float(report.rows.size())*.75
	if policy == "auction" and ledger.can_auction():
		ledger.begin_auction()
		ledger.commit_auction()
		seconds += 6
	_snapshot()

func _tick(delta: float) -> void:
	if ledger.phase != Round.Phase.MINING: return
	ledger.advance(delta)
	skills.advance(delta)
	seconds += delta
	active_seconds += delta
	laser -= delta
	crusher -= delta
	_snapshot()

func _strike(exposed: Array[int]) -> void:
	var tool: Dictionary = Main.definition(main.equipped)
	var speed: float = skills.speed(ledger.remaining,ledger.duration)*(2.0 if skills.extra_charges > 0 else 1.0)
	var period: float = (.46/3 if main.equipped == "jackhammer" else Pickaxe.SWING_DURATION)/speed
	_tick((period+1.0/60)/efficiency)
	if ledger.phase != Round.Phase.MINING: return
	shots += 1
	if random.randf() > .94: return
	var context: Dictionary = skills.begin_attack(target+1)
	var radius: float = skills.radius(ledger.spent)
	var hits: Array[int] = [target]
	for i: int in exposed:
		if i != target and hits.size() < 17 and cells[i].pos.distance_to(cells[target].pos) < radius: hits.append(i)
	var visited: Dictionary = {}
	for i: int in hits:
		var impact: Dictionary = skills.damage(context,i+1,cells[i].hp == cells[i].max_hp,cells[i].gem >= 0,cells[i].hp/cells[i].max_hp,hits.size())
		_hit(i,float(impact.damage),bool(context.critical),bool(impact.execute),visited)
	if bool(context.shock):
		var reach := radius*(S.value("shock_range")+skills.amount("shock_range_bonus"))
		var damage := float(stats.damage)*(S.value("shock_damage")+skills.amount("shock_damage_bonus"))
		for i: int in exposed:
			if cells[i].pos.distance_to(cells[target].pos) < reach: _hit(i,damage,false,false,visited)

func _hit(i: int, damage: float, critical: bool, execute: bool, visited: Dictionary) -> void:
	if ledger.phase != Round.Phase.MINING or cells[i].hp <= 0: return
	var received := minf(float(cells[i].hp),damage)
	cells[i].hp = 0.0 if execute else maxf(0,float(cells[i].hp)-damage)
	var kind: String = cells[i].kind
	var destroyed: bool = cells[i].hp <= 0
	if destroyed: _kill(i,critical,execute)
	if visited.size() >= 16 or visited.has(i): return
	if kind == "resonance" or (destroyed and kind == "bomb"):
		visited[i] = true
		var power := received*(S.value("resonance_damage")+skills.amount("resonance_damage_bonus")) if kind == "resonance" else S.value("bomb_damage")*(1+skills.amount("bomb_damage_bonus"))
		for j in cells.size():
			if j != i and cells[j].hp > 0 and cells[j].pos.distance_to(cells[i].pos) < S.value("neighbor_radius"): _hit(j,power,false,false,visited)

func _kill(i: int, critical: bool, executed: bool, recovery: float = 1.0, crush: bool = false) -> void:
	if cells[i].dead or ledger.phase != Round.Phase.MINING: return
	cells[i].hp = 0.0
	cells[i].dead = true
	live -= 1
	broken += 1
	if not crush:
		if cells[i].gem < 0: ledger.record_stone()
		_reward(skills.on_break(critical,executed))
		if cells[i].kind == "healing": ledger.recover(S.value("healing_amount")*(1+skills.amount("healing_amount_bonus")))
		if cells[i].kind == "gold_stone": ledger.record_bonus_gold(roundi(S.value("gold_stone_amount")*(1+skills.amount("gold_stone_bonus"))))
	if cells[i].gem >= 0:
		ledger.record_gem(cells[i].gem,cells[i].premium,recovery)
		_reward(skills.on_gem())

func _reward(reward: Dictionary) -> void:
	ledger.record_bonus_gold(int(reward.gold))
	ledger.recover(float(reward.heal))

func _bulk(recovery: float, crush: bool) -> void:
	for i in cells.size(): _kill(i,false,false,recovery,crush)

func _exposed() -> Array[int]:
	var result: Array[int] = []
	for i in cells.size():
		var cell: Dictionary = cells[i]
		if cell.hp > 0 and cell.dir.dot(front) > .15 and (cell.parent < 0 or cells[cell.parent].hp <= 0): result.append(i)
	return result

func _spawn() -> void:
	clear_delay = 2.4
	info = Ore.profile(ledger.lifetime_mining_gold,campaign.cleared)
	var stage := int(info.index)
	if not geometry_cache.has(stage):
		var shape: Array[Dictionary] = []
		var previous: Array[int] = []
		for layer in info.layers.size():
			var indices: Array[int] = []
			var count: int = info.layers[layer]
			for j in count:
				var y := 1.0-2.0*(j+.5)/count
				var angle: float = j*2.399963+layer*.41
				var dir := Vector3(sqrt(1-y*y)*cos(angle),y,sqrt(1-y*y)*sin(angle))
				var parent := -1
				for outer in previous:
					if parent < 0 or dir.dot(shape[outer].dir) > dir.dot(shape[parent].dir): parent = outer
				indices.append(shape.size())
				shape.append({"layer":layer,"dir":dir,"pos":dir*(float(info.radius)-layer*float(info.stride)),"parent":parent})
			previous = indices
		geometry_cache[stage] = shape
	cells.assign(geometry_cache[stage].duplicate(true))
	for i in cells.size():
		var hp := B.stone_health(stage,int(cells[i].layer),random.randi())
		cells[i].merge({"hp":hp,"max_hp":hp,"gem":-1,"premium":1.0,"kind":"","dead":false})
	var loot := Ore.gem_plan(info,stats,random)
	for g in loot.grades.size():
		var available: Array[int] = []
		for i in cells.size():
			if cells[i].layer == loot.bands[g] and cells[i].gem < 0: available.append(i)
		if available.is_empty(): continue
		var i: int = available[random.randi_range(0,available.size()-1)]
		cells[i].gem = loot.grades[g]
		cells[i].hp = float(info.cover_health)
		cells[i].max_hp = float(info.cover_health)
		if skills.amount("brilliant") > 0 and random.randf() < S.value("brilliant_chance")+skills.amount("brilliant_chance_bonus"):
			cells[i].premium = 1+S.value("brilliant_value")+skills.amount("brilliant_value_bonus")
	for cell in cells:
		if cell.gem >= 0: continue
		var ticket := random.randf()
		for kind: String in ["resonance","healing","bomb","gold_stone"]:
			if skills.amount(kind) <= 0: continue
			var chance := S.value("special_spawn")+skills.amount(kind+"_chance_bonus")
			if ticket < chance:
				cell.kind = kind
				break
			ticket -= chance
	live = cells.size()
	target = -1
	front = Vector3.FORWARD
	pin_used = false

func _run_boss() -> void:
	var stage: int = campaign.cleared
	campaign.begin(stage)
	in_boss = true
	_configure()
	ledger.refill_for_boss()
	var spec: Dictionary = Boss.BOSSES[stage]
	var total := 0
	for n: int in spec.layers: total += n
	var hp: float = float(spec.health)
	var effective_damage: float = float(stats.damage)*(1.0+float(stats.first_damage)*.3+float(stats.ore_damage)*0.0)
	var crit := (0.1 if skills.amount("critical") > 0 else 0.0)+float(stats.crit_chance_bonus)+float(stats.tool_critical)
	effective_damage *= 1+crit*(1+float(stats.crit_damage_bonus))
	var aoe := clampf(pow(skills.radius(ledger.spent)/.65,2),1.0,5.0)
	var speed: float = skills.speed(ledger.remaining,ledger.duration)
	var period := (.46/3 if main.equipped == "jackhammer" else Pickaxe.SWING_DURATION)/speed+.04
	var time_needed: float = total*ceil(hp/effective_damage)*period/aoe/efficiency
	# Mechanical downtime: regeneration, shields, moving weak points, wires,
	# spike safety windows, projectile interception/rest phases, final full clear.
	if stage == 0: time_needed *= 1.75
	if stage == 1: time_needed *= 1.4
	if stage == 2: time_needed = time_needed*.55+12
	if stage == 3: time_needed = minf(time_needed*.5+14,90)
	if stage == 4: time_needed *= 1.6
	if stage == 5: time_needed = time_needed*.7+24
	if aux.is_owned("detonator") and not detonated: time_needed *= .80
	time_needed += 4
	var available: float = ledger.duration*(1+(ledger.revive_count-ledger.revives_used)*ledger.revive_fraction)/ledger.drain_rate
	var success: bool = time_needed < (60 if stage == 3 else available)
	seconds += minf(time_needed,60 if stage == 3 else available)
	active_seconds += minf(time_needed,60 if stage == 3 else available)
	if success:
		for i in roundi(total*(1.75 if stage == 0 else .65 if stage in [2,3] else 1.0)): ledger.record_stone()
		ledger.record_boss_reward(campaign.finish(true),spec.title)
		milestones.append({"boss":stage+1,"minute":snappedf(seconds/60,.1),"fight_seconds":snappedf(time_needed,.1),"power":stats.damage,"nodes":tree_model._owned.size()-1})
	else:
		campaign.finish(false)
		failed_bosses += 1
	ledger.phase = Round.Phase.DRAINING
	in_boss = false

func _buy() -> void:
	var count := 0
	while true:
		var options: Array[Dictionary] = []
		for node in tree_model.get_nodes():
			if tree_model.is_unlocked(node.id) or not tree_model.is_visible(node.id): continue
			var weight := 1.0
			if node.category == "attack": weight = 1.3 if policy != "economy" else .9
			if node.category in ["gold","ore"] and policy == "economy": weight = 1.4
			options.append({"kind":"skill","id":node.id,"price":node.cost,"score":float(node.cost)/weight})
		for entry in Main.CATALOG:
			if not main.is_owned(entry.id):
				options.append({"kind":"main","id":entry.id,"price":entry.price,"score":float(entry.price)/1.7})
				break
		for entry in Aux.CATALOG:
			if not aux.is_owned(entry.id): options.append({"kind":"aux","id":entry.id,"price":entry.price,"score":float(entry.price)/(1.3 if entry.id in ["laser","crusher","detonator"] else 1.0)})
		if options.is_empty(): break
		options.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.score) < float(b.score))
		var choice: Dictionary = options[0]
		if ledger.wallet_gold < int(choice.price): break
		var result: Dictionary
		if choice.kind == "skill": result = tree_model.purchase(choice.id,ledger.wallet_gold)
		elif choice.kind == "main": result = main.acquire(choice.id,ledger.wallet_gold)
		else: result = aux.acquire(choice.id,ledger.wallet_gold)
		assert(result.ok)
		ledger.wallet_gold = result.gold
		purchases.append({"minute":snappedf(seconds/60,.1),"kind":choice.kind,"id":choice.id,"cost":choice.price})
		count += 1
	if count > 0: seconds += 4+count*2.0
	if tree_model._owned.size() == tree_model.get_nodes().size() and main.equipped == "gold_pickaxe" and aux._owned.size() == 7 and all_unlocked_minute < 0:
		all_unlocked_minute = snappedf(seconds/60,.1)

func _snapshot() -> void:
	if seconds < next_snapshot: return
	snapshots.append({"minute":roundi(next_snapshot/60),"gold":ledger.lifetime_mining_gold,"nodes":tree_model._owned.size()-1,"main":main.equipped,"aux":aux._owned.size(),"bosses":campaign.cleared,"stones":broken,"attacks":shots,"damage":stats.get("damage",1),"speed":stats.get("attack_speed",1),"radius":stats.get("attack_radius",.38)})
	next_snapshot += 1800
