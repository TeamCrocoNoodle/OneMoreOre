extends SceneTree
## Run with Godot --headless --path . --script res://tests/validate_mining.gd.
## Real raycasts verify hidden seeded gems, full excavation, and all input paths.

const Main = preload("res://scripts/main.gd")
const Gem = preload("res://scripts/gem.gd")
const TEST_SEED := 61477
const EXPECTED_CHUNKS := 322

var game: Main
var failures: Array[String] = []
var checks := 0
var impact_signal_count := 0
var impact_was_deferred := false
var hit_count_at_signal := -1
var traversed_layers: Array[int] = []
var initial_gem_count := 0
var owner_releases := 0
var fracture_spawn_checked := false


func _initialize() -> void:
	_run.call_deferred()
	create_timer(90.0).timeout.connect(func():
		push_error("MINING_TEST_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.size = Vector2i(1440, 1000)
	game = load("res://scenes/main.tscn").instantiate() as Main
	root.add_child(game)
	await _frames(4)
	await _validate_showcase()
	await _validate_seeded_layouts()
	initial_gem_count = game.gems.size()
	_check(game.chunks.size() == EXPECTED_CHUNKS, "A large fresh rock has 322 independently mineable chunks")
	_check(initial_gem_count > 1, "The rock contains multiple discoverable gems")
	_check(_count_gems(game) == initial_gem_count, "Seeded resets leave exactly the current gem population")
	var layer_counts := [0, 0, 0, 0, 0, 0]
	var all_solid := true
	for chunk in game.chunks:
		layer_counts[chunk.layer_index] += 1
		all_solid = all_solid and chunk.collision_layer == 1 and chunk.health > 0.0
	_check(not layer_counts.has(0) and all_solid, "All six layers contain solid, independently damageable stone")
	_validate_placement()
	var center := _center()
	var first_ray := game.ray_at(center)
	_check(not first_ray.is_empty(), "The screen center intersects the intact rock")
	if first_ray.is_empty():
		_finish()
		return
	var first: StaticBody3D = first_ray.collider
	_check(game.chunks.has(first) and first.layer_index == 0, "The outer shell blocks the initial central ray")
	var stone_ray := _masked_ray(center, 1)
	_check(not stone_ray.is_empty() and stone_ray.collider == first, "Stone-only physics query reaches the visible outer chunk")
	game.pickaxe.impacted.connect(_on_impact)
	var initial_health: float = first.health
	var initial_hits := game.hit_count
	_send_mouse_button(MOUSE_BUTTON_LEFT, true, center)
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, center)
	_check(game.pickaxe.is_swinging and game.hit_count == initial_hits, "Mouse press begins a swing without applying damage during input")
	_check(await _until(func(): return game.hit_count > initial_hits), "Mouse swing delivers a physics impact")
	_check(impact_signal_count > 0 and impact_was_deferred and hit_count_at_signal == initial_hits, "Pickaxe impact queues damage until the physics callback")
	_check(is_instance_valid(first) and first.health < initial_health and first.health > 0.0, "The first impact damages the outer chunk without detaching it")
	if is_instance_valid(first):
		var crack_mesh: MeshInstance3D = first.get("_crack_mesh")
		_check(crack_mesh != null and crack_mesh.mesh != null and crack_mesh.mesh.get_surface_count() > 0, "Damage creates visible crack geometry")
	await _settle_swing()

	var old_gems: Array[WeakRef] = []
	for body in game.gems:
		old_gems.append(weakref(body))
	var starting_rock := game.rock_number
	var collected_before := game.collected_count
	var steps := 0
	# Deliberately find every gem before excavating the rest of the rock.
	while not game.gems.is_empty() and steps < 150:
		var target: StaticBody3D = game.gems[0]
		if not await _break_visible(_gem_target_screen(target)):
			break
		steps += 1
	_check(game.gems.is_empty() and game.gems_collected_this_rock == initial_gem_count, "Breaking the six randomly placed owners automatically awards all six gems")
	_check(game.collected_count == collected_before + initial_gem_count, "Each owner awards its gem once without an additional gem strike")
	_check(owner_releases == initial_gem_count, "Excavation breaks exactly one fixed owner for each of the six gems")
	_check(game.chunks.size() > 0, "Finding all gems leaves unrelated stone intact")
	if not game.gems.is_empty() or game.chunks.is_empty():
		_finish()
		return
	var remaining_stone := game.chunks.size()
	await create_timer(3.1).timeout
	await _frames(2)
	_check(game.rock_number == starting_rock and game.completion_time < 0.0, "Collecting all gems cannot respawn a partially excavated rock")
	_check(game.chunks.size() == remaining_stone, "Gem collection animations do not remove remaining stone")
	var gems_freed := true
	for previous in old_gems:
		gems_freed = gems_freed and previous.get_ref() == null
	_check(gems_freed and game.collecting_gems.is_empty() and _count_gems(game) == 0, "Collected gems and their transient animation nodes are freed")

	steps = 0
	while game.chunks.size() > 1 and steps < EXPECTED_CHUNKS * 2:
		var target: StaticBody3D = game.chunks[-1]
		if not await _break_visible(game.camera.unproject_position(target.global_position)):
			break
		steps += 1
	_check(game.chunks.size() == 1 and game.completion_time < 0.0, "Even one remaining stone chunk prevents completion")
	traversed_layers.sort()
	_check(traversed_layers == [0, 1, 2, 3, 4, 5], "Full excavation reaches every one of the six rock layers")
	if game.chunks.size() != 1:
		_finish()
		return
	var last_chunk: StaticBody3D = game.chunks[0]
	_send_mouse_button(MOUSE_BUTTON_LEFT, true, game.camera.unproject_position(last_chunk.global_position))
	_check(await _until(func(): return game.completion_time >= 0.0, 5.0), "A real held mouse press breaks the final chunk and completes excavation")
	_check(game.chunks.is_empty() and game.gems.is_empty(), "Completion requires both all stone and all gems to be cleared")
	_check(game.mouse_down, "The final mining press remains held through completion")
	var hits_at_completion := game.hit_count
	var completed_rock := game.rock_number
	_check(await _until(func(): return game.rock_number > completed_rock, 5.0), "Only full excavation starts the next rock")
	await _frames(4)
	_check(game.chunks.size() == EXPECTED_CHUNKS and game.gems.size() == initial_gem_count, "Respawn restores the complete rock and a fresh gem population")
	_check(_count_gems(game) == initial_gem_count and game.collecting_gems.is_empty(), "Respawn contains no previous gem or collection nodes")
	_check(game.gems_collected_this_rock == 0 and game.collected_count == collected_before + initial_gem_count, "Respawn resets per-rock progress while retaining the lifetime count")
	_check(await _until(func(): return game.hit_count > hits_at_completion), "Holding the same mouse press automatically mines the fresh rock")
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, _center())
	await _settle_swing()
	var hits_after_release := game.hit_count
	await create_timer(0.42).timeout
	_check(game.hit_count == hits_after_release and not game.mouse_down, "Releasing the mouse after respawn stops repeated mining")
	await _validate_inputs()
	_finish()


func _validate_showcase() -> void:
	game._spawn_rock(12873, true)
	await create_timer(0.75).timeout
	await _frames(2)
	_check(game.showcase_mode and game.showcase_covers.size() == game.gems.size(), "The first-rock showcase provides one stone owner for each gem")
	_validate_placement(true)
	var preview_lights: Array[WeakRef] = []
	var preview_gems: Array[WeakRef] = []
	var tiers: Array[int] = []
	for cap in game.showcase_covers:
		var jewel: StaticBody3D = cap.contained_gem.get_ref()
		var visible := game.ray_at(_gem_target_screen(jewel))
		_check(not visible.is_empty() and visible.collider == cap, "Every showcase owner is reachable from its selected front face")
		_check(_masked_ray(game.camera.unproject_position(jewel.global_position), 2).is_empty(), "Even a gem-only ray cannot select a buried showcase gem")
		_check(cap.health == 16.0 and cap.max_health == 16.0, "Showcase owners have their high health before any hit")
		_check(not cap.light_node.visible and cap.light_node.pulse_count == 0, "Unstruck showcase owners give away no beam color")
		tiers.append(jewel.light_tier)
		preview_lights.append(weakref(cap.light_node))
		preview_gems.append(weakref(jewel))
	tiers.sort()
	_check(tiers == [0, 1, 2, 3, 4, 5], "All six final light colors are available on the first rock")
	var final_cap: StaticBody3D = game.showcase_covers[-1]
	var final_gem: StaticBody3D = final_cap.contained_gem.get_ref()
	var different_gem: StaticBody3D = game.gems[0]
	var different_transform: Transform3D = different_gem.transform
	var different_parent: Node = different_gem.get_parent()
	_check(not final_cap.contain_gem(different_gem), "A populated owner refuses a second gem")
	final_cap.configure_gem_cover(different_gem, different_gem.light_tier)
	_check(final_cap.contained_gem.get_ref() == final_gem and final_cap.cover_gem.get_ref() == final_gem and different_gem.get_parent() == different_parent and different_gem.transform == different_transform, "Rejected reassignment preserves both gems and the fixed light link")
	_check(not final_gem.release_from_chunk(game.shell, Vector3.ZERO), "A live owner cannot release its gem early")
	_check(not game._collect_gem(final_gem), "Main rejects direct collection of an embedded gem")
	await _clear_showcase_neighbors(final_cap, final_gem)
	var departing: WeakRef = weakref(final_cap.light_node)
	_check(await _break_visible(_gem_target_screen(final_gem), false), "A showcase owner breaks through the normal mining path")
	_check(final_gem.collected and final_gem.is_emerging and final_gem.visible and final_gem.collision_layer == 0 and game.gems.size() == 5, "The first showcase owner immediately awards one gem while the other five remain buried")
	_check(departing.get_ref() == null, "The broken showcase owner's light is freed with its stone without a detached final flash")
	# Reset during the awarded gem's emergence after its owner's light is gone.
	game._spawn_rock(TEST_SEED, false)
	await _frames(3)
	var all_lights_freed := true
	var all_gems_freed := true
	for previous in preview_lights:
		all_lights_freed = all_lights_freed and previous.get_ref() == null
	for previous in preview_gems:
		all_gems_freed = all_gems_freed and previous.get_ref() == null
	_check(all_lights_freed, "Reset frees the remaining owner lights from the previous rock")
	_check(all_gems_freed and _count_gems(game) == game.gems.size() and game.collecting_gems.is_empty(), "Reset during automatic collection frees its emerging gem and every old embedded gem")
	_check(game.effects.loose_chunks.is_empty() and game.effects.get("_fragment_pool").is_empty(), "Reset clears active fracture pieces and their reusable pool")
	owner_releases = 0


func _clear_showcase_neighbors(host: StaticBody3D, jewel: StaticBody3D) -> void:
	var removed := 0
	while removed < 3:
		var nearest: StaticBody3D
		var nearest_distance := INF
		var screen := Vector2.ZERO
		for candidate in game.chunks:
			if candidate.is_gem_cover or candidate.layer_index != 0:
				continue
			var candidate_screen: Vector2 = game.camera.unproject_position(candidate.mesh_instance.to_global(candidate.face_center))
			var ray := game.ray_at(candidate_screen)
			if ray.is_empty() or ray.collider != candidate:
				continue
			var distance: float = candidate.global_position.distance_to(host.global_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
				screen = candidate_screen
		if nearest == null:
			break
		var original_health: float = nearest.health
		nearest.configure_gem_cover(jewel, jewel.light_tier)
		_check(not nearest.is_gem_cover and nearest.health == original_health and not is_instance_valid(nearest.light_node), "An ordinary neighbor cannot adopt or emit light for another owner's embedded gem")
		if not await _break_visible(screen):
			break
		removed += 1
		var owners_unchanged := true
		for other in game.gems:
			var owner: StaticBody3D = other.host_chunk.get_ref() if other.host_chunk != null else null
			owners_unchanged = owners_unchanged and is_instance_valid(owner) and owner.is_gem_cover and owner.cover_gem.get_ref() == other and owner.health == 16.0 and owner.light_node.pulse_count == 0
		_check(owners_unchanged, "Mining an unrelated neighboring stone cannot promote it or trigger any gem owner's light")
		_check(jewel.is_embedded and not jewel.visible and jewel.collision_layer == 0 and jewel.get_parent() == host.mesh_instance, "Removing neighboring stone leaves the gem hidden inside its own untouched owner")
	_check(removed == 3, "Three real neighboring stones can be cleared without releasing the showcase gem")


func _validate_seeded_layouts() -> void:
	game._spawn_rock(TEST_SEED)
	await create_timer(0.75).timeout
	await _frames(2)
	var first := _layout_snapshot()
	_validate_placement()
	game._spawn_rock(TEST_SEED + 1)
	await create_timer(0.75).timeout
	await _frames(2)
	var different := _layout_snapshot()
	_check(first != different, "Different rock seeds change the six gems' owner assignments")
	_validate_placement()
	game._spawn_rock(TEST_SEED)
	await create_timer(0.75).timeout
	await _frames(2)
	_check(_layout_snapshot() == first, "Repeating a seed exactly reproduces owner assignment and fitted gem transforms")


func _layout_snapshot() -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	for body in game.gems:
		var host: StaticBody3D = body.host_chunk.get_ref()
		layout.append({"host_position": host.base_position, "layer": host.layer_index, "gem_transform": body.transform, "tier": body.light_tier})
	return layout


func _validate_placement(showcase: bool = false) -> void:
	var owners: Array[StaticBody3D] = []
	var occupied_layers: Array[int] = []
	var common_count := 0
	var special_count := 0
	var hidden := true
	var consistent_links := true
	var ordinary_health := true
	var plane_leaks := 0
	var body_leaks := 0
	var ray_count := 0
	var positions: Array[Vector3] = []
	var bounds: Array[float] = []
	var separated := true
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for i in range(24):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 24.0
		var angle := float(i) * 2.3999632297
		directions.append(Vector3(cos(angle) * sqrt(1.0 - y * y), y, sin(angle) * sqrt(1.0 - y * y)))
	for body in game.gems:
		if body.grade == Gem.COMMON:
			common_count += 1
		elif body.grade == Gem.SPECIAL:
			special_count += 1
		var owner: StaticBody3D = body.host_chunk.get_ref() if body.host_chunk != null else null
		_check(is_instance_valid(owner) and game.chunks.has(owner), "Every new gem references a living stone from this rock")
		if not is_instance_valid(owner):
			continue
		_check(not owners.has(owner), "Each gem has a distinct stone owner")
		owners.append(owner)
		occupied_layers.append(owner.layer_index)
		consistent_links = consistent_links and owner.contained_gem.get_ref() == body and owner.cover_gem.get_ref() == body and owner.is_gem_cover and owner.cover_tier == body.light_tier and body.get_parent() == owner.mesh_instance
		hidden = hidden and body.is_embedded and not body.is_emerging and not body.visible and body.collision_layer == 0 and not body.collected
		_check(owner.health == 16.0 and owner.max_health == 16.0 and not owner.light_node.visible and owner.light_node.pulse_count == 0, "A gem's fixed owner starts at 16 HP with no light leak")
		var points := _gem_visual_points(body)
		var planes: Array[Plane] = owner.get_containment_planes()
		_check(not points.is_empty() and planes.size() >= 4, "Containment is checked against actual gem vertices and the rendered owner's hull planes")
		var worst_distance := -INF
		for point in points:
			var local_point: Vector3 = owner.mesh_instance.to_local(game.shell.to_global(point))
			for plane in planes:
				worst_distance = maxf(worst_distance, plane.distance_to(local_point))
		if worst_distance > 0.0002:
			plane_leaks += 1
		_check(worst_distance <= 0.0002, "Every rotated and fitted gem vertex lies inside its own rendered stone (max plane distance %.6f)" % worst_distance)
		var fitted_scale: Vector3 = body.scale
		_check(fitted_scale.x > 0.0 and fitted_scale.x <= 1.00001 and fitted_scale.is_equal_approx(Vector3.ONE * fitted_scale.x), "Embedding uniformly fits the gem without enlarging it")
		var center: Vector3 = game.shell.to_local(body.global_position)
		var radius := 0.0
		if points.is_empty():
			continue
		var extrema: Array[Vector3] = [points[0], points[0], points[0], points[0], points[0], points[0], center]
		for point in points:
			radius = maxf(radius, point.distance_to(center))
			for axis in range(3):
				if point[axis] < extrema[axis * 2][axis]:
					extrema[axis * 2] = point
				if point[axis] > extrema[axis * 2 + 1][axis]:
					extrema[axis * 2 + 1] = point
		for i in range(positions.size()):
			separated = separated and center.distance_to(positions[i]) > radius + bounds[i]
		positions.append(center)
		bounds.append(radius)
		# Excluding every neighboring chunk proves the owning solid alone encloses
		# the gem, even after all unrelated stone has been excavated.
		var exclusions: Array[RID] = []
		for other in game.chunks:
			if other != owner:
				exclusions.append(other.get_rid())
		for direction in directions:
			var origin: Vector3 = game.shell.to_global(direction * (Main.ROCK_RADIUS + 2.0))
			for point in extrema:
				var query := PhysicsRayQueryParameters3D.create(origin, game.shell.to_global(point), 3)
				query.exclude = exclusions
				var result: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
				ray_count += 1
				if result.is_empty() or result.collider != owner:
					body_leaks += 1
	for chunk in game.chunks:
		if not owners.has(chunk):
			ordinary_health = ordinary_health and not chunk.is_gem_cover and chunk.contained_gem == null and chunk.max_health >= 2.0 and chunk.max_health <= 4.0 and not is_instance_valid(chunk.light_node)
	occupied_layers.sort()
	_check(owners.size() == 6 and consistent_links, "Six gems have six fixed, mutually consistent ownership and light links")
	_check(occupied_layers == ([0, 0, 0, 0, 0, 0] if showcase else [0, 1, 2, 3, 4, 5]), "Showcase uses six front owners; normal seeds distribute one owner through every depth")
	_check(hidden, "Embedded gems are hidden, uncollected and excluded from physics selection")
	_check(ordinary_health, "Only the six designated owners have high health or gem light nodes")
	_check(plane_leaks == 0 and separated, "Individually contained gem hulls remain separated without protruding into other chunks")
	_check(common_count == Main.COMMON_GEM_COUNT and special_count == Main.SPECIAL_GEM_COUNT, "Every seed creates five common gems and one special gem")
	_check(body_leaks == 0, "Each owner alone occludes its gem center and hull extrema in %d exterior rays (leaks=%d)" % [ray_count, body_leaks])
	if not showcase:
		_print_socket_sizes()


func _print_socket_sizes() -> void:
	var sizes: Array[String] = []
	for layer in range(Main.LAYER_COUNT):
		var radii: Array[float] = []
		for chunk in game.chunks:
			if chunk.layer_index == layer:
				radii.append(chunk.gem_socket_radius)
		radii.sort()
		sizes.append("%d:%.3f/%.3f/%.3f" % [layer, radii[0], radii[radii.size() / 2], radii[-1]])
	print("SOCKET_RADIUS layer:min/median/max ", ", ".join(sizes))


func _gem_visual_points(body: StaticBody3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var mesh: Mesh = body.facets.mesh
	for surface_index in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		for point in vertices:
			points.append(game.shell.to_local(body.facets.to_global(point)))
	return points


func _gem_target_screen(body: StaticBody3D) -> Vector2:
	if body.is_embedded and body.host_chunk != null:
		var owner: StaticBody3D = body.host_chunk.get_ref()
		if is_instance_valid(owner):
			return game.camera.unproject_position(owner.mesh_instance.to_global(owner.face_center))
	return game.camera.unproject_position(body.global_position)


func _break_visible(screen: Vector2, finish_emergence: bool = true) -> bool:
	var ray := game.ray_at(screen)
	if ray.is_empty():
		_check(false, "An excavation target must remain reachable by a physics ray")
		return false
	var body: StaticBody3D = ray.collider
	_check(game.chunks.has(body), "Mining rays reach remaining stone without requiring a separate gem target")
	if not game.chunks.has(body):
		return false
	var previous_stone := game.chunks.size()
	var previous_collected := game.collected_count
	var previous_per_rock := game.gems_collected_this_rock
	var previous_special := game.special_collected_count
	var previous_active_gems := game.gems.size()
	var hits_before := game.hit_count
	var prior_fragment_batches: Array[int] = []
	if not fracture_spawn_checked:
		for fragment in game.effects.loose_chunks:
			if not prior_fragment_batches.has(int(fragment.batch_id)):
				prior_fragment_batches.append(int(fragment.batch_id))
	var linked_gem: StaticBody3D = body.contained_gem.get_ref() as StaticBody3D if body.contained_gem != null else null
	var owner_light: WeakRef = weakref(body.light_node) if is_instance_valid(linked_gem) else null
	var original_max_health: float = body.max_health
	var embedded_before: Array[StaticBody3D] = []
	for jewel in game.gems:
		if jewel.is_embedded:
			embedded_before.append(jewel)
	var strikes := 0
	if not traversed_layers.has(body.layer_index):
		traversed_layers.append(body.layer_index)
	while strikes < 32:
		var pulses_before: int = body.light_node.pulse_count if is_instance_valid(linked_gem) else 0
		if not game._mine_at(screen):
			_check(false, "A reachable body's mining hits must be accepted")
			return false
		strikes += 1
		if is_instance_valid(linked_gem):
			_check(body.max_health == 16.0 and body.contained_gem.get_ref() == linked_gem and body.cover_gem.get_ref() == linked_gem, "Every owner strike retains its original high health and unique gem")
			if body.destroyed:
				_check(body.is_ancestor_of(body.light_node) and _light_is_cleared(body.light_node), "The fatal mining call immediately stops its crack light, clears all visual meshes, and keeps the light owned by its stone")
			else:
				_check(body.light_node.pulse_count == pulses_before + 1 and body.light_node.current_tier <= linked_gem.light_tier, "Each surviving owner strike emits one light pulse bounded by its own gem tier")
			if pulses_before == 0:
				_check(body.get_revealed_tier() == 0, "The first real strike on a pristine owner begins with white light")
			if not body.destroyed:
				_check(linked_gem.is_embedded and not linked_gem.collected and not linked_gem.visible and linked_gem.collision_layer == 0, "A surviving owner retains its hidden, uncollected gem after each impact")
		elif strikes == 1:
			_check(not body.is_gem_cover and body.contained_gem == null and body.max_health == original_max_health and not is_instance_valid(body.light_node), "An unrelated struck stone stays ordinary without promotion or gem beams")
		if body.destroyed:
			break
	_check(body.collision_layer == 0 and body.destroyed and game.chunks.size() == previous_stone - 1, "Breaking one chunk disables its collision and removes exactly that chunk")
	if not fracture_spawn_checked:
		var new_fragments := 0
		var distinct_meshes: Array[Mesh] = []
		var valid_fragments := true
		for fragment in game.effects.loose_chunks:
			if not prior_fragment_batches.has(int(fragment.batch_id)):
				new_fragments += 1
				var mesh: Mesh = fragment.node.mesh
				valid_fragments = valid_fragments and mesh != body.mesh_instance.mesh and not distinct_meshes.has(mesh) and fragment.node.has_meta("fracture_fragment")
				distinct_meshes.append(mesh)
		_check(new_fragments >= 2 and new_fragments <= 18 and valid_fragments, "A real mining impact replaces its broken stone with multiple distinct crack-shaped meshes")
		fracture_spawn_checked = true
	var newly_released: Array[StaticBody3D] = []
	for jewel in embedded_before:
		if not jewel.is_embedded:
			newly_released.append(jewel)
	if is_instance_valid(linked_gem):
		owner_releases += 1
		# These assertions run in the same call stack, before any animation frame.
		_check(newly_released == [linked_gem], "A fatal owner hit releases exactly its own gem and no neighbor's")
		_check(linked_gem.collected and game.collected_count == previous_collected + 1 and game.gems_collected_this_rock == previous_per_rock + 1 and game.gems.size() == previous_active_gems - 1 and not game.gems.has(linked_gem), "The fatal mining call awards and removes its gem before returning, without a further gem strike")
		_check(game.special_collected_count == previous_special + (1 if linked_gem.grade == Gem.SPECIAL else 0), "Immediate collection preserves the common versus special award count")
		_check(linked_gem.get_parent() == game and linked_gem.host_chunk == null and linked_gem.visible and linked_gem.is_emerging and linked_gem.collision_layer == 0 and _has_collection(linked_gem), "The awarded gem is safely reparented into its tracked visual collection with collision disabled")
		_check(not game._collect_gem(linked_gem) and game.collected_count == previous_collected + 1, "Repeated collection during emergence cannot award the gem twice")
		var remaining_hidden := true
		for other in embedded_before:
			if other != linked_gem:
				remaining_hidden = remaining_hidden and game.gems.has(other) and other.is_embedded and not other.collected and not other.visible and other.collision_layer == 0
		_check(remaining_hidden, "Automatically collecting one gem leaves every other owner's gem hidden and uncollected")
	else:
		_check(newly_released.is_empty() and game.collected_count == previous_collected, "Destroying an ordinary chunk cannot release or award any embedded gem")
	var hits_at_break := game.hit_count
	if is_instance_valid(linked_gem):
		_check(hits_at_break == hits_before + strikes, "Awarding the gem uses exactly its owner's necessary stone strikes")
	await _frames(1)
	_check(not is_instance_valid(body), "A detached chunk's physics body is freed")
	if is_instance_valid(linked_gem):
		_check(owner_light.get_ref() == null, "The broken owner's crack light is freed with the stone instead of lingering in effects")
		_check(_has_collection(linked_gem) and linked_gem.collected, "The automatically awarded gem survives its former owner's node deletion")
		if finish_emergence:
			_check(await _until(func(): return not linked_gem.is_emerging), "Immediate collection preserves the complete outward emergence animation")
			_check(linked_gem.collected and linked_gem.collision_layer == 0 and linked_gem.visible and not linked_gem.is_embedded, "The emerged reward remains nonselectable while its collection animation continues")
			_check(game.hit_count == hits_at_break and game.collected_count == previous_collected + 1, "The reward emerges and stays awarded with zero additional mining hits")
			_check(linked_gem.global_basis.z.normalized().dot(game.camera.global_basis.z.normalized()) > 0.8, "An emerging reward presents its broad front face to the orthographic camera")
	return true


func _light_is_cleared(light: Node3D) -> bool:
	if light.visible or light.is_processing() or light.current_tier != -1 or light.pulse_count != 0:
		return false
	for child in light.get_children():
		if child is MeshInstance3D:
			if child.mesh != null:
				return false
			if child.material_override is ShaderMaterial and float(child.material_override.get_shader_parameter("pulse_amount")) != 0.0:
				return false
	return true


func _has_collection(jewel: StaticBody3D) -> bool:
	for entry in game.collecting_gems:
		if entry.node == jewel:
			return true
	return false


func _validate_inputs() -> void:
	var before := game.hit_count
	var center := _center()
	_send_touch(true, center)
	_send_touch(false, center)
	_check(game.hit_count == before and game.pickaxe.is_swinging, "A touch tap queues a swing without an immediate hit")
	_check(await _until(func(): return game.hit_count > before), "Touch tap mines through the same physics path")
	await _settle_swing()
	before = game.hit_count
	_send_touch(true, _center())
	_check(await _until(func(): return game.hit_count > before), "Holding a touch automatically mines")
	_send_touch(false, _center())
	await _settle_swing()
	var released_hits := game.hit_count
	await create_timer(0.38).timeout
	_check(game.hit_count == released_hits, "Releasing touch stops automatic mining")

	before = game.hit_count
	var rotation_before := game.shell.quaternion
	center = _center()
	_send_touch(true, center)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(60, 18)
	drag.relative = Vector2(60, 18)
	_send(drag)
	_check(game.touch_rotating and game.shell.quaternion.angle_to(rotation_before) > 0.05, "A touch drag rotates the stone")
	_send_touch(false, drag.position)
	await create_timer(0.20).timeout
	_check(game.hit_count == before and not game.pickaxe.is_swinging, "A rotation drag does not accidentally mine")

	# Losing focus during a touch orbit must not leave mouse/keyboard/controller blocked.
	_send_touch(true, _center())
	_send(drag)
	_check(game.touch_rotating, "A touch orbit is active before focus loss")
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_send_touch(false, drag.position)
	_check(not game.focused and game.touch_id == -1 and not game.touch_rotating, "Focus loss clears the complete touch gesture state")
	before = game.hit_count
	_send_key(KEY_SPACE, true)
	_send_key(KEY_SPACE, false)
	await create_timer(0.20).timeout
	_check(game.hit_count == before and not game.pickaxe.is_swinging, "Unfocused input cannot begin a new mining swing")
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_send_mouse_button(MOUSE_BUTTON_LEFT, true, _center())
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, _center())
	_check(await _until(func(): return game.hit_count > before), "Mouse mining works after focus returns from an interrupted touch drag")
	await _settle_swing()

	rotation_before = game.shell.quaternion
	_send_mouse_button(MOUSE_BUTTON_RIGHT, true, center)
	var motion := InputEventMouseMotion.new()
	motion.position = center + Vector2(40, -12)
	motion.relative = Vector2(40, -12)
	_send(motion)
	_send_mouse_button(MOUSE_BUTTON_RIGHT, false, motion.position)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.05 and not game.dragging, "Mouse drag orbits and release ends dragging")
	rotation_before = game.shell.quaternion
	var pan := InputEventPanGesture.new()
	pan.position = center
	pan.delta = Vector2(2, 1)
	_send(pan)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.04, "Touchpad pan gestures orbit the stone")

	game.aim_position = _center()
	before = game.hit_count
	_send_joy_button(JOY_BUTTON_A, true)
	_send_joy_button(JOY_BUTTON_A, false)
	_check(game.using_controller and game.hit_count == before and game.pickaxe.is_swinging, "Controller face-button input queues a swing")
	_check(await _until(func(): return game.hit_count > before), "Controller button delivers a mining impact")
	await _settle_swing()
	rotation_before = game.shell.quaternion
	_send_joy_axis(JOY_AXIS_LEFT_X, 0.85)
	await create_timer(0.12).timeout
	_send_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.04, "Controller left stick orbits the stone")
	var aim_before := game.aim_position
	_send_joy_axis(JOY_AXIS_RIGHT_X, 0.85)
	await create_timer(0.12).timeout
	_send_joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check(game.aim_position.x > aim_before.x + 8.0, "Controller right stick moves the mining aim")
	game.aim_position = _center()
	before = game.hit_count
	_send_key(KEY_SPACE, true)
	_send_key(KEY_SPACE, false)
	_check(await _until(func(): return game.hit_count > before), "Keyboard space delivers a mining impact")
	await _settle_swing()
	rotation_before = game.shell.quaternion
	_send_key(KEY_A, true)
	await create_timer(0.12).timeout
	_send_key(KEY_A, false)
	_check(game.shell.quaternion.angle_to(rotation_before) > 0.04, "Keyboard direction input orbits the stone")


func _on_impact() -> void:
	impact_signal_count += 1
	impact_was_deferred = game.impact_pending
	hit_count_at_signal = game.hit_count


func _center() -> Vector2:
	return game.camera.unproject_position(Vector3.ZERO)


func _masked_ray(screen: Vector2, mask: int) -> Dictionary:
	var origin := game.camera.project_ray_origin(screen)
	var direction := game.camera.project_ray_normal(screen)
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * 40.0, mask))


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _until(predicate: Callable, timeout_seconds: float = 1.5) -> bool:
	var started := Time.get_ticks_msec()
	while not predicate.call():
		if Time.get_ticks_msec() - started > timeout_seconds * 1000.0:
			return false
		await _frames(1)
	return true


func _settle_swing() -> void:
	await _until(func(): return not game.pickaxe.is_swinging and game.swing_cooldown <= 0.0)
	await _frames(2)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _send_mouse_button(button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	_send(event)


func _send_touch(pressed: bool, position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	_send(event)


func _send_joy_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	_send(event)


func _send_joy_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	_send(event)


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	_send(event)


func _count_gems(node: Node) -> int:
	var count := 1 if node.get_script() == Gem else 0
	for child in node.get_children():
		count += _count_gems(child)
	return count


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("MINING_CHECK_FAILED: " + description)


func _finish() -> void:
	print("MINING_INTEGRATION checks=%d failures=%d hits=%d gems=%d rocks=%d" % [checks, failures.size(), game.hit_count, game.collected_count, game.rock_number])
	_cleanup_and_quit.call_deferred(0 if failures.is_empty() else 1)


func _cleanup_and_quit(exit_code: int) -> void:
	# Let the last audio mix and queued node deletion finish before process exit.
	# Immediate quit can retain the final WAV/playback pair in the audio thread.
	for voice in game.audio.get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
			voice.stream = null
	game.queue_free()
	await _frames(8)
	game = null
	quit(exit_code)
