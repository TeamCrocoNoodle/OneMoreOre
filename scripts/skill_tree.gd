extends RefCounted
## One-time purchases; the graph and the resulting gameplay values live here.

const NODES: Array[Dictionary] = [
	{"id": "origin", "title": "채굴의 시작", "description": "새로운 기술로 채굴을 발전시키세요.", "icon": "origin", "category": "ore", "grid": Vector2i(0, 0), "cost": 0},
	{"id": "vitality", "title": "긴 호흡", "description": "최대 채굴 시간 +5초", "icon": "vitality", "category": "health", "grid": Vector2i(-1, -1), "cost": 20},
	{"id": "power", "title": "강한 타격", "description": "곡괭이 공격력 +1", "icon": "power", "category": "attack", "grid": Vector2i(1, -1), "cost": 25},
	{"id": "appraisal", "title": "보석 감정", "description": "모든 보석 판매 단가 +20%", "icon": "appraisal", "category": "gold", "grid": Vector2i(1, 1), "cost": 30},
	{"id": "rich_ore", "title": "풍부한 광맥", "description": "새 원석마다 일반 보석 +1개", "icon": "rich_ore", "category": "ore", "grid": Vector2i(-1, 1), "cost": 40},
	{"id": "recovery", "title": "발견의 활력", "description": "보석 획득 시 채굴 시간 1초 회복\n최대 채굴 시간까지만 회복됩니다.", "icon": "recovery", "category": "health", "grid": Vector2i(-2, 0), "cost": 35},
	{"id": "speed", "title": "빠른 손놀림", "description": "곡괭이 공격 속도 +20%", "icon": "speed", "category": "attack", "grid": Vector2i(2, 0), "cost": 40},
	{"id": "reach", "title": "넓은 타격", "description": "타격점에서 0.65m 안의 표면 조각을\n최대 2개까지 추가 타격합니다.", "icon": "reach", "category": "attack", "grid": Vector2i(2, 1), "cost": 55},
	{"id": "soft_ore", "title": "무른 돌", "description": "일반 돌의 체력 -1\n체력은 최소 1입니다.", "icon": "soft_ore", "category": "ore", "grid": Vector2i(0, 2), "cost": 50},
]

const EDGES := [
	["origin", "vitality"], ["origin", "power"],
	["origin", "appraisal"], ["origin", "rich_ore"],
	["vitality", "recovery"], ["rich_ore", "recovery"],
	["power", "speed"], ["speed", "reach"], ["appraisal", "reach"],
	["appraisal", "soft_ore"], ["rich_ore", "soft_ore"],
]

var _owned: Dictionary = {"origin": true}


func get_nodes() -> Array[Dictionary]:
	return NODES.duplicate(true)


func get_node(id: String) -> Dictionary:
	for node: Dictionary in NODES:
		if node.id == id:
			return node.duplicate(true)
	return {}


func get_edges() -> Array:
	return EDGES.duplicate(true)


func is_unlocked(id: String) -> bool:
	return _owned.has(id)


func is_visible(id: String) -> bool:
	if is_unlocked(id):
		return true
	for edge: Array in EDGES:
		if (edge[0] == id and is_unlocked(edge[1])) or (edge[1] == id and is_unlocked(edge[0])):
			return true
	return false


func can_purchase(id: String, gold: int) -> bool:
	return _purchase_failure(id, gold).is_empty()


func purchase(id: String, gold: int) -> Dictionary:
	var reason := _purchase_failure(id, gold)
	if not reason.is_empty():
		return {"ok": false, "gold": gold, "reason": reason}
	var node := get_node(id)
	_owned[id] = true
	return {"ok": true, "gold": gold - int(node.cost), "reason": ""}


func stats() -> Dictionary:
	return {
		"duration": 35.0 if is_unlocked("vitality") else 30.0,
		"recovery_per_gem": 1.0 if is_unlocked("recovery") else 0.0,
		"damage": 2.0 if is_unlocked("power") else 1.0,
		"attack_speed": 1.2 if is_unlocked("speed") else 1.0,
		"attack_radius": 0.65 if is_unlocked("reach") else 0.0,
		"gem_value_multiplier": 1.2 if is_unlocked("appraisal") else 1.0,
		"extra_common_gems": 1 if is_unlocked("rich_ore") else 0,
		"stone_health_reduction": 1 if is_unlocked("soft_ore") else 0,
	}


func _purchase_failure(id: String, gold: int) -> String:
	var node := get_node(id)
	if node.is_empty():
		return "unknown_node"
	if is_unlocked(id):
		return "already_unlocked"
	if not is_visible(id):
		return "hidden"
	if gold < int(node.cost):
		return "insufficient_gold"
	return ""
