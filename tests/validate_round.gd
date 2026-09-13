extends SceneTree
## Exact round boundaries, immutable settlement, and real mining/arrival flows.
const Round = preload("res://scripts/mining_round.gd")
const Main = preload("res://scripts/main.gd")
const Gem = preload("res://scripts/gem.gd")
const RATES := [15, 60, 220, 800, 2400, 7200, 22000]

var checks := 0
var failures: Array[String] = []
var game: Node3D


func _initialize() -> void:
	_run.call_deferred()
	create_timer(40.0).timeout.connect(func():
		push_error("ROUND_VALIDATION_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	_validate_model()
	if not "--model-only" in OS.get_cmdline_user_args():
		await _validate_gameplay()
		await _validate_hud_input()
		await _validate_touch_buttons()
	if is_instance_valid(game):
		_stop_audio(game)
		game.queue_free()
	await process_frame
	# Audio playback teardown is delivered to the mixer on its next block.
	# A headless test can otherwise quit before that deferred release runs.
	await create_timer(0.1).timeout
	print("ROUND_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _validate_model() -> void:
	var round_state := Round.new()
	_check(round_state.phase == Round.Phase.READY and round_state.remaining == 30.0, "A fresh round waits with exactly 30 seconds")
	_check(Round.STONE_GOLD == 1 and Round.GEM_GOLD == RATES, "Stone and all seven grade rates use the shared published price table")
	_check(not round_state.advance(12.0) and round_state.remaining == 30.0, "Waiting before the first swing does not consume mining time")
	_check(not round_state.record_stone() and not round_state.record_gem(0), "A round cannot receive cargo before mining starts")
	_check(not round_state.commit_settlement() and not round_state.new_round(), "Neither payment nor restart can skip the initial mining phase")
	_check(round_state.start() and not round_state.start(), "The first mining start succeeds exactly once")
	_check(not round_state.advance(29.0) and round_state.remaining == 1.0, "The final full second remains available")
	_check(not round_state.advance(-1.0) and not round_state.advance(NAN) and round_state.remaining == 1.0, "Invalid frame deltas cannot rewind or corrupt the deadline")
	for i in 7:
		_check(round_state.record_stone(), "Destroyed ordinary stone is accepted while mining")
	var counts := PackedInt32Array([1, 2, 3, 4, 5, 6, 7])
	for tier in RATES.size():
		for i in counts[tier]:
			round_state.record_gem(tier)
	_check(not round_state.record_gem(-1) and not round_state.record_gem(7) and round_state.gem_counts == counts, "All seven valid grades have exact separate cargo quantities")
	_check(round_state.advance(1.0) and round_state.remaining == 0.0 and round_state.phase == Round.Phase.DRAINING, "Reaching exactly 30 seconds expires before another award")
	_check(not round_state.advance(2.0) and not round_state.record_stone() and not round_state.record_gem(5), "Expiry triggers once and rejects every later cargo award")
	_check(round_state.ordinary_stones == 7 and round_state.gem_counts == counts, "Cargo from the last valid mining interval survives draining")
	_check(not round_state.commit_settlement() and not round_state.new_round(), "Draining cannot pay or restart before settlement")
	var report := round_state.begin_settlement()
	_check(round_state.phase == Round.Phase.SETTLING and round_state.wallet_gold == 0, "Beginning settlement freezes the report before moving any gold")
	var total := _validate_report(report, 7, counts, 0)
	_check(round_state.begin_settlement() == report and round_state.wallet_gold == 0, "Repeated report requests cannot revalue cargo or pay twice")
	_check(round_state.commit_settlement() and round_state.wallet_gold == total and round_state.phase == Round.Phase.COMPLETE, "Finishing settlement pays the exact total once")
	_check(not round_state.commit_settlement() and round_state.wallet_gold == total, "Repeated settlement completion cannot duplicate payment")
	_check(round_state.ordinary_stones == 0 and round_state.gem_counts == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]) and round_state.last_report == report, "Sold cargo clears while the final receipt remains readable")
	var prior_index := round_state.round_index
	_check(round_state.new_round() and not round_state.new_round(), "Only a completed round can create its next round once")
	_check(round_state.phase == Round.Phase.READY and round_state.remaining == 30.0 and round_state.wallet_gold == total and round_state.round_index == prior_index + 1 and round_state.last_report.is_empty(), "A fresh round resets cargo and time while retaining its wallet")
	round_state.start()
	round_state.advance(30.0)
	var empty_report := round_state.begin_settlement()
	_validate_report(empty_report, 0, PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), total)
	_check(round_state.commit_settlement() and round_state.wallet_gold == total, "An empty round completes normally without changing the wallet")


func _validate_report(report: Dictionary, stones: int, counts: PackedInt32Array, wallet_before: int) -> int:
	var expected := stones
	var expected_rows := 1
	for tier in RATES.size():
		expected += counts[tier] * RATES[tier]
		if counts[tier] > 0:
			expected_rows += 1
	_check(report.get("total", -1) == expected and report.get("wallet_before", -1) == wallet_before and report.get("wallet_after", -1) == wallet_before + expected, "Settlement total equals ordinary stones plus all seven independent grade subtotals")
	_check(report.get("ordinary_stones", -1) == stones and report.get("gem_counts", PackedInt32Array()) == counts, "The receipt retains the precise cargo snapshot")
	var rows: Array = report.get("rows", [])
	var seen := {}
	var row_sum := 0
	var valid := rows.size() == expected_rows
	for row: Dictionary in rows:
		var tier := int(row.get("tier", -2))
		valid = valid and not seen.has(tier)
		seen[tier] = true
		var quantity := stones if tier == -1 else (counts[tier] if tier >= 0 and tier < RATES.size() else -1)
		var rate: int = 1 if tier == -1 else (RATES[tier] if tier >= 0 and tier < RATES.size() else -1)
		valid = valid and int(row.get("count", -1)) == quantity and int(row.get("unit_gold", -1)) == rate and int(row.get("gold", -1)) == quantity * rate
		row_sum += int(row.get("gold", 0))
	_check(valid and seen.has(-1) and row_sum == expected, "Receipt rows show each earned grade once with matching quantity, shared rate and subtotal")
	return expected


func _validate_gameplay() -> void:
	await _new_game()
	var state: Round = game.round_state
	_check(game.round_enabled and state.phase == Round.Phase.READY and game.hud != null, "Normal gameplay enables a waiting round and its HUD")
	for frame in 4:
		await process_frame
	_check(_flight_overlay_idle(), "An idle round keeps the empty flight viewport disabled and its retained texture hidden")
	game._physics_process(8.0)
	_check(state.remaining == 30.0 and state.phase == Round.Phase.READY, "Main physics does not spend time before the first valid swing")
	var ordinary := _ordinary_target()
	_check(not ordinary.is_empty(), "The ordinary-destruction fixture uses a real visible starter stone")
	if ordinary.is_empty():
		return
	var stone: StaticBody3D = ordinary.body
	var screen: Vector2 = ordinary.screen
	_check(game._mine_at(screen) and state.phase == Round.Phase.MINING, "A real first mining impact starts the round")
	_check(state.ordinary_stones == 0 and game.hud.displayed_stones == 0, "A chip or nonfatal hit does not count as a destroyed ordinary stone")
	while not stone.destroyed:
		if not game._mine_at(screen):
			_check(false, "Subsequent impacts on the visible ordinary stone are accepted")
			return
	_check(state.ordinary_stones == 1 and game.hud.displayed_stones == 1 and game.effects.loose_chunks.size() > 1, "One destroyed stone counts once despite producing multiple physical fragments")
	_check(state.gem_counts == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), "Ordinary destruction does not invent a gem reward")
	game._physics_process(2.0)
	var before_pause := state.remaining
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._physics_process(3.0)
	_check(state.remaining == before_pause, "Focus loss pauses the authoritative mining clock")
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._physics_process(1.0)
	_check(state.remaining == before_pause - 1.0, "Focus return resumes the same remaining time")
	var before_reset := state.remaining
	game._reset_rock()
	await _finish_spawn()
	_check(state.remaining == before_reset and state.ordinary_stones == 1 and state.phase == Round.Phase.MINING, "Resetting an active rock preserves its deadline and earned stone cargo")
	var owner := await _isolated_owner(Gem.SPECIAL)
	if owner.is_empty():
		return
	var jewel: StaticBody3D = owner.jewel
	var owner_body: StaticBody3D = owner.body
	owner_body.health = 1.0
	state.advance(state.remaining - 0.125)
	_check(game._mine_at(owner.screen), "The last valid fraction of a second can break a real gem owner")
	var cargo := PackedInt32Array([0, 1, 0, 0, 0, 0, 0])
	_check(state.gem_counts == cargo and state.ordinary_stones == 1, "A gem owner credits its exact grade at destruction and is excluded from ordinary-stone cargo")
	_check(jewel.collected and jewel.is_emerging and game.collecting_gems.size() == 1 and game.hud.displayed_counts[Gem.SPECIAL] == 0, "The last-frame reward is credited while its real crystal still emerges, before HUD arrival")
	var extraction: Dictionary = game.collecting_gems[0]
	var queued := await _expose_one_ordinary()
	if queued.is_empty():
		return
	var queued_body: StaticBody3D = queued.body
	queued_body.health = 1.0
	game.pending_aim = queued.screen
	game.pending_rock_number = game.rock_number
	game.impact_pending = true
	game.mouse_down = true
	game.dragging = true
	game.touch_id = 0
	game.touch_rotating = true
	var hits_before := int(game.hit_count)
	game._physics_process(0.125)
	_check(state.phase == Round.Phase.DRAINING and state.remaining == 0.0 and not game.impact_pending, "Deadline processing precedes and cancels a queued physics impact")
	_check(game.hit_count == hits_before and queued_body.health == 1.0 and state.ordinary_stones == 1, "The exact deadline admits no extra hit, stone destruction or fragment reward")
	_check(not game.mouse_down and not game.dragging and game.touch_id == -1 and not game.touch_rotating, "Expiry clears mouse, drag and touch mining state")
	game._begin_settlement()
	_check(state.phase == Round.Phase.DRAINING and not game.hud.settlement_visible, "Settlement waits for the already credited in-flight gem")
	_check(not game._mine_at(queued.screen) and not game._collect_gem(jewel) and state.gem_counts == cargo, "Neither late mining nor repeated collection can alter expired cargo")
	var orientation: Quaternion = game.shell.quaternion
	game.idle_time = 10.0
	Input.action_press("orbit_right")
	game._process(0.016)
	Input.action_release("orbit_right")
	game._orbit(Vector2(0.5, 0.5))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = queued.screen
	game._input(press)
	_check(game.shell.quaternion.is_equal_approx(orientation) and not game.mouse_down and game.hit_count == hits_before, "Expired gameplay ignores direct orbit, held rotation, auto-rotation and new mouse mining")
	await create_timer(0.45).timeout
	_check(not jewel.is_emerging and jewel.visible and jewel.get_parent() == game, "Deadline draining preserves the real crystal's complete emergence animation")
	var actual_mesh: Mesh = jewel.facets.mesh
	var actual_material: Material = jewel.facets.material_override
	game._update_collections(0.0)
	var overlay: CanvasLayer = game.flight_overlay
	_check(overlay.active_count == 1 and jewel.get_parent() == overlay._scene and jewel.get_world_3d() != game.get_world_3d() and jewel.facets.mesh == actual_mesh and jewel.facets.material_override == actual_material and overlay.layer > game.hud.layer, "The original crystal and its material fly in the dedicated world above the HUD")
	overlay.adopt(jewel)
	_check(overlay.active_count == 1 and overlay._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and overlay._display.visible, "A flying crystal enables rendering once and repeated adoption cannot duplicate it")
	var start: Vector2 = game.camera.unproject_position(jewel.global_position)
	var destination: Vector2 = game.hud.gem_target_screen(Gem.SPECIAL)
	game._update_collections(0.35)
	var halfway: Vector2 = game.camera.unproject_position(jewel.global_position)
	var expected_halfway := start.lerp(destination, 0.5) + Vector2(0, -root.get_visible_rect().size.y * 0.12)
	_check(halfway.is_finite() and halfway.distance_to(expected_halfway) < 0.75 and game.hud.displayed_counts[Gem.SPECIAL] == 0, "The actual 3D gem follows its viewport arc toward the matching grade slot without an early counter increment")
	game._update_collections(0.35)
	_check(game.collecting_gems.is_empty() and game.hud.displayed_counts == cargo and game.displayed_gems == cargo and state.gem_counts == cargo, "HUD arrival changes presentation once while preserving break-time cargo")
	_check(_flight_overlay_idle(), "Arrival disables the empty flight renderer and hides its last texture to prevent a destination ghost")
	game._deliver_gem_to_hud(extraction)
	game._update_collections(1.0)
	_check(game.hud.displayed_counts == cargo and game.displayed_gems == cargo, "Repeating a delivered flight callback cannot increment the HUD twice")
	game._begin_settlement()
	_check(state.phase == Round.Phase.SETTLING and game.hud.settlement_visible, "The drained round opens exactly one settlement")
	var total := _validate_report(state.last_report, 1, cargo, 0)
	_check(game.hud.displayed_rows == state.last_report.rows, "The settlement HUD reads the same quantities, rates and subtotals as the authoritative report")
	game.hud.finish_settlement()
	game.hud.finish_settlement()
	game._finish_settlement()
	_check(state.phase == Round.Phase.COMPLETE and state.wallet_gold == total and game.hud.displayed_gold == total, "Skip, animation completion and repeat completion still pay the exact report once")
	var index_before := state.round_index
	Input.action_press("mine")
	game.hud._request_next()
	var new_rock := int(game.rock_number)
	game._next_round()
	_check(state.phase == Round.Phase.READY and state.round_index == index_before + 1 and game.rock_number == new_rock and state.remaining == 30.0 and state.wallet_gold == total, "The next-round action runs once and retains wallet Gold with a fresh 30-second clock")
	_check(game.collecting_gems.is_empty() and game.displayed_gems == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]) and game.hud.displayed_counts == game.displayed_gems and not game.hud.settlement_visible and not game.impact_pending and not game.mouse_down and game.touch_id == -1, "A fresh round clears old cargo, arrivals, modal, pending hits and pointer states")
	await _finish_spawn()
	game._process(0.016)
	game._request_swing()
	_check(state.phase == Round.Phase.READY and not game.impact_pending, "A held confirm/mining action cannot spill into the next round")
	Input.action_release("mine")
	game._process(0.016)
	var next_target := _ordinary_target()
	if not next_target.is_empty():
		game.aim_position = next_target.screen
		game._request_swing()
		_check(state.phase == Round.Phase.MINING, "Releasing and issuing a fresh valid swing starts the next round")
	await _validate_reset_and_exhaustion()
	await _validate_empty_game_round()


func _validate_reset_and_exhaustion() -> void:
	await _new_game()
	var state: Round = game.round_state
	var owner := await _isolated_owner(Gem.COMMON)
	if owner.is_empty():
		return
	var jewel: StaticBody3D = owner.jewel
	owner.body.health = 1.0
	game._mine_at(owner.screen)
	game._physics_process(4.0)
	var cargo := state.gem_counts.duplicate()
	var remaining := state.remaining
	var extraction: Dictionary = game.collecting_gems[0]
	var prior_gem: WeakRef = weakref(jewel)
	game._reset_rock()
	await _finish_spawn()
	_check(state.remaining == remaining and state.gem_counts == cargo and game.hud.displayed_counts == cargo and game.collecting_gems.is_empty(), "An active reset flushes a still-emerging reward to its display without losing cargo or restarting time")
	_check(prior_gem.get_ref() == null, "Reset frees the old real crystal and its emergence tween")
	game._deliver_gem_to_hud(extraction)
	game._reset_rock()
	await _finish_spawn()
	_check(state.remaining == remaining and state.gem_counts == cargo and game.hud.displayed_counts == cargo, "Repeated reset and a stale flight callback cannot duplicate or erase earned cargo")
	owner = await _isolated_owner(Gem.COMMON)
	if owner.is_empty():
		return
	owner.body.health = 1.0
	game._mine_at(owner.screen)
	var flying_jewel: StaticBody3D = owner.jewel
	var flying_ref: WeakRef = weakref(flying_jewel)
	await create_timer(0.45).timeout
	game._update_collections(0.2)
	_check(game.flight_overlay.active_count == 1 and flying_jewel.get_parent() == game.flight_overlay._scene, "The reset fixture contains a real crystal already flying in the overlay world")
	cargo = state.gem_counts.duplicate()
	game._reset_rock()
	await _finish_spawn()
	_check(state.remaining == remaining and state.gem_counts == cargo and game.hud.displayed_counts == cargo and flying_ref.get_ref() == null and _flight_overlay_idle(), "Reset during flight delivers exactly once, frees the cross-world crystal, stops rendering and preserves time")
	# Isolate the existing exhaustion transition; the normal mining suite
	# separately verifies every physical chunk and owner in a full excavation.
	for chunk in game.chunks:
		chunk.collision_layer = 0
		chunk.queue_free()
	game.chunks.clear()
	game.gems.clear()
	game._check_exhausted()
	var number_before := int(game.rock_number)
	game._physics_process(2.5)
	var deadline_before_spawn := state.remaining
	game._process(2.5)
	await _finish_spawn()
	_check(game.rock_number == number_before + 1 and not game.chunks.is_empty(), "Exhausting a rock during mining creates a fresh rock within the same round")
	_check(state.phase == Round.Phase.MINING and state.remaining == deadline_before_spawn and state.gem_counts == cargo and game.hud.displayed_counts == cargo, "Automatic rock regeneration preserves the running deadline and accumulated cargo")


func _validate_empty_game_round() -> void:
	await _new_game()
	game._start_round()
	game._physics_process(30.0)
	game._process(0.016)
	var state: Round = game.round_state
	_check(state.phase == Round.Phase.SETTLING and game.hud.settlement_visible and state.last_report.total == 0, "A zero-reward game round still reaches its settlement UI")
	_check(game.hud.displayed_rows.is_empty(), "The empty settlement does not invent sale rows")
	game.hud.finish_settlement()
	_check(state.phase == Round.Phase.COMPLETE and state.wallet_gold == 0 and game.hud.displayed_gold == 0, "An empty round finishes and awards zero Gold")
	game.hud._request_next()
	_check(state.phase == Round.Phase.READY and state.remaining == 30.0, "The empty result can start another round normally")


func _new_game() -> void:
	if is_instance_valid(game):
		_stop_audio(game)
		game.queue_free()
		await process_frame
	game = Main.new()
	# Ledger/input fixture has all ranks unlocked; campaign gates have their own suite.
	game.campaign.cleared = 6
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.hud.set_process(false)
	game.spawn_time = 1.0
	await physics_frame
	await process_frame


func _finish_spawn() -> void:
	if game.spawn_tween != null and game.spawn_tween.is_valid():
		game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1.0
	await physics_frame
	await process_frame


func _ordinary_target() -> Dictionary:
	for body in game.chunks:
		if body.is_gem_cover:
			continue
		var screen: Vector2 = game.camera.unproject_position(body.mesh_instance.to_global(body.face_center))
		if not game.hud.is_pointer_blocked(screen) and game.ray_at(screen).get("collider") == body:
			return {"body": body, "screen": screen}
	return {}


func _isolated_owner(tier: int) -> Dictionary:
	var jewel: StaticBody3D
	for candidate in game.gems:
		if candidate.grade == tier:
			jewel = candidate
			break
	_check(is_instance_valid(jewel), "The owner fixture uses a real starter gem of the requested grade")
	if not is_instance_valid(jewel):
		return {}
	var body: StaticBody3D = jewel.host_chunk.get_ref()
	for chunk in game.chunks:
		chunk.collision_layer = 1 if chunk == body else 0
		chunk.visible = chunk == body
	game.shell.quaternion = Quaternion(body.direction, game.camera.global_basis.z.normalized())
	await physics_frame
	await process_frame
	var screen: Vector2 = game.camera.unproject_position(body.mesh_instance.to_global(body.face_center))
	_check(game.ray_at(screen).get("collider") == body, "The isolated owner is reached through Main's real physics ray")
	if game.ray_at(screen).get("collider") != body:
		return {}
	return {"body": body, "jewel": jewel, "screen": screen}


func _expose_one_ordinary() -> Dictionary:
	for body in game.chunks:
		if not body.is_gem_cover:
			body.collision_layer = 1
			body.show()
			await physics_frame
			await process_frame
			var screen: Vector2 = game.camera.unproject_position(body.mesh_instance.to_global(body.face_center))
			_check(game.ray_at(screen).get("collider") == body, "The pending-deadline fixture targets another live ordinary stone")
			if game.ray_at(screen).get("collider") == body:
				return {"body": body, "screen": screen}
	return {}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("ROUND_CHECK_FAILED: " + description)


func _flight_overlay_idle() -> bool:
	var overlay: CanvasLayer = game.flight_overlay
	return overlay.active_count == 0 and not overlay._display.visible and overlay._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not overlay.is_processing()


func _validate_hud_input() -> void:
	await _new_game()
	await _finish_spawn()
	game.pickaxe.set_process(false)
	var target := _ordinary_target()
	var tray: Vector2 = game.hud.gem_target_screen(Gem.SPECIAL)
	_check(not target.is_empty() and game.hud.is_pointer_blocked(tray), "The input fixture has a live stone and an actual protected HUD gem slot")
	if target.is_empty():
		return
	var playfield: Vector2 = target.screen
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = playfield
	game._input(press)
	game.pickaxe._process(0.4)
	game._physics_process(0.0)
	var hits := int(game.hit_count)
	_check(hits == 1 and game.mouse_down and game.round_state.phase == Round.Phase.MINING, "A real held mouse press mines once before entering the HUD")
	var motion := InputEventMouseMotion.new()
	motion.position = tray
	motion.relative = tray - playfield
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	game._input(motion)
	_check(game.aim_position.is_equal_approx(tray), "A held pointer entering the HUD updates aim instead of retaining its previous mineable position")
	game._process(0.4)
	game.pickaxe._process(0.4)
	game._physics_process(0.0)
	game._request_swing()
	_check(game.hit_count == hits and not game.pickaxe.is_swinging and not game.impact_pending, "Held mining and direct swing requests do not repeat against the stone while the pointer is over the HUD")
	press.position = tray
	press.pressed = false
	game._input(press)
	_check(not game.mouse_down and not game.dragging, "Releasing a held mouse over the HUD clears its gameplay input state")

	# Place real geometry behind the tray, making an empty ray an insufficient
	# explanation for the direct-mine/hover guard passing.
	# The preceding manual frame changed the recoil transform; let physics
	# synchronize before comparing mesh positions with collision queries.
	await physics_frame
	await process_frame
	var remaining_target := _ordinary_target()
	_check(not remaining_target.is_empty(), "The protected-tray fixture still has a real visible stone")
	if remaining_target.is_empty():
		return
	var from_screen: Vector2 = remaining_target.screen
	game.rock_motion.global_position += game.camera.project_position(tray, 8.0) - game.camera.project_position(from_screen, 8.0)
	await physics_frame
	await process_frame
	_check(not game.ray_at(tray).is_empty(), "An unfiltered physics ray really intersects stone behind the HUD slot")
	game.aim_position = tray
	game._physics_process(0.0)
	_check(not game._mine_at(tray) and game.hit_count == hits and game.hovered == null and not game.marker.visible, "HUD protection rejects direct damage and hides stone hover even when actual geometry lies behind it")

	game._reset_rock()
	await _finish_spawn()
	target = _ordinary_target()
	_check(not target.is_empty(), "The touch fixture starts over a real stone outside the HUD")
	if target.is_empty():
		return
	playfield = target.screen
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.position = playfield
	touch.pressed = true
	game._input(touch)
	var before_touch: Quaternion = game.shell.quaternion
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = tray
	drag.relative = tray - playfield
	game._input(drag)
	game._process(0.3)
	game.pickaxe._process(0.4)
	game._physics_process(0.0)
	_check(game.aim_position.is_equal_approx(tray) and game.shell.quaternion.is_equal_approx(before_touch) and game.hit_count == hits and not game.pickaxe.is_swinging, "Dragging a held touch into the HUD updates aim without rotating the rock or repeating mining")
	touch.position = tray
	touch.pressed = false
	game._input(touch)
	_check(game.touch_id == -1 and not game.touch_rotating and not game.impact_pending, "Releasing a touch inside the HUD clears it without generating a tap impact")
	var pan := InputEventPanGesture.new()
	pan.position = tray
	pan.delta = Vector2(4.0, -3.0)
	var before_pan: Quaternion = game.shell.quaternion
	game._input(pan)
	_check(game.shell.quaternion.is_equal_approx(before_pan), "A touchpad pan positioned on the HUD does not rotate the rock")
	pan.position = playfield
	game._input(pan)
	_check(not game.shell.quaternion.is_equal_approx(before_pan), "The same pan works again in the playfield rather than being disabled globally")


func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null


func _validate_touch_buttons() -> void:
	await _new_game()
	game._start_round()
	game._physics_process(30.0)
	game._process(0.016)
	await process_frame
	var skip_button: Button = game.hud._skip
	_check(skip_button.is_visible_in_tree() and game.round_state.phase == Round.Phase.SETTLING, "The real settlement skip control is visible for viewport touch dispatch")
	await _viewport_tap(skip_button.get_global_rect().get_center())
	_check(game.round_state.phase == Round.Phase.COMPLETE and game.hud.settlement_complete, "A real screen-touch press and release activates the settlement skip button without mouse emulation")
	if game.round_state.phase != Round.Phase.COMPLETE:
		return
	var replay_button: Button = game.hud._replay
	var old_index := int(game.round_state.round_index)
	await _viewport_tap(replay_button.get_global_rect().get_center())
	_check(game.round_state.phase == Round.Phase.READY and game.round_state.round_index == old_index + 1 and not game.hud.settlement_visible, "A real screen-touch press and release activates the next-round button once")


func _viewport_tap(position: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 6
	touch.position = position
	touch.pressed = true
	root.push_input(touch, true)
	await process_frame
	touch = touch.duplicate() as InputEventScreenTouch
	touch.pressed = false
	root.push_input(touch, true)
	await process_frame
