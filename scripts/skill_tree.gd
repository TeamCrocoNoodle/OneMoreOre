extends RefCounted
## Purchases, discovery and stat aggregation for the reference graph.
const Catalog = preload("res://scripts/skill_catalog.gd")
const B = preload("res://scripts/skill_balance.gd")
var _catalog := Catalog.new()
var _owned: Dictionary = {"origin": true}
var _by_id: Dictionary = {}
var _neighbors: Dictionary = {}

func _init() -> void:
	for node: Dictionary in _catalog.nodes:
		_by_id[node.id] = node
		_neighbors[node.id] = []
	for edge: Array in _catalog.edges:
		_neighbors[edge[0]].append(edge[1])
		_neighbors[edge[1]].append(edge[0])

func get_nodes() -> Array[Dictionary]:
	return _catalog.nodes.duplicate(true)

func get_node(id: String) -> Dictionary:
	return Dictionary(_by_id.get(id, {})).duplicate(true)

func get_edges() -> Array:
	return _catalog.edges.duplicate(true)

func is_unlocked(id: String) -> bool:
	return _owned.has(id)

func is_visible(id: String) -> bool:
	if is_unlocked(id):
		return true
	for other: String in _neighbors.get(id, []):
		if is_unlocked(other):
			return true
	return false

func can_purchase(id: String, gold: int) -> bool:
	return _purchase_failure(id, gold).is_empty()

func purchase(id: String, gold: int) -> Dictionary:
	var reason := _purchase_failure(id, gold)
	if not reason.is_empty():
		return {"ok": false, "gold": gold, "reason": reason}
	_owned[id] = true
	return {"ok": true, "gold": gold - int(_by_id[id].cost), "reason": ""}

func stats(disabled_categories: Array[String] = []) -> Dictionary:
	var s := {}
	for node: Dictionary in _catalog.nodes:
		for key: String in node.effects:
			s[key] = float(s.get(key, 0.0)) + (float(node.effects[key]) if is_unlocked(node.id) and not disabled_categories.has(str(node.category)) else 0.0)
	s.damage = maxf(float(s.damage), 0.01)
	s.duration = 30.0 + float(s.duration)
	s.attack_speed = 1.0 + float(s.attack_speed)
	s["attack_radius"] = B.value("base_radius") * (1.0 + float(s.range_bonus))
	s["drain_rate"] = maxf(0.1, 1.0 - float(s.drain_reduction))
	s["gem_value_multiplier"] = 1.0 + float(s.gem_value_bonus)
	s["income_multiplier"] = 1.0 + float(s.income_bonus)
	s["extra_common_gems"] = 0
	s["stone_health_reduction"] = 0
	s["revive_count"] = (1 + int(s.revive_count_bonus)) if s.revive > 0 else 0
	s["revive_fraction"] = B.value("revive_fraction") + float(s.revive_fraction_bonus)
	s["golden_chance"] = (B.value("golden_chance") + float(s.golden_chance_bonus)) if s.golden_day > 0 else 0.0
	return s

func _purchase_failure(id: String, gold: int) -> String:
	if not _by_id.has(id):
		return "unknown_node"
	if is_unlocked(id):
		return "already_unlocked"
	if not is_visible(id):
		return "hidden"
	if gold < int(_by_id[id].cost):
		return "insufficient_gold"
	return ""
