extends Node
## Six authored main-tool banks and the shared discovery / respawn cues.
## The bank is prepared once; playback performs no file loading or synthesis.

const SAMPLE_RATE := 24000
const PLAYER_COUNT := 14
const TWO_PI := TAU
const ToolBank = preload("res://scripts/tool_audio_bank.gd")
const DISCOVERY_SAMPLE: AudioStreamWAV = preload("res://assets/audio/ore_discovery.wav")
const MIX_BUS := &"MiningSFX"
const DIRECT_INTERVAL_MSEC := 32
const SECONDARY_INTERVAL_MSEC := 120
const SECONDARY_GAIN_DB := -8.0
const CONTACT_VOICES := 3

var _hits: Array[AudioStreamWAV] = []
var _breaks: Array[AudioStreamWAV] = []
var _ore_hits: Array[AudioStreamWAV] = []
var _swings: Array[AudioStreamWAV] = []
var _reveal: AudioStreamWAV
var _discovery: AudioStreamWAV
var _respawn: AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _started: Array[int] = []
var _random := RandomNumberGenerator.new()
var _hit_index := -1
var _ore_hit_index := -1
var _swing_index := 0
var _last_swing_msec := -1000
var _last_contact_msec := -1000
var _last_secondary_msec := -1000
var _last_discovery_msec := -1000
var _last_discovery_special := false
var _volume_tweens: Array[Tween] = []
var _batch_depth := 0
var _batch_secondary := false
var _pending_cue: Dictionary = {}
var _played_count := 0
var _coalesced_count := 0
var _last_kind := ""
var tool_id := ""


func _ready() -> void:
	_random.randomize()
	set_tool("pickaxe")
	_reveal = DISCOVERY_SAMPLE
	_discovery = DISCOVERY_SAMPLE
	_respawn = _synthesize("respawn", 0.56, 7307)
	_ensure_mix_bus()
	for i in range(PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "MiningVoice%d" % i
		player.bus = MIX_BUS
		add_child(player)
		_players.append(player)
		_started.append(0)
		_volume_tweens.append(null)
	set_process(false)


static func _ensure_mix_bus() -> void:
	if AudioServer.get_bus_index(MIX_BUS) >= 0:
		return
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, MIX_BUS)
	AudioServer.set_bus_send(bus, &"Master")
	# Solo hits stay below the threshold. Only accumulated tails are compressed.
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -10.0
	compressor.ratio = 2.5
	compressor.attack_us = 3000.0
	compressor.release_ms = 90.0
	AudioServer.add_bus_effect(bus, compressor)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -3.0
	limiter.release = 0.05
	AudioServer.add_bus_effect(bus, limiter)


func begin_impact(secondary: bool = false) -> void:
	if _batch_depth == 0:
		_pending_cue.clear()
		_batch_secondary = secondary
	_batch_depth += 1


func end_impact() -> void:
	if _batch_depth == 0:
		return
	_batch_depth -= 1
	if _batch_depth > 0 or _pending_cue.is_empty():
		return
	var cue := _pending_cue
	_pending_cue = {}
	cue.secondary = _batch_secondary
	_emit_cue(cue)


func _submit_cue(cue: Dictionary) -> void:
	if _batch_depth == 0:
		_emit_cue(cue)
		return
	# One complete impact has one audible result, even if its fracture work
	# spans more than the time-based gate. Discovery > break > ore > stone.
	if not _pending_cue.is_empty():
		_coalesced_count += 1
	if _pending_cue.is_empty() or int(cue.rank) > int(_pending_cue.rank):
		_pending_cue = cue


func _emit_cue(cue: Dictionary) -> void:
	var now := _now_msec()
	var discovery: bool = cue.kind == "discovery"
	var secondary: bool = bool(cue.get("secondary", false)) and not discovery
	if discovery:
		var special: bool = cue.get("special", false)
		# A rarer find may replace a common cue; duplicate finds never restart
		# the same flourish several times during a single fracture cascade.
		if now - _last_discovery_msec < 140 and not (special and not _last_discovery_special):
			_coalesced_count += 1
			return
		_last_discovery_msec = now
		_last_discovery_special = special
		_soften_contacts(-24.0)
	elif secondary:
		if now - _last_secondary_msec < SECONDARY_INTERVAL_MSEC or now - _last_contact_msec < 55 or now - _last_discovery_msec < 90:
			_coalesced_count += 1
			return
		_last_secondary_msec = now
	elif now - _last_contact_msec < DIRECT_INTERVAL_MSEC:
		_coalesced_count += 1
		return
	else:
		_last_contact_msec = now
		_soften_contacts(-20.0)
	_last_kind = cue.kind
	_play(cue.stream, float(cue.volume) + (SECONDARY_GAIN_DB if secondary else 0.0), cue.pitch, discovery, secondary)


func _now_msec() -> int:
	return Time.get_ticks_msec()


func _soften_contacts(level: float) -> void:
	for i in CONTACT_VOICES + 1:
		var player := _players[i]
		if not player.playing or player.volume_db <= level:
			continue
		if _volume_tweens[i] != null and _volume_tweens[i].is_valid():
			_volume_tweens[i].kill()
		_volume_tweens[i] = create_tween()
		_volume_tweens[i].tween_property(player, "volume_db", level, 0.025)


func set_tool(id: String) -> void:
	if id == tool_id or not ToolBank.BANKS.has(id):
		return
	tool_id = id
	var bank: Dictionary = ToolBank.BANKS[id]
	_hits.assign(bank.hits)
	_breaks.assign([bank["break"]])
	_ore_hits.assign(bank.ores)
	_swings.assign([bank.swing])
	_hit_index = -1
	_ore_hit_index = -1
	_last_contact_msec = -1000


func play_hit(strength: float = 1.0, layer: int = 0, secondary: bool = false) -> void:
	if _hits.is_empty():
		return
	if _hit_index < 0:
		_hit_index = _random.randi_range(0, _hits.size() - 1)
	else:
		_hit_index = (_hit_index + _random.randi_range(1, maxi(_hits.size() - 1, 1))) % _hits.size()
	var weight := clampf(strength, 0.35, 2.0)
	var pitch := _random.randf_range(0.97, 1.035) + float(clampi(layer, 0, 5)) * 0.008
	_submit_cue({"kind": "hit", "rank": 10, "stream": _hits[_hit_index], "volume": -8.5 + linear_to_db(weight) * 0.55, "pitch": pitch, "secondary": secondary})


func play_break(layer: int = 0, secondary: bool = false) -> void:
	if _breaks.is_empty():
		return
	var pitch := _random.randf_range(0.96, 1.015) + float(clampi(layer, 0, 5)) * 0.006
	_submit_cue({"kind": "break", "rank": 30, "stream": _breaks[0], "volume": -9.0, "pitch": pitch, "secondary": secondary})


func play_reveal() -> void:
	if _reveal != null:
		_submit_cue({"kind": "discovery", "rank": 101, "stream": _reveal, "volume": -7.0, "pitch": 0.98, "special": true})


func play_discovery(special: bool, variant: int = 0) -> void:
	if special:
		play_reveal()
	elif _discovery != null:
		_submit_cue({"kind": "discovery", "rank": 100, "stream": _discovery, "volume": -9.0, "pitch": 1.0 + float(clampi(variant, 0, 4)) * 0.018, "special": false})


func play_resonance(tier: int, damage_ratio: float, secondary: bool = false) -> void:
	# One clean, authored ore strike; all synthesis happened offline.
	if _ore_hits.is_empty():
		return
	if _ore_hit_index < 0:
		_ore_hit_index = _random.randi_range(0, _ore_hits.size() - 1)
	else:
		_ore_hit_index = (_ore_hit_index + _random.randi_range(1, maxi(_ore_hits.size() - 1, 1))) % _ore_hits.size()
	var volume := -10.0 + clampf(damage_ratio, 0.0, 1.0) * 2.0
	var pitch := _random.randf_range(0.985, 1.015) * pow(2.0, float(clampi(tier, 0, 6)) * 0.6 / 12.0)
	_submit_cue({"kind": "ore", "rank": 20, "stream": _ore_hits[_ore_hit_index], "volume": volume, "pitch": pitch, "secondary": secondary})


func play_external_contact(stream: AudioStreamWAV, volume: float, pitch: float, broken: bool, secondary: bool = false) -> void:
	_submit_cue({"kind": "break" if broken else "hit", "rank": 30 if broken else 10, "stream": stream, "volume": volume, "pitch": pitch, "secondary": secondary})


func play_swing() -> void:
	if _swings.is_empty():
		return
	var now := _now_msec()
	if now - _last_swing_msec < 70:
		return
	_last_swing_msec = now
	_swing_index = (_swing_index + 1) % _swings.size()
	_play(_swings[_swing_index], -14.0, _random.randf_range(0.93, 1.07), false, false, true)


func play_respawn() -> void:
	if _respawn != null:
		_play(_respawn, -14.0, 1.0, false, false, true)


func _play(stream: AudioStreamWAV, volume: float, pitch: float, priority: bool = false, secondary: bool = false, utility: bool = false) -> void:
	if _players.is_empty():
		return
	# Three direct contacts, one quiet reaction, two motion cues and one
	# protected discovery. A cascade cannot occupy the entire retained pool.
	var voice := _players.size() - 1
	if not priority:
		var first := 4 if utility else 3 if secondary else 0
		var end := 6 if utility else 4 if secondary else CONTACT_VOICES
		voice = first
		for i in range(first, end):
			if not _players[i].playing:
				voice = i
				break
			if _started[i] < _started[voice]:
				voice = i
	var player := _players[voice]
	if _volume_tweens[voice] != null and _volume_tweens[voice].is_valid():
		_volume_tweens[voice].kill()
	player.stop()
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	_started[voice] = _now_msec()
	player.play()
	_played_count += 1


func _synthesize(kind: String, duration: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var low_noise := 0.0
	var mid_noise := 0.0
	var last_noise := 0.0
	# Keep the original noise phase for the unchanged synthesized sounds after
	# removing the former stone bank's randomized setup.
	for i in range(15):
		rng.randf()
	for frame in range(frames):
		var t := float(frame) / float(SAMPLE_RATE)
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.065)
		mid_noise = lerpf(mid_noise, noise, 0.36)
		var high_noise := noise - last_noise
		last_noise = noise
		var sample := 0.0
		match kind:
			"swing":
				var progress := t / duration
				var envelope := pow(sin(PI * progress), 2.2)
				sample = (mid_noise * 0.72 + high_noise * 0.035) * envelope
				sample += sin(TWO_PI * (210.0 * t + 900.0 * t * t)) * 0.05 * envelope
			"respawn":
				var progress := t / duration
				var envelope := pow(sin(PI * progress), 2.0)
				sample = low_noise * envelope * 0.68
				sample += sin(TWO_PI * (58.0 * t + 29.0 * t * t)) * envelope * 0.19
				sample += mid_noise * envelope * 0.08
		# A smooth limiter and short tail fade remove clicks and preserve headroom.
		sample = tanh(sample * 1.25) * 0.86
		sample *= minf((duration - t) / 0.018, 1.0)
		bytes.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
