extends RefCounted
## Campaign v1 effects. Prices share the campaign economy table.
const Balance = preload("res://scripts/game_balance.gd")
const VALUES := {
	"base_power": 1.0, "power": 0.8, "speed": 0.16, "range": 0.25, "base_radius": 0.38,
	"ore_damage": 0.35, "first_damage": 0.4, "streak_damage": 0.08, "streak_cap": 5,
	"crowd_damage": 0.10, "crowd_cap": 0.50, "finisher_threshold": 0.30, "finisher_damage": 0.30,
	"combo_step": 0.01, "combo_duration": 6.0, "combo_time_step": 2.0,
	"combo_time_decay": 0.08, "combo_time_min": 2.0, "combo_speed_threshold": 5, "combo_speed": 0.25,
	"shock_chance": 0.08, "shock_chance_step": 0.04, "shock_damage": 0.55,
	"shock_damage_step": 0.25, "shock_range": 2.0, "shock_range_step": 0.4,
	"extra_chance": 0.20, "extra_chance_step": 0.10, "crit_chance_step": 0.05, "crit_damage_step": 0.25,
	"crit_gold": 8.0, "execute_gold": 20.0,
	"health": 4.0, "drain_reduction": 0.06, "spent_threshold": 12.0, "spent_threshold_reduction": 4.0,
	"spent_range": 0.25, "spent_range_step": 0.20, "low_health_threshold": 0.25,
	"low_health_threshold_step": 0.15, "low_health_speed": 0.25, "low_health_speed_step": 0.20,
	"revive_fraction": 0.15, "revive_fraction_step": 0.1, "break_heal_chance": 0.05,
	"break_heal_chance_step": 0.03, "break_heal": 0.35, "break_heal_step": 0.35,
	"gem_heal": 0.5, "gem_heal_step": 0.5,
	"income": 0.12, "gem_value": 0.2, "drop_chance": 0.08, "drop_chance_step": 0.04,
	"drop_gold": 3.0, "drop_gold_step": 3.0, "brilliant_chance": 0.04,
	"brilliant_chance_step": 0.02, "brilliant_value": 0.50, "brilliant_value_step": 0.25,
	"golden_chance": 0.015, "golden_chance_step": 0.015, "golden_pity": 0.005,
	"gem_spawn": 0.012, "rare_spawn": 0.04, "gem_gold": 5.0,
	"rare_cutoff": 0.76, "legendary_cutoff": 0.94, "mythic_cutoff": 0.99,
	"buff_duration": 5.0, "buff_power": 0.25, "buff_speed": 0.25, "buff_range": 0.30,
	"special_spawn": 0.025, "special_spawn_step": 0.015,
	"resonance_damage": 0.30, "resonance_damage_step": 0.15,
	"healing_amount": 1.0, "healing_amount_step": 0.25,
	"bomb_damage": 35.0, "bomb_damage_step": 0.35, "gold_stone_amount": 90.0, "gold_stone_step": 0.5,
	"neighbor_radius": 1.6
}

static func value(key: String) -> float:
	return float(VALUES[key])

static func percent(key: String) -> String:
	return "%s%%" % (value(key) * 100.0)

static func cost(id: String, depth: int) -> int:
	return Balance.skill_cost(id,depth)
