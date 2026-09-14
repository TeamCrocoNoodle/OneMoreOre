extends "res://tests/validate_tools.gd"
const RoundState = preload("res://scripts/mining_round.gd")
const MainTools = preload("res://scripts/main_tools.gd")
const Balance = preload("res://scripts/skill_balance.gd")

class RangeGame extends TestGame:
	var raycasts := 0
	func ray_at(point: Vector2) -> Dictionary:
		raycasts += 1
		return super.ray_at(point)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	game = RangeGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	await physics_frame
	var point := _surface_point()
	_check(point != Vector2.ZERO, "A visible surface exists for the real attack preview")
	game.aim_position = point
	var hit: Dictionary = game.ray_at(point)
	var state: int = game.mining_skills.random.state
	game.raycasts = 0
	game._update_attack_preview(hit)
	_check(game.attack_range.ring.visible, "A stone under the cursor shows the range before the first strike")
	_check(game.attack_range.ring.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The ring does not intercept mining or HUD input")
	_check(game.raycasts <= 16, "A preview uses at most 16 bounded extra surface rays")
	_check(game.round_state.phase == RoundState.Phase.READY and game.mining_skills.attacks == 0 and game.mining_skills.random.state == state, "Previewing never starts the timer, attacks, or rolls skills")
	var base_radius: float = game.attack_range.ring.radius
	var values: Dictionary = game.upgrade_stats.duplicate()
	values.range_bonus = 1.0
	game.mining_skills.configure(values)
	game._update_attack_preview(hit)
	_check(is_equal_approx(game.attack_range.ring.radius, base_radius * 2.0), "A 100 percent range upgrade doubles the visible radius")
	values.spent_range = 1.0
	game.mining_skills.configure(values)
	game.round_state.spent = Balance.value("spent_threshold")
	game._update_attack_preview(hit)
	var spent_radius: float = game.attack_range.ring.radius
	_check(spent_radius > base_radius * 2.0, "The spent-health range skill expands the preview when its condition becomes true")
	game.mining_skills.buff = 2
	game.mining_skills.buff_remaining = 0.1
	game._update_attack_preview(hit)
	_check(game.attack_range.ring.radius > spent_radius, "A temporary range buff expands the current preview")
	game.mining_skills.advance(0.2)
	game._update_attack_preview(hit)
	_check(is_equal_approx(game.attack_range.ring.radius, spent_radius), "The circle returns to its prior size as soon as the buff expires")
	game.round_state.spent = 0.0
	# Compare the highlight against damage to every actual chunk, rather than
	# comparing two copies of the area-sampling algorithm.
	for entry: Dictionary in MainTools.CATALOG:
		game.main_tools.acquire(entry.id, int(entry.price))
		game.main_tools.equip(entry.id)
		game._apply_upgrade_stats()
		for chunk in game.chunks:
			chunk.health = 10000.0
			chunk.max_health = 10000.0
		game._update_attack_preview(game.ray_at(point))
		var preview: Array = game._attack_preview_chunks.duplicate()
		_check(preview.size() >= 1 and preview.size() <= 9, "Direct strike preview remains bounded for " + entry.id)
		_check(game._mine_at(point), "The previewed strike executes for " + entry.id)
		for chunk in game.chunks:
			_check((chunk.health < 10000.0) == preview.has(chunk), "Only highlighted chunks receive direct damage for " + entry.id)
		_check(is_equal_approx(game.attack_range.ring.radius / base_radius, entry.radius), "Equipped tool range is reflected exactly for " + entry.id)
	game.main_tools.equip("hammer")
	game._apply_upgrade_stats()
	await _validate_projection()
	game.aim_position = _surface_point()
	hit = game.ray_at(game.aim_position)
	_validate_visibility(hit)
	_validate_guards(hit)
	# Highlight is not copied into flying fracture meshes.
	game._update_attack_preview(hit)
	var body: StaticBody3D = hit.collider
	body.health = 0.1
	body.max_health = 1.0
	game._mine_at(game.aim_position)
	_check(not game.effects.loose_chunks.is_empty(), "The highlighted stone fractures into actual debris")
	for fragment: Dictionary in game.effects.loose_chunks:
		var material: ShaderMaterial = fragment.node.material_override
		_check(is_zero_approx(float(material.get_shader_parameter("attack_preview"))), "Fracture debris does not retain target highlighting")
	game._physics_process(0.0)
	_check(not game._attack_preview_chunks.has(body), "A broken chunk is removed from the preview in the same physics update")
	game._clear_ore_scene()
	_check(not game.attack_range.ring.visible and game._attack_preview_chunks.is_empty(), "Replacing an ore clears every range visual")
	_stop_audio(game)
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	ended = true
	print("ATTACK_RANGE_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _surface_point() -> Vector2:
	var center := root.get_visible_rect().size * 0.5
	var best := Vector2.ZERO
	var count := -1
	for y in range(-140, 141, 35):
		for x in range(-140, 141, 35):
			var point := center + Vector2(x, y)
			var hit: Dictionary = game.ray_at(point)
			if hit.is_empty() or not game.chunks.has(hit.collider) or game._aim_over_hud(point): continue
			var next: int = game._area_targets(point, hit).size()
			if next > count:
				count = next
				best = point
	return best

func _validate_projection() -> void:
	for dimensions: Vector2i in [Vector2i(360, 800), Vector2i(800, 450), Vector2i(1920, 1080), Vector2i(3440, 1440), Vector2i(1152, 800)]:
		root.size = dimensions
		await process_frame
		game._resize()
		game.aim_position = _surface_point()
		var hit: Dictionary = game.ray_at(game.aim_position)
		game._update_attack_preview(hit)
		var ring: Control = game.attack_range.ring
		var pixels: Transform2D = root.get_final_transform()
		var radius: float = game.mining_skills.radius(0)
		var edge: Vector2 = game.camera.unproject_position(hit.position + game.camera.global_basis.x * radius)
		_check(ring.visible and ring.position.distance_to(game.aim_position) < 0.01, "Circle stays centered on the aim under window stretch")
		_check(absf((pixels * edge).distance_to(pixels * ring.position) - (pixels.x * ring.radius).length()) < 0.1, "The physical ring edge matches world attack radius at " + str(dimensions))
		var before: float = ring.radius
		game.camera.keep_aspect = Camera3D.KEEP_WIDTH
		game._update_attack_preview(hit)
		edge = game.camera.unproject_position(hit.position + game.camera.global_basis.x * radius)
		var center: Vector2 = game.camera.unproject_position(hit.position)
		_check(is_equal_approx(ring.radius, edge.distance_to(center)), "Range projection respects either camera aspect policy")
		game._resize()
		game._update_attack_preview(hit)
		_check(is_equal_approx(ring.radius, before), "Restoring framing restores the same range size")

func _validate_visibility(hit: Dictionary) -> void:
	game.round_state.phase = RoundState.Phase.READY
	game._update_attack_preview(hit)
	var previous: Array = game._attack_preview_chunks.duplicate()
	game._open_upgrades()
	_check(not game.attack_range.ring.visible, "Opening upgrades immediately hides the range")
	for chunk in previous:
		_check(is_zero_approx(float(chunk._material.get_shader_parameter("attack_preview"))), "Opening upgrades clears all affected stone tint")
	game.skill_ui.close_tree()
	game._update_attack_preview(hit)
	_check(game.attack_range.ring.visible, "Returning to mining restores the range")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not game.attack_range.ring.visible and game._attack_preview_chunks.is_empty(), "Focus loss immediately clears range and highlights")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.dragging = true
	game._update_attack_preview(hit)
	_check(not game.attack_range.ring.visible, "Orbit dragging hides the mining footprint")
	game.dragging = false
	game.touch_id = 0
	game._update_attack_preview(hit)
	_check(game.attack_range.ring.visible, "Touch aiming has the same range preview")
	game.touch_rotating = true
	game._update_attack_preview(hit)
	_check(not game.attack_range.ring.visible, "A touch orbit hides the range")
	game.touch_id = -1
	game.touch_rotating = false
	game.using_controller = true
	game._update_attack_preview(hit)
	_check(game.attack_range.ring.visible, "Controller aiming has the same range preview")
	game.using_controller = false
	game._update_attack_preview({})
	_check(not game.attack_range.ring.visible and game._attack_preview_chunks.is_empty(), "Empty space clears the ring and old stone tint")
	var aim: Vector2 = game.aim_position
	game.aim_position = game.hud._upgrades.get_global_rect().get_center()
	game._update_attack_preview(hit)
	_check(not game.attack_range.ring.visible, "Hovering a real HUD button cannot show an attack preview")
	game.aim_position = aim
	game._start_round()
	game._update_attack_preview(hit)
	game._advance_round(game.round_state.duration + 1.0)
	_check(not game.attack_range.ring.visible and game._attack_preview_chunks.is_empty(), "Timer expiry immediately clears the footprint")
	game.round_state.phase = RoundState.Phase.MINING
	game.round_state.remaining = game.round_state.duration

func _validate_guards(hit: Dictionary) -> void:
	var boss: Node3D = game.boss
	boss.active = true
	boss.stage = 4
	boss.spikes_out = true
	var health: float = game.round_state.remaining
	game._update_attack_preview(hit)
	_check(game.round_state.remaining == health, "Hovering a spike boss does not hurt the player")
	hit.collider.set_meta("boss_protected", true)
	game._update_attack_preview(hit)
	_check(not game._attack_preview_chunks.has(hit.collider), "Protected chunks are excluded without triggering blocked-hit effects")
	hit.collider.remove_meta("boss_protected")
	boss.stage = 5
	boss.volley_rest = false
	game._update_attack_preview(hit)
	_check(game._attack_preview_chunks.is_empty(), "An invulnerable artillery hull is not highlighted as damageable")
	boss.active = false
