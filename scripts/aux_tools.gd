extends RefCounted
const Balance = preload("res://scripts/game_balance.gd")
## Purchased auxiliary tools work together. All seven can remain equipped together.
const BEER_HEALTH := 6.0
const LASER_MIN := 10.0
const LASER_MAX := 16.0
const PIN_CHANCE := 0.35
const PIN_HITS := 3
const PIN_RADIUS := 2.1
const CRUSHER_COOLDOWN := Balance.CRUSHER_COOLDOWN
const CRUSHER_RECOVERY := 0.5
const CATALOG: Array[Dictionary] = [
	{"id":"laser","kind":"aux","title":"레이저","price":Balance.AUX_PRICES[0],"headline":"돌 조각 즉시 제거","subtitle":"10–16초마다 자동 발사","description":"채굴 중 무작위 간격으로 발사합니다.\n노출된 돌 조각 하나를 즉시 파괴합니다.","color":Color("75dce5")},
	{"id":"beer","kind":"aux","title":"맥주","price":Balance.AUX_PRICES[1],"headline":"최대 체력 +6","subtitle":"구매 후 계속 적용","description":"채굴을 조금 더 오래 이어갑니다.\n스킬의 최대 체력 증가와 함께 적용됩니다.","color":Color("edbb60")},
	{"id":"detector","kind":"aux","title":"탐지기","price":Balance.AUX_PRICES[2],"headline":"가까울수록 강한 신호","subtitle":"조준 위치를 기준으로 탐색","description":"가장 가까운 보석까지의 거리를 표시합니다.\n공격 범위와 무관하게 와이파이 신호가 강해집니다.","color":Color("8ee0b7")},
	{"id":"crusher","kind":"aux","title":"분쇄기","price":Balance.AUX_PRICES[3],"headline":"원석 분쇄 · 보석 가치 50% 회수","subtitle":"R · 컨트롤러 X · 화면 버튼","description":"주 도구의 공격력에 비례해 원석 전체를 분쇄합니다.\n단단한 원석은 약해진 상태로 남습니다.\n회수한 보석은 가치의 50%, 일반 돌은 정산하지 않습니다.\n재사용 대기시간 30초. 이미 모은 보석의 가치는 유지됩니다.","color":Color("e7a866")},
	{"id":"xray","kind":"aux","title":"엑스레이","price":Balance.AUX_PRICES[4],"headline":"원석 속 보석 개수 확인","subtitle":"현재 남은 보석 수 표시","description":"아직 원석 안에 남아 있는 보석을 셉니다.\n보석의 위치나 등급은 표시하지 않습니다.","color":Color("96dce7")},
	{"id":"pin","kind":"aux","title":"정","price":Balance.AUX_PRICES[5],"headline":"끝까지 박으면 주변 파괴","subtitle":"원석마다 35% 확률로 등장","description":"돌 사이에 박힌 정을 직접 때립니다.\n3번 때려 깊이 박으면 주변 돌 조각이 터집니다.","color":Color("d8c18b")},
	{"id":"detonator","kind":"aux","title":"기폭장치","price":Balance.AUX_PRICES[6],"headline":"원석 전체에 강력한 폭파 피해","subtitle":"Space · 컨트롤러 L3 · 화면 버튼","description":"주 도구의 공격력에 비례해 원석 전체를 폭파합니다.\n단단한 원석은 약해진 상태로 남습니다.\n파괴한 돌과 보석의 가치를 전부 회수합니다.\n채굴 라운드마다 한 번 사용할 수 있습니다.","color":Color("eb9472")},
]
var _owned: Dictionary = {}

static func definition(id: String) -> Dictionary:
	for entry: Dictionary in CATALOG:
		if entry.id == id: return entry.duplicate(true)
	return {}

func is_owned(id: String) -> bool:
	return _owned.has(id)

func get_catalog() -> Array[Dictionary]:
	var entries := CATALOG.duplicate(true)
	for entry in entries:
		entry["owned"] = is_owned(entry.id)
		entry["equipped"] = is_owned(entry.id)
	return entries

func acquire(id: String, gold: int) -> Dictionary:
	var entry := definition(id)
	if entry.is_empty() or is_owned(id) or gold < int(entry.price):
		return {"ok":false,"gold":gold}
	_owned[id] = true
	return {"ok":true,"gold":gold-int(entry.price)}

func apply_to(values: Dictionary) -> Dictionary:
	var result := values.duplicate()
	if is_owned("beer"):
		result.duration = float(result.get("duration",30.0))+BEER_HEALTH
	return result
