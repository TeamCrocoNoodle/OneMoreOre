extends RefCounted
## Campaign balance v2. Upgrade investment and boss resistance set the pace.
const SKILL_DEPTH_COSTS := [0, 60, 160, 400, 900, 2300, 6500, 18000, 50000, 180000, 450000, 1100000, 2500000, 4500000, 7000000, 11000000, 16000000, 23000000, 32000000]
const SKILL_PREMIUMS := {"shock":3.0,"combo":2.0,"extra":2.0,"critical":1.4,"resonance":1.7,"healing":1.25,"bomb":1.5,"golden_day":1.5,"revive":1.3}
const MAIN_PRICES := [0, 1200, 15000, 120000, 700000, 6000000]
const MAIN_POWER := [1.0, 2.2, 3.2, 20.0, 180.0, 2400.0]
const MAIN_SPEED := [1.0, 1.05, 1.0, 1.15, 2.5, 3.0]
const MAIN_RADIUS := [1.0, 1.0, 1.85, 1.15, 1.5, 2.5]
const AUX_PRICES := [3500, 5000, 50000, 300000, 310000, 550000, 3500000]
const GEM_GOLD := [15, 42, 320, 1500, 4200, 14000, 48000]
const ORE_GOLD := [0, 6500, 45000, 260000, 1500000, 6500000, 20000000]
const ORE_RADII := [2.6, 3.3, 4.2, 5.3, 6.7, 8.5, 10.8]
const ORE_LAYERS := [
	[38,24,12], [75,44,21,8], [129,85,50,24,8],
	[197,148,106,70,42,21,8], [323,258,201,151,108,71,43,21,8],
	[550,458,374,299,231,172,123,81,48,24,8],
	[893,773,662,560,466,380,304,235,175,125,82,49,24,8],
]
const STONE_HEALTH := [3.0, 9.0, 70.0, 750.0, 2000.0, 10000.0, 65000.0]
const COVER_HEALTH := [12.0, 36.0, 280.0, 3000.0, 8000.0, 40000.0, 260000.0]
const GEM_CAP := [12, 18, 24, 32, 42, 54, 68]
const BOSS_ORE_GOALS := [18, 24, 12, 20, 24, 24, 48]
const BOSS_HEALTH := [60.0, 350.0, 2500.0, 56000.0, 50000.0, 490000.0, 15000000.0]
const BOSS_REWARDS := [50, 180, 600, 1800, 6000, 18000, 60000]
const BOMB_ARMOR_FRACTION := 0.65
const RECOVERY_BUDGET := 0.80
const CRUSHER_COOLDOWN := 30.0
const CRUSHER_WORK := 12000.0
const DETONATOR_WORK := 24000.0

static func bulk_damage(tool: String, attack: float, pieces: int) -> float:
	# A fixed total work budget is shared by the remaining stones. Larger and
	# tougher new ores resist the same tool until the player's attack catches up.
	return maxf(0.0,attack)*(CRUSHER_WORK if tool == "crusher" else DETONATOR_WORK)/maxi(1,pieces)

static func skill_cost(id: String, depth: int) -> int:
	if depth <= 0: return 0
	var base: int = SKILL_DEPTH_COSTS[mini(depth,SKILL_DEPTH_COSTS.size()-1)]
	return roundi(base * float(SKILL_PREMIUMS.get(id,1.0)) / 10.0) * 10

static func stone_health(stage: int, layer: int, seed_value: int) -> float:
	# Deeper layers retain resistance even after the exterior becomes easy to mine.
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
