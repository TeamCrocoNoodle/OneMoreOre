extends RefCounted
## Reference topology, expressed on integer grid cells. Every box is a node.
const B = preload("res://scripts/skill_balance.gd")
var nodes: Array[Dictionary] = []
var edges: Array = []
var _positions: Dictionary = {}

func _init() -> void:
	_add("origin", "첫 곡괭이", "기본 공격력 +%s\n채굴을 시작하며 이미 습득한 기술입니다." % B.value("base_power"), "power", "attack", Vector2i.ZERO, {"damage": B.value("base_power")})
	_attack()
	_health()
	_gold()
	_ore()
	_link("origin", "speed")
	_link("origin", "vitality")
	_link("origin", "income_2")
	_link("origin", "rich_ore")
	_link("brilliant", "rare_1")
	_compact_attack_grid()
	_price_by_distance()
	for node in nodes:
		if node.id in ["break_heal","recovery","healing"]:
			node.description += "\n채굴당 회복 한도: 최대 체력의 80%. 부활과 보스 입장 회복은 별도입니다."

func _add(id: String, title: String, description: String, icon: String, category: String, grid: Vector2i, effects: Dictionary, parent: String = "", rank: int = 0) -> void:
	assert(not _positions.has(id), "Duplicate skill id: " + id)
	_positions[id] = grid
	nodes.append({"id": id, "title": title, "description": description, "icon": icon, "category": category,
		"grid": grid, "effects": effects, "cost": 0, "rank": rank})
	if not parent.is_empty():
		_link(parent, id)

func _link(a: String, b: String) -> void:
	edges.append([a, b])

func _step(id: String, title: String, key: String, effect: String, icon: String, category: String, grid: Vector2i, parent: String, rank: int = 0, percentage: bool = true) -> void:
	_add(id, title, title + " +" + (B.percent(key) if percentage else "%s" % B.value(key)), icon, category, grid, {effect: B.value(key)}, parent, rank)

func _chain(prefix: String, title: String, key: String, effect: String, icon: String, category: String, count: int, start: Vector2i, direction: Vector2i, parent: String, percentage: bool = true) -> void:
	for i in count:
		var id := prefix + "_%d" % (i + 1)
		_step(id, title, key, effect, icon, category, start + direction * i, parent, i + 1, percentage)
		parent = id

func _attack() -> void:
	var c := "attack"
	_step("speed", "공격 속도", "speed", "attack_speed", "speed", c, Vector2i(-6, 2), "")
	_step("power_tip", "곡괭이 공격력", "power", "damage", "power", c, Vector2i(-7, 2), "speed", 1, false)
	_step("reach", "공격 범위", "range", "range_bonus", "reach", c, Vector2i(-6, 5), "speed", 1)
	_step("power", "곡괭이 공격력", "power", "damage", "power", c, Vector2i(-6, 8), "reach", 2, false)
	_step("speed_2", "공격 속도", "speed", "attack_speed", "speed", c, Vector2i(-6, 11), "power", 2)
	_step("power_3", "곡괭이 공격력", "power", "damage", "power", c, Vector2i(-6, 14), "speed_2", 3, false)
	_step("ore_damage", "광물을 품은 돌", "ore_damage", "ore_damage", "rich_ore/power", c, Vector2i(-6, 17), "power_3")
	_step("range_2", "공격 범위", "range", "range_bonus", "reach", c, Vector2i(-6, 20), "ore_damage", 2)
	_step("first_hit", "첫 균열", "first_damage", "first_damage", "first/power", c, Vector2i(-6, 23), "range_2")
	nodes[-1].description = "아직 공격받지 않은 돌조각에 주는 피해량 +" + B.percent("first_damage")
	_step("speed_5", "공격 속도", "speed", "attack_speed", "speed", c, Vector2i(-6, 26), "first_hit", 5)
	_add("finisher", "마지막 일격", "체력이 " + B.percent("finisher_threshold") + " 이하인 돌조각에 피해량 +" + B.percent("finisher_damage"), "finisher/power", c, Vector2i(-6, 29), {"finisher": 1.0}, "speed_5")
	_step("range_3", "공격 범위", "range", "range_bonus", "reach", c, Vector2i(-8, 11), "speed_2", 3)
	_add("crowd", "한 번에 더 많이", "한 공격으로 맞히는 돌조각이 하나 늘 때마다 피해량 +" + B.percent("crowd_damage") + "\n최대 +" + B.percent("crowd_cap"), "crowd/power", c, Vector2i(-8, 14), {"crowd": 1.0}, "range_3")
	_step("speed_3", "공격 속도", "speed", "attack_speed", "speed", c, Vector2i(-7, 17), "ore_damage", 3)
	_step("speed_4", "공격 속도", "speed", "attack_speed", "speed", c, Vector2i(-8, 17), "speed_3", 4)
	_link("speed_4", "crowd")
	_chain("power_side", "곡괭이 공격력", "power", "damage", "power", c, 2, Vector2i(-7, 20), Vector2i.LEFT, "range_2", false)
	_add("streak", "집중 채굴", "같은 돌조각을 연속해서 때릴 때마다 피해량 +" + B.percent("streak_damage") + "\n최대 %d회 중첩. 다른 조각을 직접 때리면 초기화됩니다." % int(B.value("streak_cap")), "streak/power", c, Vector2i(-8, 23), {"streak": 1.0}, "first_hit")
	_step("range_4", "공격 범위", "range", "range_bonus", "reach", c, Vector2i(-8, 29), "finisher", 4)
	_add("combo", "콤보", "돌조각 10개 파괴마다 콤보 +1. 스택당 공격력 +1%%.\n%s초 안에 돌을 부수면 시간이 갱신됩니다. 콤보가 높을수록 제한 시간이 짧아지며, 시간이 끝나면 초기화됩니다." % B.value("combo_duration"), "combo", c, Vector2i(-11, 8), {"combo": 1.0}, "power")
	_chain("combo_power", "콤보 스택당 공격력 보너스", "combo_step", "combo_damage_bonus", "combo/power", c, 2, Vector2i(-12, 9), Vector2i.DOWN, "combo")
	_chain("combo_time", "콤보 유지 시간", "combo_time_step", "combo_time_bonus", "combo/time", c, 2, Vector2i(-10, 9), Vector2i.DOWN, "combo", false)
	_add("combo_speed", "콤보 가속", "콤보 %d스택 초과 시 공격 속도 +" % int(B.value("combo_speed_threshold")) + B.percent("combo_speed"), "combo/speed", c, Vector2i(-12, 12), {"combo_speed": 1.0}, "combo_power_2")
	_add("shock", "충격파", "공격 시 " + B.percent("shock_chance") + " 확률로 충격파 발생.\n공격 범위의 " + B.percent("shock_range") + " 반경에 기존 피해량의 " + B.percent("shock_damage") + " 피해를 줍니다.", "shock", c, Vector2i(-4, 5), {"shock": 1.0}, "reach")
	_chain("shock_power", "충격파 피해량", "shock_damage_step", "shock_damage_bonus", "shock/power", c, 3, Vector2i(-3, 4), Vector2i.RIGHT, "shock")
	_chain("shock_range", "충격파 범위", "shock_range_step", "shock_range_bonus", "shock/reach", c, 3, Vector2i(-3, 5), Vector2i.RIGHT, "shock")
	_chain("shock_chance", "충격파 확률", "shock_chance_step", "shock_chance_bonus", "shock/chance", c, 3, Vector2i(-3, 6), Vector2i.RIGHT, "shock")
	_add("extra", "추가타격", "5번째 기본 공격마다 " + B.percent("extra_chance") + " 확률로 다음 공격 1회가 200% 속도로 나갑니다.\n추가타격은 다시 추가타격을 충전하지 않습니다.", "extra", c, Vector2i(-4, 11), {"extra": 1.0}, "speed_2")
	for i in 3:
		_add("extra_count_%d" % (i + 1), "추가타격 횟수", "추가타격 횟수 +1", "extra/count", c, Vector2i(-3 + i, 10), {"extra_count_bonus": 1.0}, "extra" if i == 0 else "extra_count_%d" % i, i + 1)
	_chain("extra_chance", "추가타격 확률", "extra_chance_step", "extra_chance_bonus", "extra/chance", c, 3, Vector2i(-3, 12), Vector2i.RIGHT, "extra")
	_add("critical", "치명타", "치명타 확률 10%\n치명타 피해량 200%", "critical", c, Vector2i(-4, 17), {"critical": 1.0}, "ore_damage")
	_chain("crit_chance", "치명타 확률", "crit_chance_step", "crit_chance_bonus", "critical/chance", c, 3, Vector2i(-3, 16), Vector2i.RIGHT, "critical")
	_chain("crit_power", "치명타 피해량", "crit_damage_step", "crit_damage_bonus", "critical/power", c, 3, Vector2i(-3, 18), Vector2i.RIGHT, "critical")
	_add("crit_gold", "치명적인 수익", "치명타로 돌조각을 부술 때 %d Gold를 얻습니다." % int(B.value("crit_gold")), "critical/gold", c, Vector2i(-2, 15), {"crit_gold": B.value("crit_gold")}, "crit_chance_2")
	_add("extra_critical", "연속 치명타", "5번째 기본 공격이 치명타이고 추가타격이 발동되면, 충전된 추가타격이 모두 치명타가 됩니다.\n치명타와 추가타격을 모두 습득해야 발동합니다.", "extra/critical", c, Vector2i(-1, 14), {"extra_critical": 1.0}, "extra_chance_3")
	_link("extra_critical", "crit_chance_3")
	_add("execute", "처형", "처음 공격받는 돌조각이 0.5% 확률로 즉시 파괴됩니다.", "execute", c, Vector2i(-4, 23), {"execute": 0.005}, "first_hit")
	_add("execute_chance_1", "처형 확률", "처형 확률 +0.5%", "execute/chance", c, Vector2i(-3, 22), {"execute": 0.005}, "execute", 1)
	_add("execute_chance_2", "처형 확률", "처형 확률 +1%", "execute/chance", c, Vector2i(-2, 22), {"execute": 0.01}, "execute_chance_1", 2)
	_add("execute_gold", "처형의 대가", "처형으로 돌조각을 부술 때 %d Gold를 얻습니다." % int(B.value("execute_gold")), "execute/gold", c, Vector2i(-3, 24), {"execute_gold": B.value("execute_gold")}, "execute")

func _health() -> void:
	var c := "health"
	_step("vitality", "최대 체력", "health", "duration", "vitality", c, Vector2i(-2, -2), "", 1, false)
	for i in range(2, 5):
		_step("health_%d" % i, "최대 체력", "health", "duration", "vitality", c, Vector2i(-2, -i - 1), "vitality" if i == 2 else "health_%d" % (i - 1), i, false)
	for i in 3:
		_add("drain_%d" % (i + 1), "느린 체력 소모", "초당 체력 소모 -%s" % B.value("drain_reduction"), "drain", c, Vector2i(-4, -3 - i), {"drain_reduction": B.value("drain_reduction")}, "health_2" if i == 0 else "drain_%d" % i, i + 1)
	_add("spent_range", "깊어지는 호흡", "이번 채굴에서 소모한 체력이 %s 이상이면 공격 범위 +" % B.value("spent_threshold") + B.percent("spent_range") + "\n회복해도 누적 소모량은 유지됩니다.", "drain/reach", c, Vector2i(-6, -3), {"spent_range": 1.0}, "drain_1")
	_step("spent_range_more", "조건부 공격 범위", "spent_range_step", "spent_range_bonus", "drain/reach", c, Vector2i(-6, -4), "spent_range")
	_add("spent_threshold", "빠른 적응", "조건에 필요한 체력 소모량 -%s" % B.value("spent_threshold_reduction"), "drain/down", c, Vector2i(-6, -5), {"spent_threshold_reduction": B.value("spent_threshold_reduction")}, "spent_range_more")
	_add("low_health", "마지막 집중", "남은 체력이 " + B.percent("low_health_threshold") + " 이하이면 공격 속도 +" + B.percent("low_health_speed"), "low_health/speed", c, Vector2i(-6, -7), {"low_health": 1.0}, "spent_threshold")
	_link("drain_3", "low_health")
	_step("low_health_speed", "위기의 가속", "low_health_speed_step", "low_health_speed_bonus", "low_health/speed", c, Vector2i(-6, -8), "low_health")
	_step("low_health_threshold", "더 이른 집중", "low_health_threshold_step", "low_health_threshold_bonus", "low_health/chance", c, Vector2i(-6, -9), "low_health_speed")
	_add("revive", "다시 한 번", "체력이 소진되면 채굴당 1회, 최대 체력의 " + B.percent("revive_fraction") + "를 회복하고 계속 채굴합니다.", "revive", c, Vector2i(-3, -7), {"revive": 1.0}, "drain_3")
	_link("revive", "health_4")
	_step("revive_heal", "부활 회복량", "revive_fraction_step", "revive_fraction_bonus", "revive/heal", c, Vector2i(-3, -8), "revive")
	_add("revive_count", "두 번째 기회", "채굴당 부활 횟수 +1", "revive/count", c, Vector2i(-3, -9), {"revive_count_bonus": 1.0}, "revive_heal")
	_add("break_heal", "부수며 회복", "돌조각을 부술 때 " + B.percent("break_heal_chance") + " 확률로 체력 %s 회복" % B.value("break_heal"), "stone/heal", c, Vector2i(0, -3), {"break_heal": 1.0}, "health_2")
	_step("break_heal_chance", "파괴 회복 확률", "break_heal_chance_step", "break_heal_chance_bonus", "stone/chance", c, Vector2i(0, -4), "break_heal")
	_step("break_heal_amount", "파괴 회복량", "break_heal_step", "break_heal_bonus", "stone/heal", c, Vector2i(0, -5), "break_heal_chance", 0, false)
	_add("recovery", "광물의 활력", "광물을 획득할 때마다 체력 %s 회복" % B.value("gem_heal"), "recovery", c, Vector2i(0, -7), {"recovery_per_gem": B.value("gem_heal")}, "health_4")
	_link("recovery", "break_heal_amount")
	_step("recovery_more", "광물 회복량", "gem_heal_step", "recovery_per_gem", "recovery/heal", c, Vector2i(0, -8), "recovery", 0, false)

func _gold() -> void:
	var c := "gold"
	_chain("income", "총 Gold 수입", "income", "income_bonus", "gold", c, 5, Vector2i(2, 1), Vector2i.DOWN, "")
	_chain("value", "광물 가치", "gem_value", "gem_value_bonus", "appraisal", c, 4, Vector2i(4, 2), Vector2i.DOWN, "income_2")
	_add("gold_drop", "돌 속의 잔돈", "돌조각이 파괴될 때 " + B.percent("drop_chance") + " 확률로 %d Gold 획득" % int(B.value("drop_gold")), "stone/gold", c, Vector2i(0, 3), {"gold_drop": 1.0}, "income_2")
	_chain("drop_amount", "드롭 Gold", "drop_gold_step", "drop_gold_bonus", "stone/gold", c, 3, Vector2i(0, 4), Vector2i.DOWN, "gold_drop", false)
	_chain("drop_chance", "Gold 드롭 확률", "drop_chance_step", "drop_chance_bonus", "gold/chance", c, 3, Vector2i(1, 4), Vector2i.DOWN, "gold_drop")
	_add("brilliant", "찬란함", "광물이 " + B.percent("brilliant_chance") + " 확률로 찬란함을 얻습니다.\n찬란한 광물의 Gold 가치 +" + B.percent("brilliant_value"), "brilliant", c, Vector2i(6, 3), {"brilliant": 1.0}, "value_2")
	_chain("brilliant_value", "찬란한 광물의 추가 가치", "brilliant_value_step", "brilliant_value_bonus", "brilliant/gold", c, 3, Vector2i(6, 4), Vector2i.DOWN, "brilliant")
	_chain("brilliant_chance", "찬란함 확률", "brilliant_chance_step", "brilliant_chance_bonus", "brilliant/chance", c, 3, Vector2i(7, 4), Vector2i.DOWN, "brilliant")
	_add("golden_day", "황금의 날", "정산 시 " + B.percent("golden_chance") + " 확률로 전체 수입이 2배가 됩니다.\n정산마다 한 번만 추첨합니다.", "golden_day", c, Vector2i(2, 7), {"golden_day": 1.0}, "income_5")
	_step("golden_chance", "황금의 날 확률", "golden_chance_step", "golden_chance_bonus", "golden_day/chance", c, Vector2i(2, 8), "golden_day")
	_add("golden_pity", "기다린 만큼", "황금의 날이 발동하지 않은 정산마다 확률 +" + B.percent("golden_pity") + "\n발동하면 누적 확률이 초기화됩니다.", "golden_day/pity", c, Vector2i(2, 9), {"golden_pity": B.value("golden_pity")}, "golden_chance")

func _ore() -> void:
	var c := "ore"
	_step("rich_ore", "광물 등장 확률", "gem_spawn", "gem_spawn_bonus", "rich_ore/chance", c, Vector2i(2, -2), "", 1)
	_step("gem_gold_1", "광물 획득 Gold", "gem_gold", "gem_pickup_gold", "rich_ore/gold", c, Vector2i(3, -2), "rich_ore", 1, false)
	_step("ore_spawn_2", "광물 등장 확률", "gem_spawn", "gem_spawn_bonus", "rich_ore/chance", c, Vector2i(4, -2), "gem_gold_1", 2)
	_step("rare_1", "희귀한 광물 등장 확률", "rare_spawn", "rare_spawn_bonus", "rare/chance", c, Vector2i(5, -2), "ore_spawn_2", 1)
	_step("ore_spawn_3", "광물 등장 확률", "gem_spawn", "gem_spawn_bonus", "rich_ore/chance", c, Vector2i(6, -2), "rare_1", 3)
	_step("gem_gold_2", "광물 획득 Gold", "gem_gold", "gem_pickup_gold", "rich_ore/gold", c, Vector2i(7, -2), "ore_spawn_3", 2, false)
	_step("ore_spawn_4", "광물 등장 확률", "gem_spawn", "gem_spawn_bonus", "rich_ore/chance", c, Vector2i(8, -2), "gem_gold_2", 4)
	_add("gem_buff", "광물의 축복", "광물 획득 시 %s초 동안 무작위 강화 1개를 얻습니다.\n공격력 +%s / 공격 속도 +%s / 공격 범위 +%s\n다시 획득하면 효과와 지속 시간이 갱신됩니다." % [B.value("buff_duration"), B.percent("buff_power"), B.percent("buff_speed"), B.percent("buff_range")], "blessing", c, Vector2i(9, -2), {"gem_buff": 1.0}, "ore_spawn_4")
	_step("ore_spawn_5", "광물 등장 확률", "gem_spawn", "gem_spawn_bonus", "rich_ore/chance", c, Vector2i(10, -2), "gem_buff", 5)
	_step("rare_2", "희귀한 광물 등장 확률", "rare_spawn", "rare_spawn_bonus", "rare/chance", c, Vector2i(5, -3), "rare_1", 2)
	_step("rare_3", "희귀한 광물 등장 확률", "rare_spawn", "rare_spawn_bonus", "rare/chance", c, Vector2i(5, -4), "rare_2", 3)
	_special("resonance", "공명", "피해를 받을 때마다 인접한 돌조각에 받은 피해량의 " + B.percent("resonance_damage") + "만큼 피해를 줍니다.", Vector2i(4, -5), "ore_spawn_2", 3, "resonance_damage_step", "resonance_damage_bonus", "피해량")
	_special("healing", "회복", "파괴될 때 체력을 %s 회복합니다." % B.value("healing_amount"), Vector2i(6, -5), "ore_spawn_3", 2, "healing_amount_step", "healing_amount_bonus", "회복량")
	_special("bomb", "폭탄", "파괴될 때 인접한 돌조각에 %s 피해를 줍니다." % B.value("bomb_damage"), Vector2i(8, -5), "ore_spawn_4", 3, "bomb_damage_step", "bomb_damage_bonus", "피해량")
	_special("gold_stone", "황금", "파괴될 때 %d Gold를 얻습니다." % int(B.value("gold_stone_amount")), Vector2i(10, -5), "ore_spawn_5", 2, "gold_stone_step", "gold_stone_bonus", "Gold량")

func _special(id: String, title: String, description: String, grid: Vector2i, parent: String, count: int, key: String, effect: String, label: String) -> void:
	_add(id, title + " 돌조각", description + "\n일반 돌조각에 " + B.percent("special_spawn") + " 확률로 등장합니다.", id, "ore", grid, {id: 1.0}, parent)
	_chain(id + "_chance", title + " 돌 등장 확률", "special_spawn_step", id + "_chance_bonus", id + "/chance", "ore", count, grid + Vector2i.UP, Vector2i.UP, id)
	_chain(id + "_amount", title + " 돌 " + label, key, effect, id + ("/heal" if id == "healing" else ("/gold" if id == "gold_stone" else "/power")), "ore", count, grid + Vector2i(1, -1), Vector2i.UP, id)

func _price_by_distance() -> void:
	var distances := {"origin": 0}
	var queue: Array[String] = ["origin"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for edge: Array in edges:
			var other := str(edge[1] if edge[0] == id else edge[0])
			if id not in edge or distances.has(other):
				continue
			distances[other] = int(distances[id]) + 1
			queue.append(other)
	for node in nodes:
		assert(distances.has(node.id), "Disconnected skill: " + str(node.id))
		node["depth"] = int(distances[node.id])
		node.cost = B.cost(str(node.id),int(node.depth))

func _compact_attack_grid() -> void:
	# The reference uses long rectangular labels; icon-only square cells let
	# neighboring subtrees share rows while preserving every graph connection.
	var rows := {2: 2, 4: 2, 5: 3, 6: 4, 8: 4, 9: 5, 10: 5, 11: 5, 12: 6, 14: 6, 15: 8, 16: 7, 17: 7, 18: 8, 20: 8, 22: 9, 23: 9, 24: 10, 26: 10, 29: 11}
	for node in nodes:
		if node.category != "attack" or node.id == "origin":
			continue
		var grid: Vector2i = node.grid
		grid.y = int(rows[grid.y])
		if node.id in ["combo_power_2", "combo_time_2"]:
			grid.y = 6
		elif node.id == "combo_speed":
			grid.y = 8
		elif node.id == "extra_critical":
			grid = Vector2i(0, 8)
		elif node.id == "crit_gold":
			grid = Vector2i(-4, 8)
		elif node.id == "speed":
			grid = Vector2i(-2, 1)
		elif node.id == "power_tip":
			grid = Vector2i(-3, 1)
		node.grid = grid
		_positions[node.id] = grid
