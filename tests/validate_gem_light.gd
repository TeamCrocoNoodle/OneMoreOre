extends SceneTree
## Focused cover/light lifecycle checks, independent of a particular gem layout.

const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const Gem = preload("res://scripts/gem.gd")
const Light = preload("res://scripts/gem_light.gd")

var fixture := Node3D.new()
var checks := 0
var failures: Array[String] = []
var shape_data: Dictionary


func _initialize() -> void:
	_run.call_deferred()
	create_timer(20.0).timeout.connect(func():
		push_error("GEM_LIGHT_TEST_TIMEOUT")
		quit(2)
	)


func _run() -> void:
	root.add_child(fixture)
	shape_data = Geometry.build_layer(2.6, 0, 4821)[0]
	var ordinary := _make_chunk()
	_check(ordinary.max_health >= 2.0 and ordinary.max_health <= 4.0, "Ordinary stone retains its short 2-4 hit lifetime")
	ordinary.hit(1.0, ordinary.to_global(ordinary.face_center))
	_check(not ordinary.is_gem_cover and not is_instance_valid(ordinary.light_node), "Striking ordinary stone does not create gem light")
	var previously_taken := ordinary.max_health - ordinary.health
	var newly_found := _make_gem(5)
	ordinary.configure_gem_cover(newly_found, 5)
	_check(ordinary.max_health == 16.0 and ordinary.health == 16.0 - previously_taken, "Discovering a cover preserves the damage previously dealt to that stone")
	ordinary.hit(1.0, ordinary.to_global(ordinary.face_center))
	_check(ordinary.get_revealed_tier() == 0 and ordinary.health == 15.0 - previously_taken, "A previously damaged cover still begins its light sequence with white")

	for tier in range(6):
		var jewel := _make_gem(tier)
		_check(jewel.light_tier == tier, "The six gem types expose the expected light tiers")
		var cover := _make_chunk()
		cover.configure_gem_cover(jewel, tier)
		var light := cover.light_node
		_check(cover.max_health == 16.0 and cover.health == 16.0 and cover.is_gem_cover, "A gem's stone cover starts with 16 HP")
		_check(cover.cover_gem.get_ref() == jewel and cover.cover_tier == tier, "The cover is linked to its actual gem and terminal tier")
		_check(cover.get_revealed_tier() == -1 and light.current_tier == -1 and light.pulse_count == 0 and not light.visible, "An unstruck cover exposes no colored light")
		var observed: Array[int] = []
		var previous_tier := -1
		for strike in range(1, 17):
			var broken := cover.hit(1.0, cover.to_global(cover.face_center))
			var current := cover.get_revealed_tier()
			_check(current >= 0 and current <= tier, "A cover never reveals a color above its gem's tier")
			_check(current >= previous_tier and current <= previous_tier + 1, "Unit damage advances color in order without skipping a tier")
			_check(light.current_tier == current and light.pulse_count == strike, "Every cover hit produces exactly one pulse at the revealed tier")
			if current != previous_tier:
				observed.append(current)
			previous_tier = current
			if strike == 1:
				_check(current == 0 and cover.health == 15.0 and not broken, "The first cover hit is white and removes one of 16 HP")
				_check(_is_color_tier(_light_color(light), 0), "The first beam's rendered material is white")
				var remaining := cover.health
				cover.configure_gem_cover(jewel, tier)
				_check(cover.health == remaining and light.pulse_count == 1, "Repeated cover designation cannot heal or restart its progression")
				_check(_materials_use_depth_test(light), "Beam, fissure, and mote materials retain scene depth testing")
			if strike == 15:
				_check(current == tier and _is_color_tier(_light_color(light), tier), "Every gem's final color becomes visible before the cover breaks")
			_check(broken == (strike == 16), "A 16 HP cover survives precisely 15 unit strikes")
		var expected: Array[int] = []
		for value in range(tier + 1):
			expected.append(value)
		_check(observed == expected, "A cover reveals exactly the complete color prefix ending at its gem tier")
		_check(cover.destroyed and cover.collision_layer == 0 and not cover.visible, "A destroyed cover stops hiding the gem")
	_validate_spatial_damage()

	var collectible := _make_gem(5)
	var neighboring_cover := _make_chunk()
	neighboring_cover.configure_gem_cover(collectible, 5)
	neighboring_cover.hit(1.0, neighboring_cover.to_global(neighboring_cover.face_center))
	_check(collectible.begin_collection(), "The linked gem can enter collection once")
	await _frames(2)
	_check(not neighboring_cover.is_gem_cover and neighboring_cover.cover_gem == null and not neighboring_cover.light_node.visible, "Collecting a gem clears surviving cover links and their light")
	var pulses_after_collection: int = neighboring_cover.light_node.pulse_count
	neighboring_cover.hit(1.0, neighboring_cover.to_global(neighboring_cover.face_center))
	_check(neighboring_cover.light_node.pulse_count == pulses_after_collection, "An already collected gem cannot cause further cover pulses")

	var disappearing := _make_gem(2)
	var orphan_cover := _make_chunk()
	orphan_cover.configure_gem_cover(disappearing, 2)
	orphan_cover.hit(1.0, orphan_cover.to_global(orphan_cover.face_center))
	disappearing.queue_free()
	await _frames(3)
	_check(not orphan_cover.is_gem_cover and orphan_cover.cover_gem == null and not orphan_cover.light_node.visible, "Freeing a gem safely clears its weak cover association")
	var prior_light: WeakRef = weakref(orphan_cover.light_node)
	fixture.queue_free()
	await _frames(3)
	_check(prior_light.get_ref() == null, "Removing cover fixtures frees all owned beam geometry")
	print("GEM_LIGHT_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_chunk() -> Chunk:
	var chunk := Chunk.new()
	fixture.add_child(chunk)
	chunk.configure(shape_data, 0)
	return chunk


func _make_gem(tier: int) -> Gem:
	var jewel := Gem.new()
	jewel.configure(Gem.SPECIAL if tier == 5 else Gem.COMMON, tier)
	fixture.add_child(jewel)
	return jewel


func _validate_spatial_damage() -> void:
	var normal := _make_chunk()
	var point_a: Vector3 = normal.face_center.lerp(normal.face_points[0], 0.50)
	var point_b: Vector3 = normal.face_center.lerp(normal.face_points[floori(normal.face_points.size() * 0.5)], 0.50)
	var point_c: Vector3 = normal.face_center.lerp(normal.face_points[floori(normal.face_points.size() * 0.25)], 0.48)
	_check(point_a.distance_to(point_b) > 0.2, "The spatial fixture uses clearly separated off-center strikes")
	normal.hit(0.25, normal.mesh_instance.to_global(point_a))
	var first: Array[Dictionary] = normal.get_visible_crack_segments().duplicate(true)
	_check(normal.impact_count == 1 and normal.latest_impact_local.distance_to(point_a) < 0.001, "An ordinary stone records its first actual off-center impact")
	_check(_crack_distance(point_a, first) < 0.001, "Visible ordinary-stone cracks begin at the actual first strike")
	normal.hit(0.25, normal.mesh_instance.to_global(point_b))
	var second: Array[Dictionary] = normal.get_visible_crack_segments().duplicate(true)
	_check(normal.impact_count == 2 and normal.latest_impact_local.distance_to(point_b) < 0.001, "A second ordinary-stone hit moves the latest crack origin")
	_check(_crack_distance(point_b, second) < 0.001 and _old_cracks_remain(first, second), "A distant ordinary hit adds damage at its own point and preserves earlier cracks")
	normal.hit(normal.health, normal.mesh_instance.to_global(point_c))
	var fatal_normal := normal.get_visible_crack_segments()
	_check(normal.destroyed and normal.impact_count == 3 and normal.latest_impact_local.distance_to(point_c) < 0.001, "The fatal ordinary-stone hit still records its actual impact")
	_check(_crack_distance(point_c, fatal_normal) < 0.001 and _old_cracks_remain(second, fatal_normal), "Fatal ordinary damage updates geometry without erasing earlier cracks")

	var promoted := _make_chunk()
	promoted.hit(0.25, promoted.mesh_instance.to_global(point_a))
	var before_promotion: Array[Dictionary] = promoted.get_visible_crack_segments().duplicate(true)
	promoted.configure_gem_cover(_make_gem(5), 5)
	_check(_old_cracks_remain(before_promotion, promoted.get_visible_crack_segments()), "Promoting a damaged stone to gem cover preserves its visible crack history")
	promoted.hit(0.25, promoted.mesh_instance.to_global(point_b))
	_check(_old_cracks_remain(before_promotion, promoted.get_visible_crack_segments()), "The first cover pulse retains cracks made before the gem was discovered")
	_check(_light_matches_cracks(promoted), "A promoted cover's light uses its existing and new visible cracks")

	var transformed := Node3D.new()
	fixture.add_child(transformed)
	transformed.position = Vector3(4.0, -1.5, 3.0)
	transformed.rotation = Vector3(0.43, -0.71, 0.26)
	transformed.scale = Vector3(1.16, 0.91, 1.07)
	var cover := _make_chunk()
	cover.reparent(transformed, false)
	cover.rotation = Vector3(-0.22, 0.31, 0.14)
	cover.configure_gem_cover(_make_gem(5), 5)
	cover.mesh_instance.position = -cover.direction * 0.055
	cover.hit(0.2, cover.mesh_instance.to_global(point_a))
	var before_move: Array[Dictionary] = cover.get_visible_crack_segments().duplicate(true)
	var rays_before: Array[Dictionary] = cover.light_node.get("_rays").duplicate(true)
	_check(cover.latest_impact_local.distance_to(point_a) < 0.001, "Rotated and recoiling cover maps the world strike to the visible face")
	_check(_light_matches_cracks(cover), "Initial beam origins and luminous fissures follow the real cracks under rotation and recoil")
	cover.mesh_instance.position = -cover.direction * 0.093
	cover.hit(0.2, cover.mesh_instance.to_global(point_b))
	var after_move := cover.get_visible_crack_segments()
	var rays_after: Array[Dictionary] = cover.light_node.get("_rays")
	_check(cover.impact_count == 2 and cover.latest_impact_local.distance_to(point_b) < 0.001, "A moved cover strike updates its mesh-local origin during recoil")
	_check(_crack_distance(point_b, after_move) < 0.001 and _old_cracks_remain(before_move, after_move), "Moved cover damage starts at the new impact while preserving the first network")
	_check(_ray_field_changes(rays_before, rays_after, "origin", 0.015), "Moving the impact changes beam source positions")
	_check(_ray_field_changes(rays_before, rays_after, "direction", 0.015), "Moving the impact changes the beams' fan directions")
	_check(_rays_reference_impact(rays_after, point_b), "The new beam pulse includes geometry rooted at the latest impact")
	_check(_light_matches_cracks(cover), "Moved beams and fissures share the visible crack geometry in world space")

	var tangent := (point_b - point_a).normalized()
	var bitangent := cover.direction.cross(tangent).normalized()
	var last_nearby := point_b
	for i in range(128):
		last_nearby = point_b + tangent * float(i % 7 - 3) * 0.001 + bitangent * float(i % 5 - 2) * 0.001
		cover.hit(0.002, cover.mesh_instance.to_global(last_nearby))
	var repeated: Array[Dictionary] = cover.get_visible_crack_segments().duplicate(true)
	_check(cover.impact_count == 130 and cover.latest_impact_local.distance_to(last_nearby) < 0.001, "Every repeated nearby strike updates the latest impact")
	_check(_crack_distance(last_nearby, repeated) < 0.001 and _old_cracks_remain(before_move, repeated), "Repeated nearby hits keep old damage and connect the current strike to it")
	_check(repeated.size() <= 656 and _large_crack_groups(repeated) <= 2, "Nearby hits reuse bounded crack networks instead of creating an unbounded fan per hit")
	_check(_light_matches_cracks(cover), "Repeated pulses remain bounded and attached to the actual visible cracks")
	var pulses_before_fatal: int = cover.light_node.pulse_count
	cover.hit(cover.health, cover.mesh_instance.to_global(point_c))
	var fatal_cover := cover.get_visible_crack_segments()
	var fatal_rays: Array[Dictionary] = cover.light_node.get("_rays")
	_check(cover.destroyed and cover.impact_count == 131 and cover.latest_impact_local.distance_to(point_c) < 0.001, "Fatal cover damage records the final moved strike before destruction")
	_check(_crack_distance(point_c, fatal_cover) < 0.001 and _old_cracks_remain(before_move, fatal_cover), "The fatal cover hit adds its own origin while retaining previous damage")
	_check(cover.light_node.pulse_count == pulses_before_fatal + 1 and _rays_reference_impact(fatal_rays, point_c), "The fatal pulse uses the final strike's new crack geometry")
	_check(_light_matches_cracks(cover), "The detached final flash has the same spatial sources as the fatal cracks")


func _light_matches_cracks(cover: Chunk) -> bool:
	var segments := cover.get_visible_crack_segments()
	var rays: Array[Dictionary] = cover.light_node.get("_rays")
	if segments.is_empty() or rays.is_empty() or rays.size() > Light.MAX_RAYS:
		return false
	var normal := cover.direction.normalized()
	for ray in rays:
		var source_index: int = ray.source_index
		if source_index < 0 or source_index >= segments.size():
			return false
		var source: Dictionary = segments[source_index]
		if Vector3(ray.source_a).distance_to(source.a) > 0.001 or Vector3(ray.source_b).distance_to(source.b) > 0.001:
			return false
		var planar_origin: Vector3 = ray.origin - normal * Light.RAY_OFFSET
		if _point_segment_distance(planar_origin, source.a, source.b) > 0.001:
			return false
		if absf(normal.dot(Vector3(source.a) - cover.face_center)) > 0.001 or absf(normal.dot(Vector3(source.b) - cover.face_center)) > 0.001:
			return false
		var world_origin: Vector3 = cover.light_node.to_global(ray.origin)
		var world_a := cover.mesh_instance.to_global(Vector3(source.a) + normal * Light.RAY_OFFSET)
		var world_b := cover.mesh_instance.to_global(Vector3(source.b) + normal * Light.RAY_OFFSET)
		if _point_segment_distance(world_origin, world_a, world_b) > 0.002:
			return false
		var world_normal := (cover.mesh_instance.global_basis.inverse().transposed() * normal).normalized()
		var world_direction: Vector3 = (cover.light_node.global_basis * Vector3(ray.direction)).normalized()
		if world_direction.dot(world_normal) <= 0.0:
			return false
	var fissures: MeshInstance3D = cover.light_node.get_node("LitFissures")
	if fissures.mesh == null or fissures.mesh.get_surface_count() == 0:
		return false
	var vertices: PackedVector3Array = fissures.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() != segments.size() * 6:
		return false
	for i in range(segments.size()):
		# Measure the actual two-triangle ribbon, including its placement transform.
		var local_a := (vertices[i * 6] + vertices[i * 6 + 1]) * 0.5
		var local_b := (vertices[i * 6 + 2] + vertices[i * 6 + 5]) * 0.5
		var expected_a := cover.mesh_instance.to_global(Vector3(segments[i].a) + normal * Light.CRACK_OFFSET)
		var expected_b := cover.mesh_instance.to_global(Vector3(segments[i].b) + normal * Light.CRACK_OFFSET)
		if fissures.to_global(local_a).distance_to(expected_a) > 0.002 or fissures.to_global(local_b).distance_to(expected_b) > 0.002:
			return false
	return true


func _old_cracks_remain(previous: Array[Dictionary], current: Array[Dictionary]) -> bool:
	if previous.is_empty() or current.is_empty():
		return false
	for line in previous:
		var candidates: Array[Dictionary] = []
		for candidate in current:
			if int(candidate.hit_id) == int(line.hit_id):
				candidates.append(candidate)
		if _crack_distance(line.a, candidates) > 0.002 or _crack_distance(line.b, candidates) > 0.002:
			return false
	return true


func _crack_distance(point: Vector3, segments: Array[Dictionary]) -> float:
	var closest := INF
	for segment in segments:
		closest = minf(closest, _point_segment_distance(point, segment.a, segment.b))
	return closest


func _point_segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var travel := b - a
	var t := clampf((point - a).dot(travel) / maxf(travel.length_squared(), 0.0000001), 0.0, 1.0)
	return point.distance_to(a + travel * t)


func _ray_field_changes(before: Array[Dictionary], after: Array[Dictionary], field: String, tolerance: float) -> bool:
	for new_ray in after:
		var nearest := INF
		for old_ray in before:
			nearest = minf(nearest, Vector3(new_ray[field]).distance_to(old_ray[field]))
		if nearest > tolerance:
			return true
	return false


func _rays_reference_impact(rays: Array[Dictionary], impact: Vector3) -> bool:
	for ray in rays:
		if Vector3(ray.source_impact).distance_to(impact) < 0.001:
			return true
	return false


func _large_crack_groups(segments: Array[Dictionary]) -> int:
	var counts: Dictionary = {}
	for segment in segments:
		var id: int = segment.hit_id
		counts[id] = int(counts.get(id, 0)) + 1
	var networks := 0
	for count in counts.values():
		if int(count) > 3:
			networks += 1
	return networks


func _light_color(light: Node3D) -> Color:
	var mesh: MeshInstance3D = light.get_node("LightShafts")
	return mesh.material_override.get_shader_parameter("light_color")


func _is_color_tier(color: Color, tier: int) -> bool:
	match tier:
		0: return color.r > 0.8 and color.g > 0.8 and color.b > 0.8
		1: return color.g > color.r and color.g > color.b
		2: return color.b > color.r and color.b > color.g
		3: return color.r > 0.8 and color.g > 0.7 and color.b < 0.6
		4: return color.r > 0.5 and color.b > 0.8 and color.g < 0.6
		5: return color.r > 0.8 and color.g < 0.5 and color.b < 0.6
	return false


func _materials_use_depth_test(light: Node3D) -> bool:
	var inspected := 0
	var mode_pattern := RegEx.new()
	mode_pattern.compile("render_mode\\s+([^;]+);")
	for child in light.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			inspected += 1
			var shader: Shader = child.material_override.shader
			for match_result in mode_pattern.search_all(shader.code):
				if match_result.get_string(1).contains("depth_test_disabled"):
					return false
	return inspected >= 3


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("GEM_LIGHT_CHECK_FAILED: " + description)
