extends "res://tests/validate_tools.gd"
const MiningAudio = preload("res://scripts/mining_audio.gd")
const BossAudio = preload("res://scripts/boss_audio.gd")

class ClockAudio extends MiningAudio:
	var clock_msec := 10000
	func _now_msec() -> int:
		return clock_msec

class AudioGame extends TestGame:
	func _ready() -> void:
		audio.free()
		audio = ClockAudio.new()
		super._ready()

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	await _voice_rules()
	await _real_area_and_resonance()
	ended = true
	print("MINING_AUDIO_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _voice_rules() -> void:
	var audio := ClockAudio.new()
	root.add_child(audio)
	audio.play_hit()
	_check(audio._played_count == 1 and audio._players[0].stream in audio._hits and is_equal_approx(audio._players[0].volume_db, -8.5), "A single direct strike keeps its authored PCM and original volume")
	audio.clock_msec += 100
	var before := audio._played_count
	audio.begin_impact()
	for contact in 20:
		audio.play_hit()
		audio.play_resonance(contact % 7, 0.5)
		# Simulate a slow fracture frame, beyond the old millisecond gates.
		audio.clock_msec += 25
		audio.play_break()
	_check(audio._played_count == before, "The group waits for its most meaningful result without playing one sound per expensive chunk")
	audio.end_impact()
	_check(audio._played_count == before + 1 and audio._last_kind == "break", "A mixed 60-cue area impact plays exactly one representative fracture")
	audio.clock_msec += 100
	before = audio._played_count
	audio.begin_impact()
	audio.play_break()
	audio.play_discovery(false)
	audio.play_discovery(true)
	audio.play_discovery(false)
	audio.end_impact()
	_check(audio._played_count == before + 1 and audio._last_kind == "discovery", "One multi-gem fracture favors one discovery over its stone sounds")
	var discovery_voice := audio._players.size() - 1
	var discovery_started := audio._started[discovery_voice]
	_check(is_equal_approx(audio._players[discovery_voice].volume_db, -7.0), "The rarer discovery wins even if common gems follow it")
	for duplicate in 15:
		audio.play_discovery(true)
	_check(audio._started[discovery_voice] == discovery_started and audio._played_count == before + 1, "Nearby discoveries cannot repeatedly restart the same flourish")
	audio.clock_msec += 200
	before = audio._played_count
	audio.begin_impact()
	audio.begin_impact()
	audio.play_hit()
	audio.end_impact()
	_check(audio._played_count == before, "Nested impact groups cannot flush early")
	audio.end_impact()
	audio.end_impact()
	_check(audio._played_count == before + 1 and audio._batch_depth == 0, "The outer group emits once and repeated end calls are harmless")
	audio.clock_msec += 200
	before = audio._played_count
	for frame in 100:
		audio.begin_impact(true)
		for piece in 3: audio.play_break(0, true)
		audio.end_impact()
		audio.clock_msec += 16
	var propagated := audio._played_count - before
	_check(propagated > 0 and propagated <= 14, "A 300-piece cascade has at most fourteen quiet cues over 1.6 seconds")
	_check(is_equal_approx(audio._players[3].volume_db, -17.0), "Propagation plays eight decibels below the direct fracture")
	before = audio._played_count
	for strike in 20:
		audio.clock_msec += 50
		audio.play_hit()
		audio.play_break(0, true)
	_check(audio._played_count == before + 20, "Twenty fast direct strikes keep every beat while immediate secondary duplicates are suppressed")
	_check(_active_in(audio, 0, 3) <= 3 and _active_in(audio, 3, 4) <= 1, "Direct contact tails and reaction tails have independent small voice limits")
	var newest := 0
	for i in 3:
		if audio._started[i] > audio._started[newest]: newest = i
	# The synthetic clock loop runs inside one engine frame. Let the real
	# scene process its newly scheduled tweens before measuring their result.
	var fade_deadline := Time.get_ticks_msec() + 80
	while Time.get_ticks_msec() < fade_deadline:
		await process_frame
	for i in 3:
		if i != newest and audio._players[i].playing:
			_check(audio._players[i].volume_db <= -19.9, "Older impact tails fade below the fresh direct strike")
	_check(is_equal_approx(audio._players[newest].volume_db, -8.5), "Tail ducking never lowers the newest direct hit")
	_check(audio._players[discovery_voice].stream == audio._discovery, "Mining cannot steal the protected discovery voice")
	var bus := AudioServer.get_bus_index(MiningAudio.MIX_BUS)
	var bus_count := AudioServer.bus_count
	MiningAudio._ensure_mix_bus()
	_check(AudioServer.bus_count == bus_count and AudioServer.get_bus_effect_count(bus) == 2, "Repeated setup reuses one mining bus and its two dynamics effects")
	_check(AudioServer.get_bus_effect(bus, 0) is AudioEffectCompressor and AudioServer.get_bus_effect(bus, 1) is AudioEffectHardLimiter, "Only the mining mix receives gentle compression and a peak ceiling")
	var boss_audio := BossAudio.new()
	boss_audio.impact_mixer = audio
	root.add_child(boss_audio)
	audio.clock_msec += 200
	before = audio._played_count
	audio.begin_impact()
	for i in 12:
		boss_audio.play(2, "hit")
		boss_audio.play(2, "break")
	audio.end_impact()
	_check(audio._played_count == before + 1 and audio._last_kind == "break", "A boss area strike shares the same coalescing and voice budget")
	var boss_contacts := 0
	for player in boss_audio.players:
		if player.playing: boss_contacts += 1
	_check(boss_contacts == 0, "Boss contact playback does not bypass the mining mix in another pool")
	_check(audio.get_child_count() == MiningAudio.PLAYER_COUNT, "Heavy bursts create no extra players or per-cue nodes")
	_stop_audio(audio)
	_stop_audio(boss_audio)
	audio.queue_free()
	boss_audio.queue_free()
	await process_frame
	await create_timer(0.1).timeout

func _real_area_and_resonance() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	game = AudioGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.rock_motion.scale = Vector3.ONE
	var stats: Dictionary = game.upgrade_stats.duplicate()
	stats.range_bonus = 2.0
	game.mining_skills.configure(stats)
	for chunk in game.chunks:
		chunk.health = 10000.0
		chunk.max_health = 10000.0
	await physics_frame
	var point := Vector2.ZERO
	for chunk in game.chunks:
		var candidate: Vector2 = game.camera.unproject_position(chunk.to_global(chunk.face_center))
		var hit: Dictionary = game.ray_at(candidate)
		if not game._aim_over_hud(candidate) and hit.get("collider") == chunk and game._area_targets(candidate, hit).size() >= 2:
			point = candidate
			break
	_check(point != Vector2.ZERO, "The integration fixture finds a real broad strike with multiple visible targets")
	if point != Vector2.ZERO:
		var sounds_before: int = game.audio._played_count
		var hits_before: int = game.hit_count
		game._mine_at(point)
		_check(game.hit_count >= hits_before + 3 and game.audio._played_count == sounds_before + 1, "A real wide strike still damages every target but emits just one contact cue")
		for chunk in game.chunks: chunk.set_meta("special_kind", "resonance")
		game.audio.clock_msec += 100
		game._mine_at(point)
		_check(not game._reactions.is_empty(), "A struck resonance stone still queues real neighboring damage")
		sounds_before = game.audio._played_count
		hits_before = game.hit_count
		var frames := 0
		while not game._reactions.is_empty() and frames < 100:
			game.audio.clock_msec += 20
			game._drain_reactions()
			frames += 1
		_check(game._reactions.is_empty() and game.hit_count > hits_before + 9, "Sound batching does not skip or delay the actual resonance damage chain")
		_check(game.audio._played_count - sounds_before <= ceili(float(frames) / 6.0), "Frame-spanning propagation respects the quieter six-frame audio interval")
		_check(game.audio._batch_depth == 0 and game.audio._pending_cue.is_empty(), "Real direct and reaction paths always close their audio group")
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout

func _active_in(audio: Node, first: int, end: int) -> int:
	var count := 0
	for i in range(first, end):
		if audio._players[i].playing: count += 1
	return count
