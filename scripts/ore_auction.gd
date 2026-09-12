extends RefCounted
## Independent gameplay draw. UI timing and decorative bids cannot reroll it.

const CHANGES := [-100, -50, 50, 100, 200]
const WEIGHTS := [23, 25, 25, 25, 2]
var rng := RandomNumberGenerator.new()
var previous_total_loss := false


func _init() -> void:
	rng.randomize()


func draw(base_gold: int) -> Dictionary:
	if base_gold <= 0:
		return {}
	var protected := previous_total_loss
	var outcome := outcome_for_ticket(rng.randi_range(0, 76 if protected else 99), protected)
	var change: int = CHANGES[outcome]
	# Gold is indivisible. Odd half-Gold is rounded down once, on the payout.
	var payout: int = base_gold * (100 + change) / 100
	previous_total_loss = outcome == 0
	return {"index": outcome, "change_percent": change, "base_gold": base_gold,
		"payout": payout, "delta": payout - base_gold, "protected": protected}


static func outcome_for_ticket(ticket: int, protected: bool) -> int:
	# After a full loss, the other four weights remain in the ratio 25:25:25:2.
	if ticket < 0 or ticket >= (77 if protected else 100):
		return -1
	for index in WEIGHTS.size():
		if protected and index == 0:
			continue
		ticket -= WEIGHTS[index]
		if ticket < 0:
			return index
	return -1
