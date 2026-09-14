extends SceneTree
const Game = preload("res://scripts/main.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()
	create_timer(45).timeout.connect(func(): quit(2))

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _run() -> void:
	root.size = Vector2i(1152,800)
	AudioServer.set_bus_mute(0,true)
	var game := Game.new()
	root.add_child(game)
	for node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.focused = true
	game.campaign.cleared = 2
	var previous_count: int = game.chunks.size()
	game._advance_ore_preparation()
	while game._ore_preparation.chunks.is_empty():
		game._advance_ore_preparation()
		await process_frame
	_check(not game._ore_preparation.chunks.is_empty(),"Idle preparation makes bounded progress after asynchronous resource loading")
	var paused_count: int = game._ore_preparation.chunks.size()
	game.focused = false
	game._advance_ore_preparation()
	_check(game._ore_preparation.chunks.size() == paused_count,"Focus loss pauses preparation")
	game.focused = true
	while not game._ore_preparation.complete:
		game._advance_ore_preparation()
		await process_frame
	var prepared: Array = game._ore_preparation.chunks.duplicate()
	_check(prepared.size() == 296 and game.chunks.size() == previous_count,"Preparing the next ore leaves the current mining world intact")
	_check(prepared.all(func(chunk):return not chunk.is_visible_in_tree() and (chunk.collision_layer & (game._ore_collision_mask|3)) == 0),"Prepared stones are invisible and excluded from live mining rays")
	_check(game.round_state.remaining == 30 and game.round_state.wallet_gold == 0,"Preparation grants no income and spends no mining time")
	game.upgrade_stats.gem_spawn_bonus = 1.0
	game._advance_ore_preparation()
	_check(not game._ore_preparation.complete,"Purchases invalidate the prepared loot snapshot")
	while not game._ore_preparation.complete:
		game._advance_ore_preparation()
		game._advance_ore_retirement()
		await process_frame
	prepared.assign(game._ore_preparation.chunks)
	game._spawn_rock()
	_check(not game.ore_building,"The production random spawn activates the sealed prepared ore immediately")
	while game.ore_building:
		game._advance_ore_build()
		await process_frame
	_check(game.chunks.size() == 296 and prepared.all(func(chunk):return game.chunks.has(chunk)),"Adoption reuses every prepared physical stone without rebuilding it")
	_check(game.gems.size() == game.ore_profile.gem_cap,"Purchases made after preparation still affect the actual hidden gem plan")
	_check(game.chunks.any(func(chunk):return chunk.layer_index > 1 and not chunk.visible),"Untouched buried layers are excluded from rendering")
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1.0
	game._start_round()
	await physics_frame
	await physics_frame
	var contacts: Array = game.auxiliary.exposed_contacts()
	for contact in contacts.slice(0,6):
		for depth in 6:
			var hit: Dictionary = game.ray_at(contact.screen)
			if hit.is_empty(): break
			var chunk = hit.collider
			if not game.chunks.has(chunk): break
			_check(chunk.visible,"Successive real mining rays always meet a rendered, exposed stone")
			game._damage_chunk(hit,contact.screen,{},chunk.health)
			await physics_frame
			await physics_frame
	# A fast clear can arrive before preparation finishes. Keep the partially
	# assembled ore and finish its hidden loot rather than starting from zero.
	while game._ore_preparation.chunks.is_empty():
		game._advance_ore_preparation()
		await process_frame
	var partial: Array = game._ore_preparation.chunks.duplicate()
	var partial_root: Node3D = game._ore_preparation.root_node
	var remaining: float = game.round_state.remaining
	_check(not game._ore_preparation.complete and partial.size() < 296,"Fast-clear fixture contains only a partly prepared next ore")
	game._spawn_rock()
	_check(game.ore_building and game._using_prepared_build and game._ore_preparation.root_node == partial_root,"Fast clearing promotes the existing preparation instead of throwing it away")
	game._advance_round(10.0)
	_check(game.round_state.remaining == remaining and not game._round_allows_mining(),"Partially prepared ore cannot consume mining time or accept early damage")
	while game.ore_building:
		game._advance_ore_build()
		game._advance_ore_retirement()
		await process_frame
	_check(game.chunks.size() == 296 and partial.all(func(chunk):return game.chunks.has(chunk)),"Fast-clear completion preserves every partially prepared stone")
	_check(game.gems.size() == game.ore_profile.gem_cap and not game._using_prepared_build,"The reused ore is fully sealed with the correct upgraded gem count")
	# Replacing a pending stage must release its unattached nodes.
	game.campaign.cleared = 3
	game._advance_ore_preparation()
	while game._ore_preparation.chunks.is_empty():
		game._advance_ore_preparation()
		await process_frame
	var retired: Array = game._ore_preparation.chunks.duplicate()
	game.campaign.cleared = 4
	game._advance_ore_preparation()
	for i in 20:
		game._advance_ore_retirement()
		await process_frame
	_check(retired.all(func(chunk):return not is_instance_valid(chunk)),"A different stage releases the obsolete prepared nodes")
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print("ORE_PREPARATION_VALIDATION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)
