extends RefCounted
## Short-lived mining modifiers. Secondary damage never recursively rolls procs.
const B = preload("res://scripts/skill_balance.gd")
var stats: Dictionary = {}
var random := RandomNumberGenerator.new()
var combo := 0
var combo_kills := 0
var combo_remaining := 0.0
var attacks := 0
var extra_charges := 0
var extra_force_critical := false
var last_target := 0
var streak := 0
var buff := -1
var buff_remaining := 0.0

func _init() -> void:
	random.randomize()

func configure(values: Dictionary) -> void:
	stats = values.duplicate()

func amount(key: String) -> float:
	return float(stats.get(key, 0.0))

func reset_round() -> void:
	combo = 0
	combo_kills = 0
	combo_remaining = 0.0
	attacks = 0
	extra_charges = 0
	extra_force_critical = false
	last_target = 0
	streak = 0
	buff = -1
	buff_remaining = 0.0

func clear_target() -> void:
	last_target = 0
	streak = 0

func advance(delta: float) -> void:
	combo_remaining = maxf(0.0, combo_remaining - delta)
	if combo_remaining <= 0.0:
		combo = 0
		combo_kills = 0
	buff_remaining = maxf(0.0, buff_remaining - delta)
	if buff_remaining <= 0.0:
		buff = -1

func speed(remaining: float, maximum: float) -> float:
	var bonus := 0.0
	if amount("low_health") > 0.0 and remaining / maxf(maximum, 0.001) <= B.value("low_health_threshold") + amount("low_health_threshold_bonus"):
		bonus += B.value("low_health_speed") + amount("low_health_speed_bonus")
	if amount("combo_speed") > 0.0 and combo > int(B.value("combo_speed_threshold")):
		bonus += B.value("combo_speed")
	if buff == 1:
		bonus += B.value("buff_speed")
	return maxf(0.1, amount("attack_speed")) * (1.0 + bonus)

func radius(spent: float) -> float:
	var bonus := amount("range_bonus")
	if amount("spent_range") > 0 and spent >= maxf(0.0, B.value("spent_threshold") - amount("spent_threshold_reduction")):
		bonus += B.value("spent_range") + amount("spent_range_bonus")
	if buff == 2:
		bonus += B.value("buff_range")
	return B.value("base_radius") * (1.0 + bonus) * float(stats.get("tool_radius", 1.0))

func begin_attack(target: int) -> Dictionary:
	var extra := extra_charges > 0
	var has_critical := amount("critical") > 0 or amount("tool_critical") > 0
	var critical := has_critical and roll((0.10 if amount("critical") > 0 else 0.0) + amount("tool_critical") + amount("crit_chance_bonus"))
	if extra:
		extra_charges -= 1
		critical = critical or extra_force_critical
	else:
		attacks += 1
		if amount("extra") > 0 and attacks % 5 == 0 and roll(B.value("extra_chance") + amount("extra_chance_bonus")):
			extra_charges = 1 + int(amount("extra_count_bonus"))
			extra_force_critical = critical and amount("extra_critical") > 0
	streak = mini(streak + 1, int(B.value("streak_cap"))) if target == last_target else 0
	last_target = target
	return {"critical": critical, "extra": extra, "shock": amount("shock") > 0 and roll(B.value("shock_chance") + amount("shock_chance_bonus")), "target": target}

func damage(context: Dictionary, target: int, first: bool, ore: bool, health_ratio: float, count: int) -> Dictionary:
	var bonus := 0.0
	if amount("combo") > 0:
		bonus += combo * (0.01 + amount("combo_damage_bonus"))
	if ore:
		bonus += amount("ore_damage")
	if first:
		bonus += amount("first_damage")
	if amount("streak") > 0 and target == last_target:
		bonus += streak * B.value("streak_damage")
	if amount("crowd") > 0:
		bonus += minf(maxi(0, count - 1) * B.value("crowd_damage"), B.value("crowd_cap"))
	if amount("finisher") > 0 and health_ratio <= B.value("finisher_threshold"):
		bonus += B.value("finisher_damage")
	if buff == 0:
		bonus += B.value("buff_power")
	var value := amount("damage") * (1.0 + bonus)
	if bool(context.get("critical", false)):
		value *= 2.0 + amount("crit_damage_bonus")
	return {"damage": value, "execute": first and roll(amount("execute"))}

func on_break(critical: bool, executed: bool) -> Dictionary:
	var gold := 0
	var heal := 0.0
	if amount("combo") > 0:
		combo_kills += 1
		combo = combo_kills / 10
		combo_remaining = maxf(B.value("combo_time_min"), B.value("combo_duration") + amount("combo_time_bonus") - combo * B.value("combo_time_decay"))
	if amount("gold_drop") > 0 and roll(B.value("drop_chance") + amount("drop_chance_bonus")):
		gold += int(B.value("drop_gold") + amount("drop_gold_bonus"))
	if amount("break_heal") > 0 and roll(B.value("break_heal_chance") + amount("break_heal_chance_bonus")):
		heal += B.value("break_heal") + amount("break_heal_bonus")
	if critical:
		gold += int(amount("crit_gold"))
	if executed:
		gold += int(amount("execute_gold"))
	return {"gold": gold, "heal": heal}

func on_gem() -> Dictionary:
	if amount("gem_buff") > 0:
		buff = random.randi_range(0, 2)
		buff_remaining = B.value("buff_duration")
	return {"gold": int(amount("gem_pickup_gold")), "heal": amount("recovery_per_gem")}

func roll(chance: float) -> bool:
	return chance > 0.0 and random.randf() < clampf(chance, 0.0, 1.0)
