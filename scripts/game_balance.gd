extends RefCounted
## Campaign balance v1. All values are gameplay values, not elapsed-time gates.
const SKILL_DEPTH_COSTS := [0, 60, 160, 400, 800, 1800, 4000, 9000, 22000, 180000, 450000, 1000000, 2100000, 3750000, 6000000, 9000000, 12600000, 16800000, 21600000]
const SKILL_PREMIUMS := {"shock":3.0,"combo":2.0,"extra":2.0,"critical":1.4,"resonance":1.7,"healing":1.25,"bomb":1.5,"golden_day":1.5,"revive":1.3}
const MAIN_PRICES := [0, 800, 8500, 65000, 400000, 10000000]
const MAIN_POWER := [1.0, 1.7, 2.8, 3.8, 6.0, 12.0]
const MAIN_SPEED := [1.0, 1.05, 1.0, 1.15, 2.5, 3.0]
const MAIN_RADIUS := [1.0, 1.0, 1.85, 1.15, 1.25, 1.8]
const AUX_PRICES := [900, 1300, 12000, 300000, 310000, 550000, 3500000]
const GEM_GOLD := [15, 60, 220, 800, 2400, 7200, 22000]
const ORE_GOLD := [0, 6500, 45000, 260000, 1500000, 6500000, 20000000]
const STONE_HEALTH := [3.0, 5.0, 8.0, 12.0, 18.0, 24.0, 32.0]
const COVER_HEALTH := [12.0, 20.0, 32.0, 48.0, 72.0, 96.0, 128.0]
const GEM_CAP := [12, 16, 22, 28, 36, 44, 52]
const BOSS_ORE_GOALS := [18, 24, 32, 40, 48, 56, 160]
const BOSS_HEALTH := [14.0, 28.0, 90.0, 150.0, 260.0, 240.0, 1400.0]
const BOSS_REWARDS := [1500, 9000, 50000, 260000, 900000, 2400000, 5000000]
const RECOVERY_BUDGET := 0.80
const CRUSHER_COOLDOWN := 30.0

static func skill_cost(id: String, depth: int) -> int:
	if depth <= 0: return 0
	var base: int = SKILL_DEPTH_COSTS[mini(depth,SKILL_DEPTH_COSTS.size()-1)]
	return roundi(base * float(SKILL_PREMIUMS.get(id,1.0)) / 10.0) * 10

static func stone_health(stage: int, layer: int, seed_value: int) -> float:
	# Small variation retains harder inner stone without cancelling late one-hit breaks.
	var variation := 1.0 + (0.12 if posmod(seed_value,5) == 0 else 0.0)
	return STONE_HEALTH[clampi(stage,0,6)] * (1.0+layer*0.06) * variation

static func boss_aux_damage(attack: float, plate_health: float) -> float:
	return minf(plate_health * 0.25, maxf(4.0, attack * 2.0))

static func gold_label(amount: int) -> String:
	var digits := str(maxi(0,amount))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length()-i)%3 == 0: result += ","
		result += digits[i]
	return result
