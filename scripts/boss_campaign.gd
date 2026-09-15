extends RefCounted
const Balance = preload("res://scripts/game_balance.gd")
## Run-lifetime campaign. A failed attempt never unlocks a mineral or pays a bounty.
const BOSSES: Array[Dictionary] = [
	{"id":"regenerator","title":"되살아나는 거암","subtitle":"재생의 채석장","goal":Balance.BOSS_ORE_GOALS[0],"reward":Balance.BOSS_REWARDS[0],"radius":3.1,"shape":Vector3(.94,1.12,.94),"layers":[18,8],"health":Balance.BOSS_HEALTH[0],"color":Color("637975"),"accent":Color("a6edca"),"back":Color("183632"),"hint":"부서진 조각은 체력이 절반으로 줄어 두 번 재생합니다."},
	{"id":"bastion","title":"수호석의 성채","subtitle":"에메랄드 요새","goal":Balance.BOSS_ORE_GOALS[1],"reward":Balance.BOSS_REWARDS[1],"radius":3.35,"shape":Vector3(1.03,.94,.90),"layers":[22,10],"health":Balance.BOSS_HEALTH[1],"color":Color("466552"),"accent":Color("aad877"),"back":Color("243826"),"hint":"방패 문양의 보호석을 먼저 부수세요."},
	{"id":"wanderer","title":"빙결의 눈","subtitle":"유리서리 성소","goal":Balance.BOSS_ORE_GOALS[2],"reward":Balance.BOSS_REWARDS[2],"radius":3.55,"shape":Vector3(.86,1.12,.90),"layers":[28,12],"health":Balance.BOSS_HEALTH[2],"color":Color("547f9e"),"accent":Color("b9edff"),"back":Color("183049"),"hint":"이동하는 다섯 약점을 깨면 주변 돌도 무너집니다."},
	{"id":"timebomb","title":"황철 시한핵","subtitle":"멈춘 태엽의 금고","goal":Balance.BOSS_ORE_GOALS[3],"reward":Balance.BOSS_REWARDS[3],"radius":3.75,"shape":Vector3.ONE,"layers":[30,14],"health":Balance.BOSS_HEALTH[3],"color":Color("847047"),"accent":Color("ffd57b"),"back":Color("382d19"),"hint":"60초 안에 갑피 65%를 부순 뒤, 정지선을 찾아 자르세요."},
	{"id":"thorn","title":"가시 흑요석","subtitle":"검은 가시 정원","goal":Balance.BOSS_ORE_GOALS[4],"reward":Balance.BOSS_REWARDS[4],"radius":4.0,"shape":Vector3(1.0,.94,1.0),"layers":[34,16],"health":Balance.BOSS_HEALTH[4],"color":Color("51405d"),"accent":Color("dba1f5"),"back":Color("2b193a"),"hint":"가시가 솟았을 때 직접 공격하면 스태미나를 잃습니다."},
	{"id":"artillery","title":"화산 포격수","subtitle":"붉은 화산의 포구","goal":Balance.BOSS_ORE_GOALS[5],"reward":Balance.BOSS_REWARDS[5],"radius":4.3,"shape":Vector3(1.12,.90,.94),"layers":[38,18],"health":Balance.BOSS_HEALTH[5],"color":Color("6c4144"),"accent":Color("ffad86"),"back":Color("401d28"),"hint":"날아오는 돌을 쳐내고, 포격이 멈추면 본체를 공격하세요."},
	{"id":"exotic_core","title":"이형의 심장","subtitle":"광맥의 끝","goal":Balance.BOSS_ORE_GOALS[6],"reward":Balance.BOSS_REWARDS[6],"radius":4.6,"shape":Vector3(.90,1.10,.90),"layers":[42,24,12],"health":Balance.BOSS_HEALTH[6],"color":Color("464151"),"accent":Color("f0e2ff"),"back":Color("211d37"),"hint":"마지막 원석의 모든 조각을 부수세요."},
]
var cleared := 0
var ore_clears := PackedInt32Array([0,0,0,0,0,0,0])
var round_clears := PackedInt32Array([0,0,0,0,0,0,0])
var attempted_this_round := false
var active := false
var last_result := ""
var last_boss := -1
var won: bool:
	get: return cleared >= BOSSES.size()

func new_round() -> void:
	round_clears.fill(0)
	attempted_this_round = false
	active = false
	last_result = ""

func record_ore(stage: int) -> void:
	if stage < 0 or stage >= ore_clears.size() or active or won: return
	ore_clears[stage] += 1
	round_clears[stage] += 1

func eligible(stage: int) -> bool:
	return not won and not active and not attempted_this_round and stage == cleared and ore_clears[stage] >= int(BOSSES[stage].goal) and round_clears[stage] >= 1

func begin(stage: int) -> bool:
	if not eligible(stage): return false
	active = true
	attempted_this_round = true
	last_boss = stage
	return true

func finish(victory: bool) -> int:
	if not active: return 0
	active = false
	last_result = "victory" if victory else "defeat"
	if not victory: return 0
	var reward: int = BOSSES[cleared].reward
	cleared += 1
	return reward

func decorate_status(info: Dictionary) -> Dictionary:
	info["boss_cleared"] = cleared
	info["rarity_cap"] = mini(cleared,6)
	info["game_won"] = won
	if not won:
		info["boss_count"] = ore_clears[cleared]
		info["boss_goal"] = BOSSES[cleared].goal
		info["boss_title"] = BOSSES[cleared].title
		info["boss_gate"] = int(info.index) == cleared
	return info
