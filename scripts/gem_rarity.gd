extends RefCounted
## One source of truth for cargo, 3D gems, UI and crack-light grades.
const COUNT := 7
const EXOTIC := 6
const NAMES := ["COMMON","SPECIAL","RARE","LEGENDARY","MYTHIC","ANCIENT","EXOTIC"]
const LABELS := ["일반","특별","희귀","전설","신화","고대","이형"]
const GOLD := preload("res://scripts/game_balance.gd").GEM_GOLD
const COLORS: Array[Color] = [Color("f3faff"),Color("64ff86"),Color("4896ff"),Color("ffe15b"),Color("be65ff"),Color("ff4c61"),Color("f1ddff")]

static func empty_counts() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(COUNT)
	return counts
