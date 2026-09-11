extends SceneTree
## Graph rules, real confirmation controls, and upgrade effects in Main.
const Skills = preload("res://scripts/skill_tree.gd")
const RoundModel = preload("res://scripts/mining_round.gd")
const Gem = preload("res://scripts/gem.gd")
const Pickaxe = preload("res://scripts/pickaxe.gd")
const COSTS := {"vitality": 20, "recovery": 35, "power": 25, "speed": 40, "reach": 55, "appraisal": 30, "rich_ore": 40, "soft_ore": 50}
const PURCHASE_ORDER := ["vitality", "recovery", "power", "speed", "reach", "appraisal", "rich_ore", "soft_ore"]
const FULL_STATS := {"duration": 35.0, "recovery_per_gem": 1.0, "damage": 2.0, "attack_speed": 1.2, "attack_radius": 0.65, "gem_value_multiplier": 1.2, "extra_common_gems": 1, "stone_health_reduction": 1}

class TestGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var checks := 0
var failures: Array[String] = []
var game: Node3D
var ended := false

func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
		if not ended:
			push_error("SKILL_VALIDATION_TIMEOUT")
			quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	_validate_graph()
	_validate_round_effects()
	if not "--model-only" in OS.get_cmdline_user_args():
		await _validate_ui()
		await _validate_gameplay()
		await _validate_close_navigation()
	if is_instance_valid(game):
		_stop_audio(game)
		game.queue_free()
	await process_frame
	var deadline := Time.get_ticks_usec() + 40000
	while Time.get_ticks_usec() < deadline:
		await process_frame
	ended = true
	print("SKILL_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _validate_graph() -> void:
	var model := Skills.new()
	var nodes: Array[Dictionary] = model.get_nodes()
	var edges: Array = model.get_edges()
	var ids: Array[String] = []
	var cells: Array[Vector2i] = []
	for node in nodes:
		_check(not ids.has(node.id) and not cells.has(node.grid), "Each skill has a unique identity and grid position")
		ids.append(node.id)
		cells.append(node.grid)
		if node.id != "origin":
			_check(COSTS.get(node.id, -1) == node.cost, "The eight actual upgrades retain their specified purchase prices")
	_check(nodes.size() == 9 and model.is_unlocked("origin"), "A new nine-node graph begins with exactly its origin owned")
	var initial: Array[String] = []
	for id in ids:
		if model.is_visible(id):
			initial.append(id)
	initial.sort()
	_check(initial == ["appraisal", "origin", "power", "rich_ore", "vitality"], "Only the origin and its four immediate neighbors are initially revealed")
	var unique_edges := {}
	for edge: Array in edges:
		var sorted_edge: Array = edge.duplicate()
		sorted_edge.sort()
		var key := str(sorted_edge)
		_check(edge.size() == 2 and ids.has(edge[0]) and ids.has(edge[1]) and edge[0] != edge[1] and not unique_edges.has(key), "Graph edges join two real distinct nodes without duplicate undirected links")
		unique_edges[key] = true
	var hidden := model.purchase("speed", 1000)
	_check(not hidden.ok and hidden.gold == 1000 and hidden.reason == "hidden" and not model.is_unlocked("speed"), "Money alone cannot buy a node beyond the revealed frontier")
	var poor := model.purchase("power", 24)
	_check(not poor.ok and poor.gold == 24 and poor.reason == "insufficient_gold", "An unaffordable purchase leaves both ownership and wallet untouched")
	_check(not model.can_purchase("unknown", 999) and not model.purchase("unknown", 999).ok, "Unknown IDs cannot enter the owned graph")
	_check(not model.can_purchase("origin", 999), "The starting node cannot be purchased again")
	var gold := 1000
	for id: String in PURCHASE_ORDER:
		var before := gold
		_check(model.can_purchase(id, gold), "A connected purchase becomes available through an owned neighbor")
		var result := model.purchase(id, gold)
		gold = int(result.gold)
		_check(result.ok and gold == before - int(COSTS[id]) and model.is_unlocked(id), "A purchase spends exactly its cost and unlocks exactly once")
		var duplicate := model.purchase(id, gold)
		_check(not duplicate.ok and duplicate.gold == gold and duplicate.reason == "already_unlocked", "Repeated confirmation cannot purchase the same upgrade twice")
		for candidate: String in ids:
			var expected: bool = model.is_unlocked(candidate)
			for edge: Array in edges:
				expected = expected or (edge[0] == candidate and model.is_unlocked(edge[1])) or (edge[1] == candidate and model.is_unlocked(edge[0]))
			_check(model.is_visible(candidate) == expected, "Visibility follows owned-neighbor graph adjacency after each purchase")
	_check(gold == 705 and model.stats() == FULL_STATS, "All eight purchases cost 295 gold and yield the specified eight gameplay effects")
	_check(Skills.new().stats().damage == 1.0 and not Skills.new().is_unlocked("power"), "Independent playthroughs do not share purchased skills")

func _validate_round_effects() -> void:
	var state := RoundModel.new()
	state.apply_stats(FULL_STATS)
	_check(state.duration == 35.0 and state.remaining == 35.0, "Vitality configures the actual round duration and its ready timer")
	state.start()
	state.advance(8.0)
	_check(state.recover(1.0) == 1.0 and state.remaining == 28.0, "Recovery restores one real second while mining")
	_check(state.recover(100.0) == 7.0 and state.remaining == 35.0, "Recovery is capped by the upgraded maximum time")
	_check(state.recover(-1.0) == 0.0 and state.recover(NAN) == 0.0, "Invalid recovery cannot corrupt the deadline")
	state.apply_stats({"duration": 90.0, "gem_value_multiplier": 9.0})
	_check(state.duration == 35.0 and state.gem_value_multiplier == 1.2, "Stats cannot change the live round or its cargo valuation mid-run")
	for i in 3:
		state.record_stone()
	for tier in 6:
		state.record_gem(tier)
	state.advance(35.0)
	_check(state.recover(1.0) == 0.0 and state.remaining == 0.0, "A gem cannot revive an already expired round")
	var receipt := state.begin_settlement()
	var rates := [1, 12, 60, 240, 1200, 6000, 30000]
	var rows: Array = receipt.rows
	for i in rows.size():
		_check(int(rows[i].unit_gold) == rates[i], "Appraisal raises each real gem sale price while stone remains one gold")
	_check(receipt.total == 37515 and state.commit_settlement() and state.wallet_gold == 37515, "The upgraded sale receipt commits its exact independent price sum")
	_check(state.new_round() and state.remaining == 35.0, "The next round retains the purchased maximum duration")

func _validate_ui() -> void:
	await _new_game()
	game.round_state.wallet_gold = 100
	game.aim_position = Vector2(160, 400)
	_check(game.ray_at(game.aim_position).is_empty(), "The pending-input fixture prepares an empty-air swing without starting a mining round")
	game._request_swing()
	game.impact_pending = true
	var shortcut := InputEventKey.new()
	shortcut.physical_keycode = KEY_U
	shortcut.pressed = true
	game._input(shortcut)
	await process_frame
	var ui: Node = game.skill_ui
	_check(ui.is_open and game.round_state.phase == RoundModel.Phase.READY, "The real upgrade entry opens between rounds without starting the timer")
	_check(not game.pickaxe.is_swinging and not game.impact_pending and game.pending_rock_number == -1, "Opening the tree cancels a prepared swing and all pending mining input")
	var controller := InputEventJoypadButton.new()
	controller.button_index = JOY_BUTTON_Y
	controller.pressed = true
	game._input(controller)
	_check(not ui.is_open, "Controller Y closes the same real upgrade window")
	game._input(controller)
	_check(ui.is_open, "Controller Y can reopen the between-round upgrade window")
	var initial_gold: int = game.round_state.wallet_gold
	var power: Vector2 = ui.get_node_screen("power")
	await _hover(power)
	_check(ui.hovered_id == "power" and ui.selected_id.is_empty() and ui.get_confirmation_rect().size == Vector2.ZERO, "Hover reveals information without selecting or spending gold")
	await _click(power)
	_check(ui.selected_id == "power" and ui.get_confirmation_rect().size.x > 0.0 and game.round_state.wallet_gold == initial_gold and not game.upgrades.is_unlocked("power"), "Clicking an affordable node opens confirmation without purchasing it")
	await _click(ui.get_node_screen("vitality"))
	_check(ui.selected_id.is_empty() and game.round_state.wallet_gold == initial_gold, "Clicking elsewhere cancels the pending purchase instead of spending")
	await _click(power)
	await _click(ui.get_confirmation_rect().get_center())
	_check(game.upgrades.is_unlocked("power") and game.round_state.wallet_gold == 75, "Only the real confirmation Button spends gold through Main")
	_check(game.upgrades.is_visible("speed") and not game.upgrades.is_unlocked("speed"), "Buying power reveals its adjacent speed node without granting it")
	game._purchase_upgrade("power")
	_check(game.round_state.wallet_gold == 75, "Repeated Main purchase requests cannot charge an owned node")
	game.round_state.wallet_gold = 0
	ui.refresh(0)
	await _click(ui.get_node_screen("vitality"))
	if ui.get_confirmation_rect().size.x > 0.0:
		await _click(ui.get_confirmation_rect().get_center())
	_check(not game.upgrades.is_unlocked("vitality") and game.round_state.wallet_gold == 0, "Unaffordable confirmation cannot change actual ownership or make gold negative")
	ui.close_tree()
	game._start_round()
	game.round_state.wallet_gold = 1000
	game._open_upgrades()
	game._purchase_upgrade("vitality")
	_check(not ui.is_open and not game.upgrades.is_unlocked("vitality") and game.round_state.wallet_gold == 1000 and game.round_state.phase == RoundModel.Phase.MINING, "The tree and purchases stay unavailable during active mining even with sufficient gold")
	await _new_game()
	game.round_state.wallet_gold = 1000
	game._open_upgrades()
	await process_frame
	ui = game.skill_ui
	var concealed: Vector2 = ui.get_node_screen("speed")
	if not concealed.is_finite():
		concealed = ui.get_node_screen("origin") + (ui.get_node_screen("power") + ui.get_node_screen("appraisal") - ui.get_node_screen("origin") * 2.0)
	await _hover(concealed)
	await _click(concealed)
	_check(ui.selected_id.is_empty() and ui.hovered_id != "speed" and game.round_state.wallet_gold == 1000 and not game.upgrades.is_unlocked("speed"), "A hidden grid node has no interactive hit target even with sufficient gold")
	ui.close_tree()

func _validate_gameplay() -> void:
	await _new_game()
	var baseline_health: Array[float] = []
	var baseline_covers: Array[bool] = []
	for chunk in game.chunks:
		baseline_health.append(chunk.max_health)
		baseline_covers.append(chunk.is_gem_cover)
	game.round_state.wallet_gold = 1000
	game._open_upgrades()
	for id: String in PURCHASE_ORDER:
		game._purchase_upgrade(id)
	game.skill_ui.close_tree()
	_check(game.upgrades.stats() == FULL_STATS and game.round_state.wallet_gold == 705, "Main applies the complete purchased model without free upgrades")
	_check(game.round_state.duration == 35.0 and game.round_state.remaining == 35.0 and is_equal_approx(game.pickaxe.speed_multiplier, 1.2), "Main applies purchased duration and animation speed to the live round and pickaxe")
	game._spawn_rock(12873, false)
	await _finish_spawn()
	var counts := [0, 0, 0, 0, 0, 0]
	var health_correct: bool = game.chunks.size() == baseline_health.size()
	for i in game.chunks.size():
		var chunk: StaticBody3D = game.chunks[i]
		if not chunk.is_gem_cover:
			# Rich ore may select a different host; compare ordinary geometry
			# only where both otherwise-identical seeded ores have normal stone.
			if not baseline_covers[i]:
				health_correct = health_correct and is_equal_approx(chunk.max_health, maxf(1.0, baseline_health[i] - 1.0))
		else:
			health_correct = health_correct and chunk.max_health >= 16.0
	for jewel in game.gems:
		counts[jewel.grade] += 1
		_check(jewel.is_embedded and not jewel.visible and jewel.host_chunk.get_ref().is_gem_cover, "Extra ore gems remain actually buried in owning chunks")
	_check(counts == [4, 1, 0, 0, 0, 0], "Rich ore adds one ordinary gem to the next real random starter")
	_check(health_correct, "Soft ore reduces actual ordinary stone health by one with a floor of one, preserving gem covers")
	await _validate_damage_and_reach()
	await _validate_collection_recovery()

func _validate_damage_and_reach() -> void:
	# Search a real surface seam, then validate actual damage independently of
	# the selector's returned count. Healthy fixture bodies prevent early breaks.
	for chunk in game.chunks:
		chunk.health = 20.0
		chunk.max_health = 20.0
	var target := Vector2.INF
	var primary: Dictionary = {}
	var surrounding: Array[Dictionary] = []
	for chunk in game.chunks:
		if chunk.layer_index != 0:
			continue
		for corner: Vector3 in chunk.face_points:
			var local: Vector3 = chunk.face_center.lerp(corner, 0.88)
			var screen: Vector2 = game.camera.unproject_position(chunk.mesh_instance.to_global(local))
			var ray: Dictionary = game.ray_at(screen)
			if ray.is_empty() or ray.collider != chunk or game.hud.is_pointer_blocked(screen):
				continue
			var candidates: Array[Dictionary] = game._area_targets(screen, ray)
			if candidates.size() == 2 and candidates.all(func(entry: Dictionary): return not entry.hit.collider.is_gem_cover):
				target = screen
				primary = ray
				surrounding = candidates
				break
		if target.is_finite():
			break
	_check(target.is_finite() and surrounding.size() == 2, "A real starter surface seam can use both extra reach contacts")
	if not target.is_finite():
		return
	var selected: Array[StaticBody3D] = [primary.collider]
	for contact in surrounding:
		var independent_ray: Dictionary = game.ray_at(contact.screen)
		_check(not selected.has(contact.hit.collider) and independent_ray.get("collider") == contact.hit.collider and Vector3(contact.hit.position).distance_to(primary.position) <= 0.65001, "Each extra contact is a distinct first visible ray hit within the physical reach radius")
		selected.append(contact.hit.collider)
	game.focused = true
	_check(game._mine_at(target), "The upgraded swing mines a real surface seam")
	var affected := 0
	for chunk in game.chunks:
		if chunk.health != 20.0:
			affected += 1
		_check(is_equal_approx(chunk.health, 18.0 if selected.has(chunk) else 20.0), "Power deals exactly two damage to each selected surface stone and leaves every unselected layer unchanged")
	_check(affected == 3, "Reach adds exactly two contacts to the primary hit without recursive area damage")
	# Save the hidden backing hit before the front fragments are removed. All
	# targets are pre-resolved, so this same swing must not damage it afterward.
	var query := PhysicsRayQueryParameters3D.create(game.camera.project_ray_origin(target), game.camera.project_ray_origin(target) + game.camera.project_ray_normal(target) * 40.0, 3)
	var excluded: Array[RID] = []
	for chunk in selected:
		excluded.append(chunk.get_rid())
		chunk.health = 1.0
	query.exclude = excluded
	var backing: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	var backing_body: StaticBody3D = backing.get("collider") as StaticBody3D
	var backing_health: float = backing_body.health if is_instance_valid(backing_body) else -1.0
	_check(game._mine_at(target), "A wide fatal strike still resolves its visible contacts before breaking them")
	_check(not is_instance_valid(backing_body) or backing_body.health == backing_health, "Destroying the front contacts does not drill the same attack into the newly exposed backing layer")
	await physics_frame
	# Cooldown and animation must both accelerate, keeping one impact per swing.
	game.aim_position = target
	game.swing_cooldown = 0.0
	game._wait_for_mine_release = false
	game._request_swing()
	_check(game.pickaxe.is_swinging and is_equal_approx(game.swing_cooldown, 0.25), "The purchased speed changes Main's real attack interval from .30 to .25 seconds")
	if game.pickaxe.is_swinging:
		game.pickaxe._process(Pickaxe.SWING_DURATION / 1.2 + 0.001)
		_check(not game.pickaxe.is_swinging, "The real pickaxe animation completes in the accelerated duration")
	game.impact_pending = false

func _validate_collection_recovery() -> void:
	var jewel: StaticBody3D = game.gems[0]
	var owner: StaticBody3D = jewel.host_chunk.get_ref()
	for chunk in game.chunks:
		chunk.collision_layer = 1 if chunk == owner else 0
	game.shell.quaternion = Quaternion(owner.direction, game.camera.global_basis.z.normalized())
	await physics_frame
	game.focused = true
	game._start_round()
	game._advance_round(maxf(game.round_state.remaining - 10.0, 0.0))
	var before: float = game.round_state.remaining
	owner.health = 1.0
	var screen: Vector2 = game.camera.unproject_position(owner.mesh_instance.to_global(owner.face_center))
	_check(game.ray_at(screen).get("collider") == owner and game._mine_at(screen), "The recovery fixture destroys an actual gem-owning stone through Main physics")
	_check(jewel.collected and game.round_state.remaining == before + 1.0 and game.round_state.gem_counts[jewel.grade] == 1, "Real gem discovery immediately restores one second and records one gem")
	game._collect_gem(jewel)
	_check(game.round_state.remaining == before + 1.0 and game.round_state.gem_counts[jewel.grade] == 1, "Repeated collection cannot repeatedly recover time or duplicate cargo")

func _validate_close_navigation() -> void:
	await _new_game()
	game.using_controller = true
	var original_rotation: Quaternion = game.shell.quaternion
	var original_aim: Vector2 = game.aim_position
	Input.action_press("orbit_right")
	Input.action_press("aim_right")
	game._open_upgrades()
	game._process(0.016)
	game.skill_ui.close_tree()
	game._process(0.016)
	_check(game.shell.quaternion.is_equal_approx(original_rotation) and game.aim_position.is_equal_approx(original_aim), "Held navigation used around the tree does not move the rock or aim when it closes")
	Input.action_release("orbit_right")
	game._process(0.016)
	_check(game.aim_position.is_equal_approx(original_aim), "Releasing only one held navigation stick does not prematurely resume the other")
	Input.action_release("aim_right")
	game._process(0.016)
	Input.action_press("orbit_right")
	Input.action_press("aim_right")
	game._process(0.016)
	_check(not game.shell.quaternion.is_equal_approx(original_rotation) and not game.aim_position.is_equal_approx(original_aim), "Fresh navigation works again after both sticks return to neutral")
	Input.action_release("orbit_right")
	Input.action_release("aim_right")
	game.round_state.wallet_gold = 100
	game._open_upgrades()
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	var chosen: String = game.skill_ui._focused_id
	_check(chosen != "origin" and game.upgrades.can_purchase(chosen, 100), "Actual controller D-pad navigation focuses a purchasable adjacent skill")
	await _joy(JOY_BUTTON_A)
	_check(game.skill_ui.selected_id == chosen and game.round_state.wallet_gold == 100, "Actual controller A selects the skill without spending")
	await _joy(JOY_BUTTON_B)
	_check(game.skill_ui.selected_id.is_empty() and game.skill_ui.is_open, "Actual controller B cancels the selection before closing the tree")
	await _joy(JOY_BUTTON_A)
	await _joy(JOY_BUTTON_A)
	_check(game.upgrades.is_unlocked(chosen) and game.round_state.wallet_gold == 100 - int(COSTS[chosen]), "A second actual controller A confirms exactly one purchase")
	await _joy(JOY_BUTTON_B)
	_check(not game.skill_ui.is_open, "Actual controller B closes an unselected skill tree")
	for keyboard in [false, true]:
		game._start_round()
		game._advance_round(game.round_state.remaining)
		game._process(0.0)
		game.hud.finish_settlement()
		game._process(0.0)
		_check(game.round_state.phase == RoundModel.Phase.COMPLETE, "The shortcut fixture finishes a real empty round before opening upgrades")
		game._open_upgrades()
		game.skill_ui.close_tree()
		await process_frame
		_check(root.gui_get_focus_owner() == game.hud._replay, "Closing upgrades from a completed round restores the real replay Button's focus")
		var before_index: int = game.round_state.round_index
		var accept: InputEvent
		if keyboard:
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER
			key.physical_keycode = KEY_ENTER
			key.pressed = true
			accept = key
		else:
			var button := InputEventJoypadButton.new()
			button.device = 3
			button.button_index = JOY_BUTTON_A
			button.pressed = true
			accept = button
		_check(accept.is_action_pressed("ui_accept"), "The actual Enter/A event is mapped to the project's UI accept action: %s" % str(InputMap.action_get_events("ui_accept")))
		root.push_input(accept, true)
		await process_frame
		accept = accept.duplicate()
		accept.pressed = false
		root.push_input(accept, true)
		await process_frame
		_check(game.round_state.phase == RoundModel.Phase.READY and game.round_state.round_index == before_index + 1, "Actual %s activates replay after returning from upgrades (phase=%d round=%d expected=%d)" % ["Enter" if keyboard else "controller A", game.round_state.phase, game.round_state.round_index, before_index + 1])
		await _finish_spawn()
	# Reproduce the two narrow-layout faults found in actual rendered captures.
	game.round_state.wallet_gold = 1000
	game._open_upgrades()
	for id: String in ["vitality", "power", "appraisal", "rich_ore"]:
		if not game.upgrades.is_unlocked(id):
			game._purchase_upgrade(id)
	await _finish_spawn()
	root.size = Vector2i(360, 800)
	await process_frame
	await _click(game.skill_ui.get_node_screen("reach"))
	var check_rect: Rect2 = game.skill_ui.get_confirmation_rect()
	var separate := check_rect.size.x > 0.0
	for id: String in game.skill_ui.get_visible_node_ids():
		if id != "reach":
			separate = separate and not check_rect.intersects(game.skill_ui._buttons[id].get_global_rect())
	_check(separate, "At 360x800 the actual reach confirmation does not cover another visible node's native Button")
	game.skill_ui.close_tree()
	game._start_round()
	game._advance_round(game.round_state.remaining)
	game._process(0.0)
	game.hud.finish_settlement()
	game._process(0.0)
	game.hud._process(0.0)
	_check(game.hud._upgrades.visible and not game.hud._upgrades.get_global_rect().intersects(game.hud._replay.get_global_rect()), "At 360x800 the completed round exposes upgrades separately from the replay Button")
	root.size = Vector2i(1152, 800)
	await process_frame

func _new_game() -> void:
	if is_instance_valid(game):
		_stop_audio(game)
		game.queue_free()
		await process_frame
	game = TestGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
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

func _hover(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame

func _click(point: Vector2) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.position = point
	button.pressed = true
	root.push_input(button, true)
	await process_frame
	button = button.duplicate()
	button.pressed = false
	root.push_input(button, true)
	await process_frame

func _joy(button_index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 3
	event.button_index = button_index
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SKILL_CHECK_FAILED: " + message)
