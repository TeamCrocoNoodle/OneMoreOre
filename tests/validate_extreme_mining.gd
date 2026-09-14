extends SceneTree
const Game = preload("res://scripts/main.gd")
var game: Node3D
var checks := 0
var failures := 0
var seen_rays := 0

func _initialize() -> void:
	_run.call_deferred()
	create_timer(120).timeout.connect(func(): push_error("EXTREME_VALIDATION_TIMEOUT"); quit(2))

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 15: push_error(message)

func _step() -> void:
	game._advance_bulk_breaks()
	game._advance_damage_visuals()
	game._advance_ore_retirement()
	game._update_collections(.016)
	await process_frame

func _build() -> void:
	while game.ore_building:
		game._advance_ore_build()
		await _step()
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1.0
	game._start_round()
	await physics_frame
	await physics_frame

func _finish_blast() -> void:
	while game._bulk_job != null: await _step()

func _run() -> void:
	root.size = Vector2i(1152,800)
	AudioServer.set_bus_mute(0,true)
	game = Game.new()
	root.add_child(game)
	for node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.focused = true
	game.campaign.cleared = 6
	game.upgrade_stats.gem_spawn_bonus = 1.0
	game._spawn_rock(12873)
	await _build()
	_check(game.chunks.size() == 4736 and game.gems.size() == 68,"Maximum ore keeps 4,736 independent stones and 68 buried gems")
	_audit_deferred_visuals()
	# Staging must not make invisible stones selectable, even at identical world
	# coordinates to the active ore and while the camera orbits the whole sphere.
	while not game._ore_preparation.complete:
		game._advance_ore_preparation()
		await _step()
	var future: Array = game._ore_preparation.chunks.duplicate()
	await _audit_views(false)
	# Exercise narrow deep tunnels, side/back openings and disconnected AoE
	# cavities, checking the first real physics hit after every depth change.
	await _audit_views(true)
	_check(seen_rays > 400,"Visibility audit includes hundreds of real surface hits")
	var before_count: int = game.chunks.size()
	var sample: StaticBody3D = game.chunks[0]
	var health_before: float = sample.health
	var remaining: float = game.round_state.remaining
	var result: Dictionary = game.remove_with_auxiliary(game.chunks.duplicate(),1.0,false,.01)
	_check(result.get("pending",false),"Large partial blasts use bounded transactions")
	game._advance_round(10.0)
	_check(game.round_state.remaining == remaining,"The deadline cannot expire halfway through one extraction")
	_check(not game._round_allows_mining() and game.ray_at(game.aim_position).is_empty(),"A pending extraction cannot be struck twice or select a hidden collider")
	await _finish_blast()
	_check(game.chunks.size() == before_count and is_equal_approx(sample.health,health_before-.01),"Partial damage is applied exactly once without deleting surviving stones")
	_check(future.all(func(chunk):return not chunk.destroyed and chunk.health == chunk.max_health),"The future ore never receives the current ore's blast damage")
	var gem_counts_before: PackedInt32Array = game.round_state.gem_counts.duplicate()
	var expected_gems := PackedInt32Array([0,0,0,0,0,0,0])
	for jewel in game.gems: expected_gems[jewel.grade] += 1
	var expected_stones: int = game.chunks.size()-game.gems.size()
	var stones_before: int = game.round_state.ordinary_stones
	var retired: Array = game.chunks.duplicate()
	game.remove_with_auxiliary(game.chunks.duplicate(),1.0,false,10000000.0)
	_check(not game.shell.visible,"An extreme all-ore destruction disappears in the activation frame")
	await _finish_blast()
	_check(game.chunks.is_empty() and game.gems.is_empty(),"A full blast finishes every target and embedded gem")
	_check(game.round_state.ordinary_stones-stones_before == expected_stones,"Thousands of simultaneous breaks count each ordinary stone once")
	for grade in 7:
		_check(game.round_state.gem_counts[grade]-gem_counts_before[grade] == expected_gems[grade],"Exact grade accounting through a sliced blast: "+str(grade))
	game._spawn_rock()
	_check(not game.ore_building and game.chunks.size() == 4736,"Prepared ore is immediately playable without per-stone reattachment")
	_check(future.all(func(chunk):return game.chunks.has(chunk)),"Activation preserves all prepared stone instances")
	await _build()
	await _audit_views(false)
	for i in 160: await _step()
	_check(retired.all(func(chunk):return not is_instance_valid(chunk)),"Destroyed GPU meshes / physics bodies drain completely")
	_check(game._retired_chunks.is_empty() and game._retired_containers.is_empty(),"Repeated activation leaves no retirement backlog")
	_check(game.effects.rings.size() <= game.effects.RING_POOL_CAPACITY and game.effects.loose_chunks.size() <= game.effects.FRAGMENT_CAPACITY,"Effect pools remain bounded under simultaneous destruction")
	# Interrupt a large operation by resetting the scene. No queued job may
	# award the new ore's gems, collide with it, or revive after the reset.
	game.remove_with_auxiliary(game.chunks.duplicate(),.5,true,10000000.0)
	game._advance_bulk_breaks()
	var credited: PackedInt32Array = game.round_state.gem_counts.duplicate()
	game._spawn_rock(12875)
	await _build()
	_check(game._bulk_job == null and game.round_state.gem_counts == credited,"Reset cancels only the unfinished extraction, with no later awards")
	for i in 180: await _step()
	_check(game._retired_chunks.is_empty() and game._retired_containers.is_empty(),"Reset also releases partial-batch and previous ore resources")
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print("EXTREME_VALIDATION checks=",checks," failures=",failures," rays=",seen_rays)
	quit(0 if failures == 0 else 1)

func _audit_deferred_visuals() -> void:
	var chunk: StaticBody3D
	for candidate in game.chunks:
		if candidate.layer_index == 0 and not candidate.is_gem_cover:
			chunk = candidate
			break
	var before: float = chunk.health
	var contact: Vector3 = chunk.mesh_instance.to_global(chunk.face_center)
	for i in 5: chunk.hit(.01,contact,false)
	_check(is_equal_approx(chunk.health,before-.05) and chunk.impact_count == 5,"Deferred visuals never discard damage or hit counts")
	_check(chunk._pending_visual_hits.size() == 2,"A busy secondary target retains bounded recent crack anchors")
	chunk.flush_damage_visuals()
	_check(chunk._pending_visual_hits.is_empty() and chunk.impact_count == 5 and is_instance_valid(chunk._crack_mesh),"Flushing secondary cracks preserves hit provenance")
	_check(chunk.is_processing(),"Lazy crack creation must not stop an active hit animation")
	chunk._process(.7)
	_check(is_zero_approx(chunk._flash) and is_zero_approx(chunk._material.get_shader_parameter("hit_flash")) and not chunk.is_processing(),"Secondary hit flashes decay completely instead of sticking on the stone")

func _audit_views(excavate: bool) -> void:
	for turn in 10:
		game.shell.rotation = Vector3(sin(turn*.9)*.8,turn*TAU/10.0,.12)
		await physics_frame
		await physics_frame
		if excavate:
			for depth in 8:
				var screen := root.get_visible_rect().size*Vector2(.48,.47)
				var hit: Dictionary = game.ray_at(screen)
				if hit.is_empty() or not game.chunks.has(hit.collider): break
				_check(hit.collider.visible,"Deep drilling always hits a rendered stone")
				game.remove_with_auxiliary([hit.collider])
				await physics_frame
				await _step()
		for y in range(2,9):
			for x in range(2,13):
				var screen := root.get_visible_rect().size*Vector2(x/14.0,y/10.0)
				var hit: Dictionary = game.ray_at(screen)
				if hit.is_empty(): continue
				seen_rays += 1
				_check(game.chunks.has(hit.collider) and hit.collider.is_visible_in_tree(),"Orbit rays never select a culled, retired or staged stone")

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)
