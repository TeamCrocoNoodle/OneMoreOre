class_name MiningRound
extends RefCounted
## Authoritative round cargo. Presentation never changes prices or awards twice.

enum Phase { READY, MINING, DRAINING, SETTLING, COMPLETE }
const DURATION := 30.0
const STONE_GOLD := 1
const GEM_GOLD := [10, 50, 200, 1000, 5000, 25000]
const GEM_LABELS := ["일반 보석", "특별 보석", "희귀 보석", "전설 보석", "신화 보석", "고대 보석"]

var phase: Phase = Phase.READY
var remaining := DURATION
var ordinary_stones := 0
var gem_counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
var wallet_gold := 0
var round_index := 1
var last_report: Dictionary = {}

func start() -> bool:
	if phase != Phase.READY:
		return false
	phase = Phase.MINING
	return true

func advance(delta: float) -> bool:
	if phase != Phase.MINING or not is_finite(delta) or delta <= 0.0:
		return false
	remaining = maxf(0.0, remaining - delta)
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

func record_gem(tier: int) -> bool:
	if phase != Phase.MINING or tier < 0 or tier >= gem_counts.size():
		return false
	gem_counts[tier] += 1
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
		var value: int = gem_counts[tier] * GEM_GOLD[tier]
		total += value
		rows.append({"kind": "gem", "tier": tier, "label": GEM_LABELS[tier], "count": gem_counts[tier], "unit_gold": GEM_GOLD[tier], "gold": value})
	last_report = {"rows": rows, "total": total, "wallet_before": wallet_gold, "wallet_after": wallet_gold + total,
		"round_index": round_index, "ordinary_stones": ordinary_stones, "gem_counts": gem_counts.duplicate()}
	phase = Phase.SETTLING
	return last_report.duplicate(true)

func commit_settlement() -> bool:
	if phase != Phase.SETTLING:
		return false
	wallet_gold += int(last_report["total"])
	# The report retains the breakdown; the physical cargo has been sold.
	ordinary_stones = 0
	gem_counts.fill(0)
	phase = Phase.COMPLETE
	return true

func new_round() -> bool:
	if phase != Phase.COMPLETE:
		return false
	round_index += 1
	remaining = DURATION
	ordinary_stones = 0
	gem_counts.fill(0)
	last_report.clear()
	phase = Phase.READY
	return true
