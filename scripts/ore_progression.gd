extends RefCounted
const Balance = preload("res://scripts/game_balance.gd")
const Skills = preload("res://scripts/skill_balance.gd")
## Campaign victories advance ore and rarity together, regardless of mining income.
## Without a campaign (cleared_bosses = -1), committed income selects the ore.
const STAGES: Array[Dictionary] = [
	{"id":"weathered","title":"풍화 원석","gold":Balance.ORE_GOLD[0],"radius":Balance.ORE_RADII[0],"layers":Balance.ORE_LAYERS[0],"gems":[0,0,0,1],"weights":[75,25,0,0,0,0],"gem_cap":Balance.GEM_CAP[0],"color":Color("7b8081"),"accent":Color("b1b7b8"),"theme":0,"bevel":1.0,"relief":1.0,"face":0.925,"corners":1.0},
	{"id":"moss","title":"이끼 광맥","gold":Balance.ORE_GOLD[1],"radius":Balance.ORE_RADII[1],"layers":Balance.ORE_LAYERS[1],"gems":[0,0,0,0,1,1,2],"weights":[52,36,12,0,0,0],"gem_cap":Balance.GEM_CAP[1],"color":Color("697957"),"accent":Color("9cab6a"),"theme":1,"bevel":1.0,"relief":1.1,"face":0.915,"corners":1.2},
	{"id":"frost","title":"서리 광맥","gold":Balance.ORE_GOLD[2],"radius":Balance.ORE_RADII[2],"layers":Balance.ORE_LAYERS[2],"gems":[0,0,0,1,1,1,2,2,3],"weights":[30,40,26,4,0,0],"gem_cap":Balance.GEM_CAP[2],"color":Color("557e96"),"accent":Color("abd9dc"),"theme":2,"bevel":0.65,"relief":0.7,"face":0.950,"corners":0.65},
	{"id":"pyrite","title":"황철 광맥","gold":Balance.ORE_GOLD[3],"radius":Balance.ORE_RADII[3],"layers":Balance.ORE_LAYERS[3],"gems":[0,0,1,1,1,2,2,2,3,3,3,4],"weights":[17,29,36,15,3,0],"gem_cap":Balance.GEM_CAP[3],"color":Color("946b3f"),"accent":Color("d4ad61"),"theme":3,"bevel":1.2,"relief":1.0,"face":0.930,"corners":0.7},
	{"id":"obsidian","title":"흑요 광맥","gold":Balance.ORE_GOLD[4],"radius":Balance.ORE_RADII[4],"layers":Balance.ORE_LAYERS[4],"gems":[0,1,1,1,2,2,2,2,3,3,3,3,4,4,4,5],"weights":[8,16,38,28,9,1],"gem_cap":Balance.GEM_CAP[4],"color":Color("534664"),"accent":Color("a18baf"),"theme":4,"bevel":0.48,"relief":0.8,"face":0.957,"corners":0.55},
	{"id":"primordial","title":"태고의 화산암","gold":Balance.ORE_GOLD[5],"radius":Balance.ORE_RADII[5],"layers":Balance.ORE_LAYERS[5],"gems":[0,1,1,2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,5],"weights":[4,8,24,36,22,6],"gem_cap":Balance.GEM_CAP[5],"color":Color("574143"),"accent":Color("b97859"),"theme":5,"bevel":0.85,"relief":1.25,"face":0.913,"corners":1.15},
	{"id":"exotic","title":"이형의 광맥","gold":Balance.ORE_GOLD[6],"radius":Balance.ORE_RADII[6],"layers":Balance.ORE_LAYERS[6],"gems":[0,1,2,2,2,3,3,3,3,3,4,4,4,4,4,4,4,5,5,5,5,5,5,6,6,6,6,6,6],"weights":[2,4,12,25,30,20,7],"gem_cap":Balance.GEM_CAP[6],"color":Color("6d647d"),"accent":Color("e9e0f5"),"theme":6,"bevel":0.60,"relief":0.80,"face":0.946,"corners":0.65},
]

static func stage_for(gold: int) -> int:
	var stage := 0
	for i in STAGES.size():
		if gold >= int(STAGES[i].gold): stage = i
	return stage

static func profile(gold: int, cleared_bosses: int = -1) -> Dictionary:
	var index := stage_for(gold) if cleared_bosses < 0 else clampi(cleared_bosses,0,STAGES.size()-1)
	var result := STAGES[index].duplicate(true)
	result["index"] = index
	result["rarity_cap"] = 6 if cleared_bosses < 0 else clampi(cleared_bosses,0,6)
	for i in result.gems.size(): result.gems[i] = mini(result.gems[i],result.rarity_cap)
	result["stone_health"] = Balance.STONE_HEALTH[index]
	result["cover_health"] = Balance.COVER_HEALTH[index]
	result["pieces"] = 0
	for count: int in result.layers: result.pieces += count
	result["stride"] = (float(result.radius)-1.04)/(result.layers.size()-1)
	result["thickness"] = float(result.stride)+0.08
	return result

static func status(gold: int, cleared_bosses: int = -1) -> Dictionary:
	var info := profile(gold,cleared_bosses)
	var last: bool = info.index == STAGES.size()-1
	var next_gold: int = STAGES[mini(info.index+1,STAGES.size()-1)].gold
	info["earned"] = maxi(0,gold)
	info["next_gold"] = next_gold
	info["remaining"] = maxi(0,next_gold-gold)
	info["progress"] = 1.0 if last else clampf(float(gold-int(info.gold))/float(next_gold-int(info.gold)),0.0,1.0)
	info["maxed"] = last
	return info

static func roll_grade(info: Dictionary, random: RandomNumberGenerator) -> int:
	var ticket := random.randf()*100.0
	for grade in info.weights.size():
		ticket -= float(info.weights[grade])
		if ticket < 0: return mini(grade,int(info.get("rarity_cap",6)))
	return mini(info.weights.size()-1,int(info.get("rarity_cap",6)))

static func gem_plan(info: Dictionary, stats: Dictionary, random: RandomNumberGenerator) -> Dictionary:
	var grades: Array[int] = []
	var bands: Array[int] = []
	grades.assign(info.gems)
	for i in int(stats.get("extra_common_gems",0)): grades.append(0)
	for i in grades.size(): bands.append(1+i%(info.layers.size()-1))
	for depth in range(1,info.layers.size()):
		var free_sockets: int = info.layers[depth]-bands.count(depth)
		for i in free_sockets:
			if grades.size() >= int(info.gem_cap): break
			if float(stats.get("gem_spawn_bonus",0)) > 0 and random.randf() < float(stats.gem_spawn_bonus):
				grades.append(0 if int(info.index) == 0 else roll_grade(info,random))
				bands.append(depth)
	for i in grades.size():
		if random.randf() < float(stats.get("rare_spawn_bonus",0)):
			var ticket := random.randf()
			var grade := 2 if ticket < Skills.value("rare_cutoff") else 3 if ticket < Skills.value("legendary_cutoff") else 4 if ticket < Skills.value("mythic_cutoff") else 5
			grades[i] = maxi(grades[i],grade)
		grades[i] = mini(grades[i],int(info.rarity_cap))
	return {"grades":grades,"bands":bands}

static func color_for(info: Dictionary, original: Color, layer: int, seed_value: int) -> Color:
	if int(info.theme) == 0: return original
	var random := RandomNumberGenerator.new()
	random.seed = seed_value ^ 0x22737
	var base: Color = info.color
	base = base.lerp(Color(info.accent),random.randf_range(0.0,0.17))
	return Color(base.darkened(minf(0.18,layer*0.035))*random.randf_range(0.85,1.10),1.0)
