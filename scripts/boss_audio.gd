extends Node
const Bank = preload("res://scripts/boss_audio_bank.gd")
const VOICES := 8
var players: Array[AudioStreamPlayer] = []
var cursor := 0
var last_play: Dictionary = {}
var cue_count := 0
var last_cue := ""
var impact_mixer: Node

func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)

func play(stage: int, event: String, pitch: float = 1.0, secondary: bool = false) -> void:
	var cue := "%d_%s" % [clampi(stage,0,6),event]
	if not Bank.CUES.has(cue): return
	if event in ["hit", "break"] and is_instance_valid(impact_mixer):
		impact_mixer.play_external_contact(Bank.CUES[cue], -15.0, pitch, event == "break", secondary)
		last_cue = cue
		cue_count += 1
		return
	var now := Time.get_ticks_msec()
	if now-int(last_play.get(cue,-9999)) < (70 if event == "hit" else 110): return
	last_play[cue] = now
	var index := 7 if event == "victory" else 6 if event == "entry" else cursor
	if index < 6: cursor = (cursor+1)%6
	var player := players[index]
	player.stop()
	player.stream = Bank.CUES[cue]
	player.volume_db = -12.0 if event in ["entry","victory"] else -15.0
	player.pitch_scale = pitch
	player.play()
	last_cue = cue
	cue_count += 1

func stop_all() -> void:
	for player in players: player.stop()
