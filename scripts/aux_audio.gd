extends Node
const Bank = preload("res://scripts/aux_audio_bank.gd")
const VOICES := 5
var players: Array[AudioStreamPlayer] = []
var cursor := 0
var cue_count := 0
var last_cue := ""

func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)

func play(kind: String, pitch: float = 1.0) -> void:
	if not Bank.CUES.has(kind) or players.is_empty(): return
	var player := players[cursor]
	cursor = (cursor+1)%VOICES
	player.stop()
	player.stream = Bank.CUES[kind]
	player.volume_db = -18.0 if kind == "detector_ping" else (-9.5 if kind == "detonator_blast" else -10.5)
	player.pitch_scale = pitch
	player.play()
	cue_count += 1
	last_cue = kind

func stop_all() -> void:
	for player in players: player.stop()
