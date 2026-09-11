extends SceneTree
## Real-renderer benchmark. No image readback or file writes during sampling.
## --script res://tests/profile_mining.gd -- --tag=baseline

const SEED := 12873
const HIT_INTERVAL := 0.08
const EXPECTED_HITS := 96

class ProfileEffects:
	extends "res://scripts/mining_effects.gd"
	var timings: Dictionary = {}
	func _record(label: String, started: int) -> void:
		if not timings.has(label):
			timings[label] = []
		timings[label].append(float(Time.get_ticks_usec() - started) / 1000.0)
	func _process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._process(delta)
		_record("effects_process_ms", started)
	func impact(point: Vector3, normal: Vector3, broken: bool, stone_color: Color, gem_cover: bool = false) -> void:
		var started := Time.get_ticks_usec()
		super.impact(point, normal, broken, stone_color, gem_cover)
		_record("impact_ms", started)
	func _ring(point: Vector3, normal: Vector3, broken: bool) -> void:
		var started := Time.get_ticks_usec()
		super._ring(point, normal, broken)
		_record("ring_ms", started)
	func shed_fragments(fragments: Array[Dictionary], material: Material, placement: Transform3D, outward: Vector3, impact_point: Vector3) -> void:
		var started := Time.get_ticks_usec()
		super.shed_fragments(fragments, material, placement, outward, impact_point)
		_record("shed_fragments_ms", started)
	func gem_burst(point: Vector3, special: bool = true, tier: int = -1) -> void:
		var started := Time.get_ticks_usec()
		super.gem_burst(point, special, tier)
		_record("gem_burst_ms", started)

class ProfileAudio:
	extends "res://scripts/mining_audio.gd"
	var timings: Dictionary = {}
	func _record(label: String, started: int) -> void:
		if not timings.has(label):
			timings[label] = []
		timings[label].append(float(Time.get_ticks_usec() - started) / 1000.0)
	func _ready() -> void:
		var started := Time.get_ticks_usec()
		super._ready()
		_record("audio_ready_ms", started)
	func play_hit(strength: float = 1.0, layer: int = 0) -> void:
		var started := Time.get_ticks_usec()
		super.play_hit(strength, layer)
		_record("audio_hit_ms", started)
	func play_discovery(special: bool, variant: int = 0) -> void:
		var started := Time.get_ticks_usec()
		super.play_discovery(special, variant)
		_record("audio_discovery_ms", started)

class ProfileGame:
	extends "res://scripts/main.gd"
	var mine_samples: Array[Dictionary] = []
	func _ready() -> void:
		effects.free()
		effects = ProfileEffects.new()
		audio.free()
		audio = ProfileAudio.new()
		super._ready()
		rng.seed = 12873
		effects.rng.seed = 12873
		set_process_input(false)
	func _mine_at(screen_position: Vector2) -> bool:
		var before := broken_count
		var started := Time.get_ticks_usec()
		var accepted := super._mine_at(screen_position)
		mine_samples.append({"cpu_ms": float(Time.get_ticks_usec() - started) / 1000.0,
			"broken": broken_count > before, "accepted": accepted, "hit": hit_count,
			"frame": Engine.get_process_frames()})
		return accepted

var game: ProfileGame
var frames: Array[Dictionary] = []
var tag := "baseline"
var finished := false
var errors: Array[String] = []
var startup_ms := 0.0
var initial_rotation := Quaternion.IDENTITY
var covers: Array[StaticBody3D] = []
var break_frame := -100
var hit_frame := -100
var hit_index := 0
var renderer_name := ""
var prewarm_gem := false
var prewarm_gem_count := 0
var initial_gem_state: Array[Dictionary] = []
var warmup_validated := false
var warmup_render: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			tag = argument.trim_prefix("--tag=").validate_filename().substr(0, 48)
		elif argument == "--prewarm-gem":
			prewarm_gem = true
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func():
		if not finished:
			errors.append("30 second watchdog expired")
			_finish()
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	root.title = "OneMoreOre performance: " + tag
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	renderer_name = RenderingServer.get_current_rendering_method()
	var started := Time.get_ticks_usec()
	game = ProfileGame.new()
	game.showcase_on_start = true
	RenderingServer.frame_post_draw.connect(_observe_warmup_frame)
	root.add_child(game)
	startup_ms = float(Time.get_ticks_usec() - started) / 1000.0
	initial_rotation = game.shell.quaternion
	covers.assign(game.showcase_covers)
	for jewel in game.gems:
		initial_gem_state.append({"jewel": jewel, "parent": jewel.get_parent(),
			"transform": jewel.transform, "owner": jewel.host_chunk.get_ref(),
			"facets_parent": jewel.facets.get_parent(), "facets_transform": jewel.facets.transform})
	if covers.size() != 6:
		errors.append("Expected six showcase gem covers")
		_finish()
		return
	# Optional diagnostic renders the actual hidden gem meshes in this viewport.
	# Only mesh parenting changes temporarily; gem ownership/colliders stay sealed.
	if prewarm_gem:
		await _prewarm_gem_meshes()
	# Allow production startup warmup/cleanup to finish before timed sampling.
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	RenderingServer.frame_post_draw.disconnect(_observe_warmup_frame)
	if not _validate_warmup_state():
		_finish()
		return
	var previous := Time.get_ticks_usec()
	var measurement_start := previous
	var previous_phase := "idle"
	var next_hit := 3.3
	while not finished:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := float(now - measurement_start) / 1000000.0
		var frame_number := Engine.get_process_frames()
		var frame := {"phase": previous_phase, "wall_ms": float(now - previous) / 1000.0,
			"frame": frame_number, "elapsed": elapsed,
			"break_offset": frame_number - break_frame if frame_number - break_frame <= 2 else -1,
			"hit_offset": frame_number - hit_frame if frame_number - hit_frame <= 2 else -1,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0}
		frames.append(frame)
		previous = now
		game.idle_time = 0.0
		game.focused = false
		if elapsed < 1.5:
			previous_phase = "idle"
		elif elapsed < 3.0:
			previous_phase = "orbit"
			var angle := sin((elapsed - 1.5) / 1.5 * TAU) * 0.75
			game.shell.quaternion = Quaternion(Vector3.UP, angle) * initial_rotation
		elif elapsed < 3.3:
			previous_phase = "orbit_settle"
			game.shell.quaternion = initial_rotation
		elif hit_index < EXPECTED_HITS:
			previous_phase = "mining"
			if elapsed >= next_hit:
				_strike()
				next_hit = elapsed + HIT_INTERVAL
		else:
			previous_phase = "residual_effects"
			if elapsed >= next_hit + 2.3:
				_finish()

func _validate_warmup_state() -> bool:
	if not game.find_children("GemRenderWarmup", "", true, false).is_empty():
		errors.append("GemRenderWarmup survived startup")
	if game.gems.size() != 6 or initial_gem_state.size() != 6:
		errors.append("Startup changed the six real gems")
	if game.hit_count != 0 or game.broken_count != 0 or game.collected_count != 0 or game.gems_collected_this_rock != 0 or not game.collecting_gems.is_empty():
		errors.append("Startup caused a hit, destruction, or award")
	for state in initial_gem_state:
		var jewel: StaticBody3D = state.jewel
		if not is_instance_valid(jewel) or not game.gems.has(jewel):
			errors.append("Startup removed a real gem")
			continue
		if jewel.visible or not jewel.is_embedded or jewel.is_emerging or jewel.collected or jewel.collision_layer != 0:
			errors.append("Startup exposed or enabled an embedded gem")
		if jewel.host_chunk == null or jewel.host_chunk.get_ref() != state.owner or jewel.get_parent() != state.parent or jewel.transform != state.transform:
			errors.append("Startup changed a real gem's host, parent, or transform")
		if jewel.facets.get_parent() != state.facets_parent or jewel.facets.transform != state.facets_transform:
			errors.append("Startup changed a real gem's visible mesh placement")
	warmup_validated = errors.is_empty()
	return warmup_validated

func _observe_warmup_frame() -> void:
	if not warmup_render.is_empty() or not is_instance_valid(game):
		return
	var nodes := game.find_children("GemRenderWarmup", "SubViewport", true, false)
	if nodes.is_empty():
		return
	var viewport: SubViewport = nodes[0]
	warmup_render = {"size": [viewport.size.x, viewport.size.y],
		"mesh_nodes": viewport.find_children("*", "MeshInstance3D", true, false).size(),
		"visible_draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_objects": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)}

func _prewarm_gem_meshes() -> void:
	var saved: Array[Dictionary] = []
	for i in range(game.gems.size()):
		var jewel: StaticBody3D = game.gems[i]
		var mesh: MeshInstance3D = jewel.facets
		saved.append({"mesh": mesh, "parent": mesh.get_parent(), "transform": mesh.transform,
			"visible": mesh.visible, "jewel": jewel, "owner": jewel.host_chunk.get_ref()})
		mesh.reparent(game, false)
		var offset := Vector3((float(i % 3) - 1.0) * 1.30, 0.70 if i < 3 else -0.70, -8.0)
		mesh.global_transform = Transform3D(game.camera.global_basis, game.camera.to_global(offset))
		mesh.show()
	# Two submitted visible frames allow all six actual materials/meshes to draw.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for state in saved:
		var mesh: MeshInstance3D = state.mesh
		mesh.reparent(state.parent, false)
		mesh.transform = state.transform
		mesh.visible = state.visible
		var jewel: StaticBody3D = state.jewel
		if not jewel.is_embedded or jewel.visible or jewel.collision_layer != 0 or jewel.host_chunk.get_ref() != state.owner:
			errors.append("Gem prewarm changed embedded ownership or collision state")
	prewarm_gem_count = saved.size()

func _strike() -> void:
	var host: StaticBody3D = covers[hit_index % 6]
	if not is_instance_valid(host):
		errors.append("Host freed before scheduled final hit %d" % hit_index)
		_finish()
		return
	var candidates: Array[Vector3] = [host.face_center]
	for point in host.face_points:
		candidates.append(host.face_center.lerp(point, 0.30))
	var screen := Vector2.ZERO
	var found := false
	for local_point in candidates:
		var candidate: Vector2 = game.camera.unproject_position(host.mesh_instance.to_global(local_point))
		if game.ray_at(candidate).get("collider") == host:
			screen = candidate
			found = true
			break
	if not found:
		errors.append("Showcase host not ray-visible at hit %d" % hit_index)
		_finish()
		return
	game.aim_position = screen
	if not game.pickaxe.is_swinging:
		game.pickaxe.set_target(screen)
		game.pickaxe.set_contact_point(host.mesh_instance.to_global(host.face_center))
		game.pickaxe.swing()
	var before := game.broken_count
	game._mine_at(screen)
	# A call after post_draw affects the next drawn frame (offset 0), then two tails.
	hit_frame = Engine.get_process_frames() + 1
	if game.broken_count > before:
		break_frame = hit_frame
	hit_index += 1

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in sorted:
		sum += float(value)
	return {"count": sorted.size(), "mean": sum / sorted.size(), "p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95), "p99": _percentile(sorted, 0.99), "max": sorted.back()}

func _percentile(sorted: Array, ratio: float) -> float:
	return float(sorted[clampi(int(ceil(ratio * sorted.size())) - 1, 0, sorted.size() - 1)])

func _frame_stats(selected: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in ["wall_ms", "draw_calls", "objects", "primitives", "process_ms", "physics_ms"]:
		var values: Array = []
		for frame in selected:
			values.append(frame[key])
		result[key] = _stats(values)
	return result

func _finish() -> void:
	if finished:
		return
	finished = true
	if game != null and (game.hit_count != EXPECTED_HITS or game.gems_collected_this_rock != 6):
		errors.append("Scenario incomplete: hits=%d gems=%d" % [game.hit_count, game.gems_collected_this_rock])
	var phases: Dictionary = {}
	for phase in ["idle", "orbit", "orbit_settle", "mining", "residual_effects"]:
		phases[phase] = _frame_stats(frames.filter(func(frame): return frame.phase == phase))
	var breaks := frames.filter(func(frame): return frame.break_offset >= 0)
	var hits := frames.filter(func(frame): return frame.hit_offset >= 0 and frame.break_offset < 0)
	var cpu: Dictionary = {}
	var mine_normal: Array = []
	var mine_broken: Array = []
	for sample in game.mine_samples:
		if sample.broken:
			mine_broken.append(sample.cpu_ms)
		else:
			mine_normal.append(sample.cpu_ms)
	cpu["mine_normal_ms"] = _stats(mine_normal)
	cpu["mine_broken_ms"] = _stats(mine_broken)
	cpu["first_hit_ms"] = mine_normal.front() if not mine_normal.is_empty() else null
	cpu["first_break_ms"] = mine_broken.front() if not mine_broken.is_empty() else null
	cpu["later_breaks_ms"] = _stats(mine_broken.slice(1))
	for timings in [game.effects.timings, game.audio.timings]:
		for label in timings:
			cpu[label] = _stats(timings[label])
	var report := {"tag": tag, "seed": SEED, "renderer": renderer_name,
		"prewarm_gem": prewarm_gem, "prewarm_gem_count": prewarm_gem_count,
		"warmup_validated": warmup_validated,
		"warmup_render": warmup_render,
		"adapter": RenderingServer.get_video_adapter_name(), "vsync": "disabled", "window": [1152, 800],
		"startup_ms": startup_ms, "hits": game.hit_count, "broken": game.broken_count,
		"gems_collected": game.gems_collected_this_rock, "errors": errors,
		"all_frames": _frame_stats(frames), "phases": phases, "cpu": cpu,
		"broken_frame_and_next_2": _frame_stats(breaks), "normal_hit_frame_and_next_2": _frame_stats(hits),
		"mine_samples": game.mine_samples, "frame_samples": frames,
		"notes": ["Stress workload: six real front gem hosts, one hit every 80 ms, 16 rounds.",
			"Wall frames use RenderingServer.frame_post_draw; no screenshots or disk writes in measurement.",
			"Frame windows are rendered frame 0 plus next 2 following the synchronous mine call.",
			"Method wrappers include super() only; frame sampling and wrappers add small profiling overhead.",
			"No GPU timestamp queries: render wall duration includes CPU, driver, scheduling and GPU contention."]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var path := "res://artifacts/profile_mining_%s.json" % tag
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print("MINING_PROFILE_", "OK" if errors.is_empty() else "FAILED", " path=", path,
		" frames=", frames.size(), " hits=", game.hit_count, " broken=", game.broken_count,
		" mine_cpu=", cpu, " frame_ms=", report.all_frames.wall_ms)
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
