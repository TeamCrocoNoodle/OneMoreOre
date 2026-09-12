extends SceneTree
## Inspect actual cached PCM and fixed playback voices, independently of synth.

const RewardAudio = preload("res://scripts/reward_audio.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_usec()
	var audio := RewardAudio.new()
	root.add_child(audio)
	var build_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var original_builds: int = RewardAudio._bank_build_count
	_check(audio._players.size() == 8 and audio.get_child_count() == 8 and not audio.is_processing(), "Eight fixed voices need no per-frame script loop")
	_check(audio._streams.keys().size() == 12, "Settlement and five auction cues have cached PCM")
	var total_bytes := 0
	var streams := 0
	for kind: String in RewardAudio.CUE_KINDS:
		var bank: Array = audio._streams[kind]
		var expected_count := 6 if kind in ["pickup", "row", "countdown", "auction_bid"] else (3 if kind in ["tick", "confirm"] else 1)
		_check(bank.size() == expected_count, kind + ": expected bounded variation bank")
		for variant in bank.size():
			var stream: AudioStreamWAV = bank[variant]
			var pcm := stream.data
			var frames := pcm.size() / 2
			_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 24000 and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s/%d: stable mono 24 kHz PCM16 one-shot" % [kind, variant])
			_check(frames > 0 and pcm.size() % 2 == 0 and absf(stream.get_length() - float(RewardAudio.CUE_DURATIONS[kind])) < 1.0 / 24000.0, "%s/%d: measured PCM length matches the intended short duration" % [kind, variant])
			var peak := 0
			var energy := 0.0
			var mean := 0.0
			for i in frames:
				var value := pcm.decode_s16(i * 2)
				peak = maxi(peak, absi(value))
				var sample := float(value) / 32767.0
				energy += sample * sample
				mean += sample
			var rms := sqrt(energy / float(frames))
			_check(peak > 1000 and peak <= 22938 and is_finite(rms) and rms > 0.008 and rms < 0.4, "%s/%d: audible finite PCM retains at least 3 dB sample headroom and never clips" % [kind, variant])
			_check(pcm.decode_s16(0) == 0 and pcm.decode_s16(pcm.size() - 2) == 0 and absf(mean / float(frames)) < 0.008, "%s/%d: zero endpoints and negligible DC avoid clicks" % [kind, variant])
			streams += 1
			total_bytes += pcm.size()
		if bank.size() > 1:
			_check(bank[0].data != bank[bank.size() - 1].data, kind + ": variations have distinct real sample data")
	var another := RewardAudio.new()
	root.add_child(another)
	var shared := true
	for kind: String in RewardAudio.CUE_KINDS:
		for i in audio._streams[kind].size():
			shared = shared and audio._streams[kind][i] == another._streams[kind][i]
	_check(shared and RewardAudio._bank_build_count == original_builds, "A second instance reuses every stream without resynthesis")
	_check(audio._players[0] != another._players[0], "Sharing immutable audio does not share playback state")
	audio.play_cue("total")
	audio.play_cue("timeout")
	var total_started: int = audio._started_usec[6]
	var timeout_started: int = audio._started_usec[7]
	var total_stream: AudioStream = audio._players[6].stream
	var timeout_stream: AudioStream = audio._players[7].stream
	_check(total_stream == audio._streams.total[0] and timeout_stream == audio._streams.timeout[0] and audio._players[6].playing and audio._players[7].playing, "Total and timeout can overlap on their separate reserved voices")
	for i in 80:
		var kind: String = ["pickup", "row", "tick", "countdown", "confirm"][i % 5]
		audio._last_play_usec.erase(kind)
		audio.play_cue(kind, i % 6)
		_check(audio._last_voice < 6, "Ordinary cue %d uses only the bounded normal pool" % i)
	_check(audio.get_child_count() == 8 and audio._players.size() == 8, "A burst of repeated cues never creates more voice nodes")
	_check(audio._players[6].stream == total_stream and audio._players[7].stream == timeout_stream and audio._started_usec[6] == total_started and audio._started_usec[7] == timeout_started, "Rapid ticks and pickups never restart or steal either reserved ending")
	var before: int = audio._played_count
	audio.play_cue("total")
	audio.play_cue("timeout")
	_check(audio._played_count == before, "Duplicate ending signals do not restart their flourish")
	audio.stop_all()
	var stopped := true
	for player in audio._players:
		stopped = stopped and not player.playing
	_check(stopped, "Reset stops all normal and reserved voices immediately")
	before = audio._played_count
	audio.play_cue("tick")
	for i in 100:
		audio.play_cue("tick")
	_check(audio._played_count == before + 1, "Repeated count events are rate limited instead of producing an ear-spam burst")
	# Rate caps use real monotonic time. The first headless frame can contain
	# the whole bank-build delta, so a SceneTree timer alone is not this oracle.
	while Time.get_ticks_usec() - int(audio._last_play_usec.tick) < 45000:
		await process_frame
	audio.play_cue("tick")
	_check(audio._played_count == before + 2, "The rate limit permits a later distinct tick")
	audio.stop_all()
	audio.play_cue("countdown", -10)
	_check(audio._players[audio._last_voice].stream == audio._streams.countdown[0], "Countdown urgency clamps to the quiet earliest tick")
	audio._last_play_usec.erase("countdown")
	audio.play_cue("countdown", 99)
	_check(audio._players[audio._last_voice].stream == audio._streams.countdown[5] and is_equal_approx(audio._players[audio._last_voice].volume_db, -20.4), "The last countdown tick is brighter with only a discreet level increase")
	before = audio._played_count
	audio.play_cue("unrecognized")
	_check(audio._played_count == before and RewardAudio._bank_build_count == original_builds, "Unknown cues are harmless and all playback avoids synthesis")
	audio.stop_all()
	audio.play_cue("total")
	audio.play_cue("auction_jackpot")
	_check(audio._last_voice == 6 and audio._players[6].stream == audio._streams.auction_jackpot[0], "A skipped auction reveal can replace the earlier settlement flourish on its reserved voice")
	var auction_started: int = audio._started_usec[6]
	for i in 20:
		audio._last_play_usec.erase("auction_bid")
		audio.play_cue("auction_bid", i % 6)
	_check(audio._started_usec[6] == auction_started and audio._players[6].stream == audio._streams.auction_jackpot[0], "Auction bid ticks cannot steal the result flourish")
	var peak_sum: float = 6.0 * 0.70 * db_to_linear(-17.0) + 0.70 * db_to_linear(-13.5) + 0.70 * db_to_linear(-17.0)
	_check(peak_sum < 0.9, "Even aligned maximum voice peaks retain mix headroom")
	if "--export-demo" in OS.get_cmdline_user_args():
		_export_demo(audio._streams)
	var voice_ref: WeakRef = weakref(audio._players[6])
	audio.stop_all()
	another.stop_all()
	for owner in [audio, another]:
		for player in owner._players:
			player.stream = null
	audio.queue_free()
	another.queue_free()
	await process_frame
	await process_frame
	_check(voice_ref.get_ref() == null, "Deleting the reward module frees its reserved voices")
	print("REWARD_AUDIO_BANK streams=%d bytes=%d first_build_ms=%.3f" % [streams, total_bytes, build_ms])
	print("REWARD_AUDIO_VALIDATION checks=%d failures=%d" % [checks, failures])
	RewardAudio._shared_bank.clear()
	# Let the mixer consume queued playback releases before a very fast
	# headless process exits; this is not part of the production cue path.
	var release_deadline := Time.get_ticks_usec() + 25000
	while Time.get_ticks_usec() < release_deadline:
		await process_frame
	quit(0 if failures == 0 else 1)


func _export_demo(bank: Dictionary) -> void:
	var pcm := PackedByteArray()
	var silence := PackedByteArray()
	silence.resize(24000 * 2 / 4)
	silence.fill(0)
	var sequence: Array = [["pickup", 0], ["pickup", 5], ["row", 1], ["tick", 0], ["total", 0], ["timeout", 0], ["countdown", 0], ["countdown", 5], ["confirm", 0], ["auction_open", 0], ["auction_bid", 0], ["auction_bid", 3], ["auction_bid", 5], ["auction_loss", 0], ["auction_win", 0], ["auction_jackpot", 0]]
	for entry: Array in sequence:
		var stream: AudioStreamWAV = bank[entry[0]][entry[1]]
		var gain := db_to_linear(float(RewardAudio.CUE_VOLUME_DB[entry[0]]) + (float(entry[1]) * 0.32 if entry[0] == "countdown" else 0.0))
		var data := stream.data
		for frame in data.size() / 2:
			data.encode_s16(frame * 2, roundi(float(data.decode_s16(frame * 2)) * gain))
		pcm.append_array(data)
		pcm.append_array(silence)
	var demo := AudioStreamWAV.new()
	demo.format = AudioStreamWAV.FORMAT_16_BITS
	demo.mix_rate = 24000
	demo.stereo = false
	demo.data = pcm
	var status := demo.save_to_wav("res://artifacts/reward_audio_demo.wav")
	_check(status == OK, "Representative cue sequence exports as a standalone WAV at its actual playback levels")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("REWARD_AUDIO_FAILED: " + message)
