class_name MiningRound
extends RefCounted
## Authoritative round cargo. Presentation never changes prices or awards twice.

enum Phase { READY, MINING, DRAINING, SETTLING, COMPLETE, AUCTION }
const Auction = preload("res://scripts/ore_auction.gd")
const Rarity = preload("res://scripts/gem_rarity.gd")
const Balance = preload("res://scripts/game_balance.gd")
const DURATION := 30.0
const STONE_GOLD := 1
const GEM_GOLD := Rarity.GOLD
const GEM_LABELS := ["일반 보석", "특별 보석", "희귀 보석", "전설 보석", "신화 보석", "고대 보석", "이형 보석"]

var phase: Phase = Phase.READY
var duration := DURATION
var remaining := DURATION
var gem_value_multiplier := 1.0
var ordinary_stones := 0
var gem_counts := Rarity.empty_counts()
var wallet_gold := 0
var lifetime_mining_gold := 0
var round_index := 1
var last_report: Dictionary = {}
var auction := Auction.new()
var _pending_auction: Dictionary = {}
var drain_rate := 1.0
var spent := 0.0
var recovered := 0.0
var revive_count := 0
var revive_fraction := 0.20
var revives_used := 0
var last_advance_revives := 0
var income_multiplier := 1.0
var bonus_gold := 0
var boss_reward := 0
var boss_name := ""
var gem_premium := Rarity.empty_counts()
var gem_discount := Rarity.empty_counts()
var crushed_counts := Rarity.empty_counts()
var golden_chance := 0.0
var golden_pity := 0.0
var golden_failures := 0
var reward_random := RandomNumberGenerator.new()

func _init() -> void:
	reward_random.randomize()

func apply_stats(values: Dictionary) -> void:
	# Purchase effects are configured between rounds, never halfway through
	# a cargo valuation or a running deadline.
	if phase != Phase.READY and phase != Phase.COMPLETE:
		return
	var next_duration := float(values.get("duration", DURATION))
	var next_multiplier := float(values.get("gem_value_multiplier", 1.0))
	duration = maxf(0.001, next_duration) if is_finite(next_duration) else DURATION
	gem_value_multiplier = maxf(0.0, next_multiplier) if is_finite(next_multiplier) else 1.0
	drain_rate = clampf(float(values.get("drain_rate", 1.0)), 0.1, 10.0)
	revive_count = maxi(0, int(values.get("revive_count", 0)))
	revive_fraction = clampf(float(values.get("revive_fraction", 0.2)), 0.01, 1.0)
	income_multiplier = maxf(1.0, float(values.get("income_multiplier", 1.0)))
	golden_chance = clampf(float(values.get("golden_chance", 0.0)), 0.0, 1.0)
	golden_pity = maxf(0.0, float(values.get("golden_pity", 0.0)))
	if phase == Phase.READY:
		remaining = duration

func seconds_remaining() -> float:
	return remaining / drain_rate

func seconds_capacity() -> float:
	return duration / drain_rate

func recover(amount: float) -> float:
	if phase != Phase.MINING or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var restored := minf(amount,minf(maxf(0.0,duration-remaining),maxf(0.0,duration*Balance.RECOVERY_BUDGET-recovered)))
	remaining += restored
	recovered += restored
	return restored

func refill_for_boss() -> void:
	# A fresh boss attempt always starts full, without spending the healing reserve.
	if phase == Phase.MINING: remaining = duration

func start() -> bool:
	if phase != Phase.READY:
		return false
	phase = Phase.MINING
	return true

func advance(delta: float) -> bool:
	last_advance_revives = 0
	if phase != Phase.MINING or not is_finite(delta) or delta <= 0.0:
		return false
	var consumption := delta * drain_rate
	while consumption > 0.0:
		var paid := minf(remaining, consumption)
		remaining -= paid
		spent += paid
		consumption -= paid
		if remaining > 0.0000001:
			break
		if revives_used >= revive_count:
			break
		revives_used += 1
		last_advance_revives += 1
		remaining = duration * revive_fraction
	if remaining <= 0.0000001:
		remaining = 0.0
		phase = Phase.DRAINING
		return true
	return false

func record_stone() -> bool:
	if phase != Phase.MINING:
		return false
	ordinary_stones += 1
	return true

func record_gem(tier: int, value_multiplier: float = 1.0, recovery: float = 1.0) -> bool:
	if phase != Phase.MINING or tier < 0 or tier >= gem_counts.size():
		return false
	gem_counts[tier] += 1
	var unit := roundi(float(GEM_GOLD[tier]) * gem_value_multiplier)
	var premium := roundi(unit * maxf(0.0, value_multiplier - 1.0))
	gem_premium[tier] += premium
	var factor := clampf(recovery,0.0,1.0) if is_finite(recovery) else 1.0
	gem_discount[tier] += unit+premium-roundi((unit+premium)*factor)
	if factor < 1.0: crushed_counts[tier] += 1
	return true

func record_bonus_gold(amount: int) -> bool:
	if phase != Phase.MINING or amount <= 0:
		return false
	bonus_gold += amount
	return true

func record_boss_reward(amount: int, title: String) -> bool:
	if phase != Phase.MINING or amount <= 0 or boss_reward > 0: return false
	boss_reward = amount
	boss_name = title
	return true

func begin_settlement() -> Dictionary:
	if phase != Phase.DRAINING:
		return last_report.duplicate(true)
	var rows: Array[Dictionary] = []
	var total := ordinary_stones * STONE_GOLD
	rows.append({"kind": "stone", "tier": -1, "label": "돌 조각", "count": ordinary_stones, "unit_gold": STONE_GOLD, "gold": total})
	for tier in gem_counts.size():
		if gem_counts[tier] <= 0:
			continue
		var unit_gold := roundi(float(GEM_GOLD[tier]) * gem_value_multiplier)
		var value: int = gem_counts[tier] * unit_gold + gem_premium[tier] - gem_discount[tier]
		total += value
		var row := {"kind": "gem", "tier": tier, "label": GEM_LABELS[tier], "count": gem_counts[tier], "unit_gold": unit_gold, "gold": value,"premium":gem_premium[tier]}
		if gem_premium[tier] > 0:
			row["formula"] = "%d개 × %d G · 찬란함 +%d G" % [gem_counts[tier], unit_gold, gem_premium[tier]]
		if gem_discount[tier] > 0:
			row["formula"] = "%s · 분쇄 −%d G" % [str(row.get("formula","%d개 × %d G" % [gem_counts[tier],unit_gold])),gem_discount[tier]]
			row["crushed_count"] = crushed_counts[tier]
			row["discount"] = gem_discount[tier]
		rows.append(row)
	var subtotal := total
	var income := roundi((subtotal + bonus_gold) * income_multiplier)
	var golden := false
	if income > 0 and golden_chance > 0:
		golden = reward_random.randf() < minf(1.0, golden_chance + golden_failures * golden_pity)
		golden_failures = 0 if golden else golden_failures + 1
	total = income * (2 if golden else 1)
	if total > subtotal:
		rows.append({"kind": "bonus", "tier": -1, "label": "황금의 날 ×2" if golden else "스킬 보너스", "count": 1, "unit_gold": total - subtotal, "gold": total - subtotal,
			"formula": "추가 획득 %d G · 수입 +%s%%" % [bonus_gold, (income_multiplier - 1.0) * 100.0]})
	if boss_reward > 0:
		total += boss_reward
		rows.append({"kind":"boss","tier":-1,"label":boss_name,"count":1,"unit_gold":boss_reward,"gold":boss_reward,"formula":"보스 최초 처치 보상"})
	last_report = {"rows": rows, "total": total, "wallet_before": wallet_gold, "wallet_after": wallet_gold + total,
		"round_index": round_index, "ordinary_stones": ordinary_stones, "gem_counts": gem_counts.duplicate(),
		"bonus_gold": bonus_gold, "income_multiplier": income_multiplier, "golden_day": golden, "subtotal": subtotal, "gem_premium": gem_premium.duplicate(),"gem_discount":gem_discount.duplicate(),"crushed_counts":crushed_counts.duplicate()}
	phase = Phase.SETTLING
	return last_report.duplicate(true)

func commit_settlement() -> bool:
	if phase != Phase.SETTLING:
		return false
	wallet_gold += int(last_report["total"])
	# Count the settled mining proceeds once. Purchases and auction adjustments
	# never alter this total, so spending cannot demote an unlocked ore.
	lifetime_mining_gold += maxi(0,int(last_report["total"]))
	# The report retains the breakdown; the physical cargo has been sold.
	ordinary_stones = 0
	gem_counts.fill(0)
	gem_premium.fill(0)
	gem_discount.fill(0)
	crushed_counts.fill(0)
	bonus_gold = 0
	boss_reward = 0
	boss_name = ""
	phase = Phase.COMPLETE
	return true

func new_round() -> bool:
	if phase != Phase.COMPLETE:
		return false
	round_index += 1
	gem_premium.fill(0)
	gem_discount.fill(0)
	crushed_counts.fill(0)
	bonus_gold = 0
	boss_reward = 0
	boss_name = ""
	spent = 0.0
	recovered = 0.0
	revives_used = 0
	last_advance_revives = 0
	remaining = duration
	ordinary_stones = 0
	gem_counts.fill(0)
	last_report.clear()
	_pending_auction.clear()
	phase = Phase.READY
	return true


func can_auction() -> bool:
	var stake := int(last_report.get("total", 0))
	return phase == Phase.COMPLETE and stake > 0 and wallet_gold >= stake and not last_report.has("auction")


func begin_auction() -> Dictionary:
	if not can_auction():
		return {}
	_pending_auction = auction.draw(int(last_report.total))
	_pending_auction["round_index"] = round_index
	_pending_auction["wallet_before"] = wallet_gold
	_pending_auction["wallet_after"] = wallet_gold + int(_pending_auction.delta)
	phase = Phase.AUCTION
	return _pending_auction.duplicate(true)


func commit_auction() -> bool:
	if phase != Phase.AUCTION or _pending_auction.is_empty():
		return false
	# Base settlement has already paid. Apply only its adjustment, once.
	wallet_gold += int(_pending_auction.delta)
	last_report["auction"] = _pending_auction.duplicate(true)
	last_report["final_total"] = int(_pending_auction.payout)
	last_report["wallet_after"] = wallet_gold
	_pending_auction.clear()
	phase = Phase.COMPLETE
	return true
