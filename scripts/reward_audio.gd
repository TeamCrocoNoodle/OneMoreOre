extends Node
## Original short reward/round cues. All PCM is synthesized once and shared;
## playing a cue only selects a cached stream and an existing fixed voice.

const SAMPLE_RATE := 24000
const VOICE_COUNT := 8
const NORMAL_VOICES := 6
const TOTAL_VOICE := 6
const TIMEOUT_VOICE := 7
const CUE_KINDS := ["pickup", "row", "tick", "total", "timeout", "countdown", "confirm", "auction_open", "auction_bid", "auction_loss", "auction_win", "auction_jackpot"]
const CUE_DURATIONS := {"pickup": 0.21, "row": 0.28, "tick": 0.046, "total": 0.70, "timeout": 0.42, "countdown": 0.075, "confirm": 0.085, "auction_open": 0.28, "auction_bid": 0.070, "auction_loss": 0.35, "auction_win": 0.68, "auction_jackpot": 1.1}
const CUE_VOLUME_DB := {"pickup": -17.0, "row": -20.0, "tick": -25.0, "total": -13.5, "timeout": -17.0, "countdown": -22.0, "confirm": -20.0, "auction_open": -19.0, "auction_bid": -25.0, "auction_loss": -18.0, "auction_win": -14.5, "auction_jackpot": -13.5}
const MIN_INTERVAL_USEC := {"pickup": 28000, "row": 65000, "tick": 35000, "total": 350000, "timeout": 350000, "countdown": 150000, "confirm": 70000, "auction_open": 150000, "auction_bid": 30000, "auction_loss": 350000, "auction_win": 350000, "auction_jackpot": 350000}
const AUCTION_ENDINGS := ["auction_loss", "auction_win", "auction_jackpot"]

static var _shared_bank: Dictionary = {}
static var _bank_build_count := 0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _started_usec: Array[int] = []
var _last_play_usec: Dictionary = {}
var _variation_cursor: Dictionary = {}
var _played_count := 0
var _dropped_count := 0
var _last_voice := -1
var _last_kind := ""


func _ready() -> void:
	_prepare_bank()
	_streams = _shared_bank
	for i in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "RewardVoice%d" % i
		player.bus = &"Master"
		player.max_polyphony = 1
		add_child(player)
		_players.append(player)
		_started_usec.append(0)
	set_process(false)


func play_cue(kind: String, tier: int = 0) -> void:
	if not _streams.has(kind) or _players.size() != VOICE_COUNT:
		return
	var now := Time.get_ticks_usec()
	if now - int(_last_play_usec.get(kind, -10000000)) < int(MIN_INTERVAL_USEC[kind]):
		_dropped_count += 1
		return
	var voice := TOTAL_VOICE if kind == "total" or kind in AUCTION_ENDINGS else (TIMEOUT_VOICE if kind == "timeout" else -1)
	if voice >= 0:
		# Each ending owns a separate voice. Neither counting ticks nor the
		# other ending can steal it, and duplicate UI signals do not restart it.
		if _players[voice].playing and not (kind in AUCTION_ENDINGS and _players[voice].stream == _streams.total[0]):
			_dropped_count += 1
			return
	else:
		voice = 0
		for i in NORMAL_VOICES:
			if not _players[i].playing:
				voice = i
				break
			if _started_usec[i] < _started_usec[voice]:
				voice = i
	var variants: Array = _streams[kind]
	var index := clampi(tier, 0, 5) if kind in ["pickup", "row", "countdown", "auction_bid"] else int(_variation_cursor.get(kind, 0)) % variants.size()
	_variation_cursor[kind] = int(_variation_cursor.get(kind, 0)) + 1
	var player := _players[voice]
	player.stop()
	player.stream = variants[index]
	player.volume_db = float(CUE_VOLUME_DB[kind])
	if kind == "countdown":
		# Tier is urgency here: 0 at five seconds, rising to 4/5 at the last.
		player.volume_db += float(clampi(tier, 0, 5)) * 0.32
	player.pitch_scale = 1.0
	player.play()
	_started_usec[voice] = now
	_last_play_usec[kind] = now
	_played_count += 1
	_last_voice = voice
	_last_kind = kind


func stop_all() -> void:
	for player in _players:
		player.stop()
	_last_play_usec.clear()
	_last_voice = -1
	_last_kind = ""


static func _prepare_bank() -> void:
	if not _shared_bank.is_empty():
		return
	for kind: String in CUE_KINDS:
		var variants: Array[AudioStreamWAV] = []
		var count := 6 if kind in ["pickup", "row", "countdown", "auction_bid"] else (3 if kind in ["tick", "confirm"] else 1)
		for variant in count:
			variants.append(_synthesize(kind, variant))
		_shared_bank[kind] = variants
	_bank_build_count += 1


static func _strike(at: float, frequency: float, decay: float, amplitude: float, metal: float = 0.45, texture: float = 0.04, bend: float = 0.0) -> Dictionary:
	return {"at": at, "frequency": frequency, "decay": decay, "amplitude": amplitude, "metal": metal, "texture": texture, "bend": bend}


static func _synthesize(kind: String, variant: int) -> AudioStreamWAV:
	var events: Array[Dictionary] = []
	var brightness := 1.0 + float(variant) * 0.045
	match kind:
		"pickup":
			# A close glass chip with an airy second glint, not a sustained note.
			events.append(_strike(0.0, 1420.0 * brightness, 0.037, 0.62, 0.60, 0.085, -650.0))
			events.append(_strike(0.016, 2980.0 * brightness, 0.026, 0.19, 0.28, 0.025, -1100.0))
		"row":
			# Uneven, inharmonic coin contacts make a little cascade rather than
			# an arpeggio. The row arrives as one short sound, not many voices.
			for i in 4:
				var frequencies := [1740.0, 2380.0, 1960.0, 2830.0]
				events.append(_strike([0.0, 0.041, 0.094, 0.151][i], frequencies[i] * brightness, 0.026 + float(i) * 0.003, 0.31 - float(i) * 0.025, 0.67, 0.095, -420.0))
		"tick":
			events.append(_strike(0.0, 790.0 + float(variant) * 47.0, 0.0055, 0.52, 0.12, 0.48))
			events.append(_strike(0.012, 1080.0 + float(variant) * 31.0, 0.0042, 0.20, 0.10, 0.35))
		"total":
			# A soft wooden landing followed by an irregular shower of bright
			# metallic contacts and one bent, rounded final shimmer.
			events.append(_strike(0.0, 185.0, 0.036, 0.28, 0.16, 0.12, -330.0))
			for i in 5:
				var frequencies := [1530.0, 2070.0, 1790.0, 2710.0, 2280.0]
				events.append(_strike([0.008, 0.054, 0.116, 0.184, 0.260][i], frequencies[i], 0.044, 0.31 - float(i) * 0.025, 0.65, 0.055, 550.0))
			events.append(_strike(0.242, 910.0, 0.120, 0.38, 0.52, 0.018, 530.0))
			events.append(_strike(0.313, 3210.0, 0.082, 0.15, 0.22, 0.02, -1800.0))
		"timeout":
			# A calm closure: no buzzer, alarm or negative descending sting.
			events.append(_strike(0.0, 820.0, 0.084, 0.50, 0.27, 0.02, 80.0))
			events.append(_strike(0.062, 1730.0, 0.058, 0.22, 0.24, 0.015, -100.0))
		"countdown":
			events.append(_strike(0.0, 560.0 + float(variant) * 55.0, 0.012, 0.62, 0.12, 0.30, -900.0))
			events.append(_strike(0.004, 1280.0 + float(variant) * 95.0, 0.007, 0.17, 0.10, 0.12))
		"confirm":
			events.append(_strike(0.0, 1040.0 + float(variant) * 43.0, 0.010, 0.42, 0.14, 0.25, 900.0))
			events.append(_strike(0.011, 680.0 + float(variant) * 23.0, 0.013, 0.19, 0.15, 0.08))
		"auction_open":
			# A small wooden auction hammer; no backing music or sustained bed.
			events.append(_strike(0.0, 164, 0.026, 0.58, 0.12, 0.24, -180))
			events.append(_strike(0.060, 213, 0.020, 0.33, 0.10, 0.18, -300))
			events.append(_strike(0.116, 1170, 0.024, 0.15, 0.55, 0.06, 1100))
		"auction_bid":
			events.append(_strike(0.0, 610 + variant * 71, 0.007, 0.55, 0.20, 0.35, -1100))
			events.append(_strike(0.009, 1720 + variant * 59, 0.010, 0.17, 0.52, 0.04, 520))
		"auction_loss":
			events.append(_strike(0.0, 158, 0.041, 0.59, 0.13, 0.14, -190))
			events.append(_strike(0.075, 310, 0.032, 0.25, 0.28, 0.04, -470))
		"auction_win", "auction_jackpot":
			events.append(_strike(0.0, 194, 0.030, 0.46, 0.15, 0.16, -210))
			var contacts := 9 if kind == "auction_jackpot" else 5
			var frequencies := [1730, 2490, 1910, 3170, 2240, 2830, 3510, 2370, 3030]
			for i in contacts:
				events.append(_strike(0.020 + i * 0.047 + (i % 3) * 0.013, frequencies[i], 0.038 + i * 0.003, 0.32 - i * 0.014, 0.72, 0.065, 290))
			if kind == "auction_jackpot":
				events.append(_strike(0.35, 1280, 0.115, 0.34, 0.62, 0.022, 790))
	var duration := float(CUE_DURATIONS[kind])
	var frame_count := roundi(duration * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 658127 + CUE_KINDS.find(kind) * 3701 + variant * 113
	var low_noise := 0.0
	var peak := 0.0
	for frame in frame_count:
		var time := float(frame) / float(SAMPLE_RATE)
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.32)
		var texture := noise - low_noise
		var sample := 0.0
		for event in events:
			var age := time - float(event["at"])
			var decay := float(event["decay"])
			if age < 0.0 or age > decay * 9.0:
				continue
			var phase := TAU * (float(event["frequency"]) * age + float(event["bend"]) * age * age * 0.5)
			var envelope := minf(age / 0.0012, 1.0) * exp(-age / decay)
			var metallic := float(event["metal"])
			var frequency := absf(float(event["frequency"]) + float(event["bend"]) * age)
			# Roll off partials before Nyquist even for the brightest grade.
			var partial_2 := clampf((SAMPLE_RATE * 0.45 - frequency * 2.37) / 1800.0, 0.0, 1.0)
			var partial_3 := clampf((SAMPLE_RATE * 0.45 - frequency * 3.91) / 1800.0, 0.0, 1.0)
			var resonator := sin(phase) + metallic * 0.46 * partial_2 * sin(phase * 2.37 + age * 29.0) + metallic * 0.22 * partial_3 * sin(phase * 3.91 - age * 43.0)
			var attack_noise := texture * float(event["texture"]) * exp(-age / 0.0055)
			sample += float(event["amplitude"]) * (resonator * envelope + attack_noise * minf(age / 0.0007, 1.0))
		# Endpoint-zero fade prevents clicks. A soft limiter shapes transients;
		# a peak ceiling leaves room for every pool voice and existing mining.
		sample = tanh(sample * 1.10) * minf(float(frame_count - 1 - frame) / (0.012 * SAMPLE_RATE), 1.0)
		samples[frame] = sample
		peak = maxf(peak, absf(sample))
	var gain := minf(0.70 / maxf(peak, 0.000001), 1.35)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	for frame in frame_count:
		pcm.encode_s16(frame * 2, roundi(samples[frame] * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream
