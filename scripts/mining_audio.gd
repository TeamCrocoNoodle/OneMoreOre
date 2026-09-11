extends Node
## Small, entirely procedural sound bank. Add as a child before playing sounds.
## All samples are generated once; impact playback performs no synthesis.

const SAMPLE_RATE := 24000
const PLAYER_COUNT := 14
const TWO_PI := TAU
const REVEAL_STEPS: Array[float] = [0.0, 4.0, 7.0, 12.0, 16.0]

var _hits: Array[AudioStreamWAV] = []
var _breaks: Array[AudioStreamWAV] = []
var _swings: Array[AudioStreamWAV] = []
var _reveal: AudioStreamWAV
var _discovery: AudioStreamWAV
var _respawn: AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _started: Array[int] = []
var _random := RandomNumberGenerator.new()
var _hit_index := 0
var _break_index := 0
var _swing_index := 0
var _last_swing_msec := -1000
var _last_break_msec := -1000


func _ready() -> void:
	_random.randomize()
	for i in range(5):
		_hits.append(_synthesize("hit", 0.24, 701 + i * 31))
	for i in range(4):
		_breaks.append(_synthesize("break", 0.53, 1907 + i * 47))
	for i in range(3):
		_swings.append(_synthesize("swing", 0.115, 3803 + i * 71))
	_reveal = _synthesize("reveal", 1.55, 5107)
	_discovery = _synthesize("reveal", 0.62, 8107)
	_respawn = _synthesize("respawn", 0.56, 7307)
	for i in range(PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "MiningVoice%d" % i
		player.bus = &"Master"
		add_child(player)
		_players.append(player)
		_started.append(0)


func play_hit(strength: float = 1.0, layer: int = 0) -> void:
	if _hits.is_empty():
		return
	_hit_index = (_hit_index + 1 + _random.randi_range(0, 2)) % _hits.size()
	var weight := clampf(strength, 0.35, 2.0)
	var pitch := _random.randf_range(0.94, 1.065) + minf(float(layer), 5.0) * 0.045
	_play(_hits[_hit_index], -8.5 + linear_to_db(weight) * 0.55, pitch)


func play_break(layer: int = 0) -> void:
	if _breaks.is_empty():
		return
	# One heavy fracture per short cluster keeps area hits from becoming a roar.
	var now := Time.get_ticks_msec()
	if now - _last_break_msec < 42:
		return
	_last_break_msec = now
	_break_index = (_break_index + 1 + _random.randi_range(0, 1)) % _breaks.size()
	var pitch := _random.randf_range(0.94, 1.05) + minf(float(layer), 5.0) * 0.055
	_play(_breaks[_break_index], -9.0, pitch)


func play_reveal() -> void:
	if _reveal != null:
		_play(_reveal, -7.0, 1.0, true)


func play_discovery(special: bool, variant: int = 0) -> void:
	if special:
		play_reveal()
	elif _discovery != null:
		_play(_discovery, -10.0, 1.0 + float(variant % 5) * 0.07)


func play_resonance(tier: int, damage_ratio: float) -> void:
	if _discovery != null:
		_play(_discovery, -19.0 + clampf(damage_ratio, 0.0, 1.0) * 4.0, pow(2.0, float(clampi(tier, 0, 5)) * 2.0 / 12.0))


func play_swing() -> void:
	if _swings.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_swing_msec < 70:
		return
	_last_swing_msec = now
	_swing_index = (_swing_index + 1) % _swings.size()
	_play(_swings[_swing_index], -14.0, _random.randf_range(0.93, 1.07))


func play_respawn() -> void:
	if _respawn != null:
		_play(_respawn, -14.0, 1.0)


func _play(stream: AudioStreamWAV, volume: float, pitch: float, priority: bool = false) -> void:
	if _players.is_empty():
		return
	# Reserve the last voice for gem reveals, so repeated mining cannot cut it off.
	var voice := _players.size() - 1
	if not priority:
		voice = 0
		for i in range(_players.size() - 1):
			if not _players[i].playing:
				voice = i
				break
			if _started[i] < _started[voice]:
				voice = i
	var player := _players[voice]
	player.stop()
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	_started[voice] = Time.get_ticks_msec()
	player.play()


func _synthesize(kind: String, duration: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var low_noise := 0.0
	var mid_noise := 0.0
	var last_noise := 0.0
	var variation := rng.randf_range(0.93, 1.07)
	var tick_times: Array[float] = [0.008, 0.043, 0.083, 0.132, 0.198, 0.271, 0.346]
	var tick_pitches: Array[float] = []
	for i in range(tick_times.size()):
		tick_times[i] += rng.randf_range(-0.005, 0.006)
		tick_pitches.append(rng.randf_range(800.0, 2600.0))
	for frame in range(frames):
		var t := float(frame) / float(SAMPLE_RATE)
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.065)
		mid_noise = lerpf(mid_noise, noise, 0.36)
		var high_noise := noise - last_noise
		last_noise = noise
		var sample := 0.0
		match kind:
			"hit":
				# A tight contact tick, woody stone body, and a very short iron ring.
				var attack := minf(t / 0.0008, 1.0)
				sample += high_noise * 0.33 * exp(-t * 260.0)
				sample += mid_noise * 0.33 * exp(-t * 63.0)
				sample += sin(TWO_PI * (145.0 * t + 14.0 * (1.0 - exp(-t * 36.0)))) * 0.36 * exp(-t * 44.0)
				sample += sin(TWO_PI * 1080.0 * variation * t) * 0.19 * exp(-t * 43.0)
				sample += sin(TWO_PI * 1791.0 * variation * t) * 0.105 * exp(-t * 56.0)
				sample += sin(TWO_PI * 2987.0 * variation * t) * 0.065 * exp(-t * 82.0)
				sample += low_noise * 0.25 * exp(-t * 25.0)
				sample *= attack
			"break":
				# Deep initial fracture followed by separate pebble/chip contacts.
				var attack := minf(t / 0.001, 1.0)
				sample += sin(TWO_PI * (75.0 * t + 2.1 * (1.0 - exp(-t * 29.0)))) * 0.55 * exp(-t * 22.0)
				sample += mid_noise * 0.48 * exp(-t * 23.0)
				sample += high_noise * 0.21 * exp(-t * 108.0)
				sample += low_noise * 0.5 * exp(-t * 9.5)
				for i in range(tick_times.size()):
					var local_t := t - tick_times[i]
					if local_t >= 0.0 and local_t < 0.07:
						var tick_env := exp(-local_t * 130.0) * (1.0 - float(i) * 0.1)
						sample += (mid_noise * 0.26 + sin(TWO_PI * tick_pitches[i] * local_t) * 0.14) * tick_env
				# Brief upward sparkle: enough reward without sounding like a melody.
				for i in range(3):
					var local_t := t - 0.065 - float(i) * 0.034
					if local_t >= 0.0:
						var frequency := 1318.51 * pow(1.259921, float(i)) * variation
						var bell_env := minf(local_t / 0.003, 1.0) * exp(-local_t * 15.0)
						sample += (sin(TWO_PI * frequency * local_t) + 0.17 * sin(TWO_PI * frequency * 2.76 * local_t)) * 0.075 * bell_env
				sample *= attack
			"swing":
				var progress := t / duration
				var envelope := pow(sin(PI * progress), 2.2)
				sample = (mid_noise * 0.72 + high_noise * 0.035) * envelope
				sample += sin(TWO_PI * (210.0 * t + 900.0 * t * t)) * 0.05 * envelope
			"reveal":
				# A major pentatonic glint blooms into a gentle, glassy chord.
				for i in range(REVEAL_STEPS.size()):
					var local_t := t - float(i) * 0.06
					if local_t >= 0.0:
						var frequency := 659.255 * pow(2.0, REVEAL_STEPS[i] / 12.0)
						var envelope := minf(local_t / 0.003, 1.0) * exp(-local_t * 3.8)
						var bell := sin(TWO_PI * frequency * local_t)
						bell += sin(TWO_PI * frequency * 2.002 * local_t) * 0.24 * exp(-local_t * 5.0)
						bell += sin(TWO_PI * frequency * 3.97 * local_t) * 0.075 * exp(-local_t * 13.0)
						sample += bell * envelope * 0.23
				sample += sin(TWO_PI * 164.814 * t) * 0.2 * minf(t / 0.009, 1.0) * exp(-t * 7.0)
				sample += mid_noise * 0.055 * exp(-t * 5.5) * minf(t / 0.015, 1.0)
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
