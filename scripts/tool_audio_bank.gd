extends RefCounted
## Offline-authored 48 kHz stereo PCM. No loading or synthesis on impact.
const BANKS := {
	"pickaxe": {
		"hits": [preload("res://assets/audio/tools/pickaxe_hit_01.wav"), preload("res://assets/audio/tools/pickaxe_hit_02.wav"), preload("res://assets/audio/tools/pickaxe_hit_03.wav")],
		"ores": [preload("res://assets/audio/tools/pickaxe_ore_01.wav"), preload("res://assets/audio/tools/pickaxe_ore_02.wav")],
		"break": preload("res://assets/audio/tools/pickaxe_break_01.wav"),
		"swing": preload("res://assets/audio/tools/pickaxe_swing_01.wav")
	},
	"axe": {
		"hits": [preload("res://assets/audio/tools/axe_hit_01.wav"), preload("res://assets/audio/tools/axe_hit_02.wav"), preload("res://assets/audio/tools/axe_hit_03.wav")],
		"ores": [preload("res://assets/audio/tools/axe_ore_01.wav"), preload("res://assets/audio/tools/axe_ore_02.wav")],
		"break": preload("res://assets/audio/tools/axe_break_01.wav"),
		"swing": preload("res://assets/audio/tools/axe_swing_01.wav")
	},
	"hammer": {
		"hits": [preload("res://assets/audio/tools/hammer_hit_01.wav"), preload("res://assets/audio/tools/hammer_hit_02.wav"), preload("res://assets/audio/tools/hammer_hit_03.wav")],
		"ores": [preload("res://assets/audio/tools/hammer_ore_01.wav"), preload("res://assets/audio/tools/hammer_ore_02.wav")],
		"break": preload("res://assets/audio/tools/hammer_break_01.wav"),
		"swing": preload("res://assets/audio/tools/hammer_swing_01.wav")
	},
	"jackhammer": {
		"hits": [preload("res://assets/audio/tools/jackhammer_hit_01.wav"), preload("res://assets/audio/tools/jackhammer_hit_02.wav"), preload("res://assets/audio/tools/jackhammer_hit_03.wav")],
		"ores": [preload("res://assets/audio/tools/jackhammer_ore_01.wav"), preload("res://assets/audio/tools/jackhammer_ore_02.wav")],
		"break": preload("res://assets/audio/tools/jackhammer_break_01.wav"),
		"swing": preload("res://assets/audio/tools/jackhammer_swing_01.wav")
	},
	"drill": {
		"hits": [preload("res://assets/audio/tools/drill_hit_01.wav"), preload("res://assets/audio/tools/drill_hit_02.wav"), preload("res://assets/audio/tools/drill_hit_03.wav")],
		"ores": [preload("res://assets/audio/tools/drill_ore_01.wav"), preload("res://assets/audio/tools/drill_ore_02.wav")],
		"break": preload("res://assets/audio/tools/drill_break_01.wav"),
		"swing": preload("res://assets/audio/tools/drill_swing_01.wav")
	},
	"gold_pickaxe": {
		"hits": [preload("res://assets/audio/tools/gold_pickaxe_hit_01.wav"), preload("res://assets/audio/tools/gold_pickaxe_hit_02.wav"), preload("res://assets/audio/tools/gold_pickaxe_hit_03.wav")],
		"ores": [preload("res://assets/audio/tools/gold_pickaxe_ore_01.wav"), preload("res://assets/audio/tools/gold_pickaxe_ore_02.wav")],
		"break": preload("res://assets/audio/tools/gold_pickaxe_break_01.wav"),
		"swing": preload("res://assets/audio/tools/gold_pickaxe_swing_01.wav")
	},
}
