extends RefCounted
const Balance = preload("res://scripts/game_balance.gd")
## Main-tool ownership and campaign balance, shared by the shop and mining.
const CATALOG: Array[Dictionary] = [
	{"id": "pickaxe", "kind": "main", "title": "곡괭이", "price": Balance.MAIN_PRICES[0], "power": Balance.MAIN_POWER[0], "speed": Balance.MAIN_SPEED[0], "radius": Balance.MAIN_RADIUS[0], "critical": 0.0, "burst": 1, "color": Color("b5e0e1"), "description": "균형 잡힌 기본 채굴 도구.\n처음부터 사용할 수 있습니다."},
	{"id": "axe", "kind": "main", "title": "도끼", "price": Balance.MAIN_PRICES[1], "power": Balance.MAIN_POWER[1], "speed": Balance.MAIN_SPEED[1], "radius": Balance.MAIN_RADIUS[1], "critical": 0.20, "burst": 1, "color": Color("dfa37c"), "description": "날카로운 날로 약점을 가릅니다.\n치명타 확률 +20%. 스킬 없이도 치명타가 발생합니다."},
	{"id": "hammer", "kind": "main", "title": "망치", "price": Balance.MAIN_PRICES[2], "power": Balance.MAIN_POWER[2], "speed": Balance.MAIN_SPEED[2], "radius": Balance.MAIN_RADIUS[2], "critical": 0.0, "burst": 1, "color": Color("e3b86b"), "description": "넓은 머리로 주변 돌까지 부숩니다.\n공격 범위 ×1.85."},
	{"id": "jackhammer", "kind": "main", "title": "착암기", "price": Balance.MAIN_PRICES[3], "power": Balance.MAIN_POWER[3], "speed": Balance.MAIN_SPEED[3], "radius": Balance.MAIN_RADIUS[3], "critical": 0.0, "burst": 3, "color": Color("e6a15d"), "description": "한 번 누르면 3번 연속으로 타격합니다.\n각 타격은 현재 조준 위치를 따라갑니다."},
	{"id": "drill", "kind": "main", "title": "드릴", "price": Balance.MAIN_PRICES[4], "power": Balance.MAIN_POWER[4], "speed": Balance.MAIN_SPEED[4], "radius": Balance.MAIN_RADIUS[4], "critical": 0.0, "burst": 1, "color": Color("81bce7"), "description": "회전하는 날로 빠르게 파고듭니다.\n공격 속도 ×2.5. 누르고 있으면 연속 채굴합니다."},
	{"id": "gold_pickaxe", "kind": "main", "title": "황금 곡괭이", "price": Balance.MAIN_PRICES[5], "power": Balance.MAIN_POWER[5], "speed": Balance.MAIN_SPEED[5], "radius": Balance.MAIN_RADIUS[5], "critical": 0.0, "burst": 1, "color": Color("ffe09a"), "description": "가장 강한 일격을 가진 최종 곡괭이.\n넓은 공격 범위와 가장 빠른 스윙을 갖췄습니다."},
]
var equipped := "pickaxe"
var _owned := {"pickaxe": true}

static func definition(id: String) -> Dictionary:
	for entry: Dictionary in CATALOG:
		if entry.id == id:
			return entry.duplicate(true)
	return {}

func get_catalog() -> Array[Dictionary]:
	var result := CATALOG.duplicate(true)
	for entry in result:
		entry["owned"] = is_owned(entry.id)
		entry["equipped"] = entry.id == equipped
	return result

func is_owned(id: String) -> bool:
	return _owned.has(id)

func can_acquire(id: String, gold: int) -> bool:
	var entry := definition(id)
	return not entry.is_empty() and not is_owned(id) and gold >= int(entry.price)

func acquire(id: String, gold: int) -> Dictionary:
	if not can_acquire(id, gold):
		return {"ok": false, "gold": gold}
	_owned[id] = true
	equipped = id
	return {"ok": true, "gold": gold - int(definition(id).price)}

func equip(id: String) -> bool:
	if not is_owned(id) or equipped == id:
		return false
	equipped = id
	return true

func apply_to(skill_stats: Dictionary) -> Dictionary:
	var result := skill_stats.duplicate()
	var tool := definition(equipped)
	result.damage = float(result.damage) * float(tool.power)
	result.attack_speed = float(result.attack_speed) * float(tool.speed)
	result["tool_radius"] = float(tool.radius)
	result["tool_critical"] = float(tool.critical)
	return result
