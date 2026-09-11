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
var light_failure_reason := ""
var solid_offset_cache := {}


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
				_check(_materials_use_depth_test(light), "Beam, source, fissure, halo, and mote materials retain scene depth testing")
				if tier == 5:
					var junction_count := 0
					for segment in cover.get_surface_crack_segments():
						if bool(segment.get("junction", false)) and not bool(segment.has_centerline):
							junction_count += 1
					_check(junction_count > 0 and _light_matches_cracks(cover) and _halo_follows_cracks(cover), "The first three-arm junction is filled by an attached core/glow hull without adding a light ray")
			if strike == 15:
				_check(current == tier and _is_color_tier(_light_color(light), tier), "Every gem's final color becomes visible before the cover breaks")
			_check(broken == (strike == 16), "A 16 HP cover survives precisely 15 unit strikes")
		var expected: Array[int] = []
		for value in range(tier + 1):
			expected.append(value)
		_check(observed == expected, "A cover reveals exactly the complete color prefix ending at its gem tier")
		_check(cover.destroyed and cover.collision_layer == 0 and not cover.visible, "A destroyed cover stops hiding the gem")
		_check(_light_has_no_visuals(light), "A fatal cover hit retains its tier without building invisible light meshes")
		if tier == 5:
			_check(cover.get_visible_crack_segments().size() <= 9 and _light_matches_cracks(cover), "Sixteen strikes at one point deepen a compact crack network and illuminate every remaining segment")
	_validate_spatial_damage()
	_validate_crack_density()
	_validate_miter_contacts()

	var collectible := _make_gem(5)
	var neighboring_cover := _make_chunk()
	neighboring_cover.configure_gem_cover(collectible, 5)
	neighboring_cover.hit(1.0, neighboring_cover.to_global(neighboring_cover.face_center))
	var sources := neighboring_cover.light_node.get_node_or_null("LightSources") as MeshInstance3D
	var shafts := neighboring_cover.light_node.get_node("LightShafts") as MeshInstance3D
	_check(sources != null and sources.visible and sources.mesh != null and sources.mesh == shafts.mesh, "The source glow shares the current beam geometry during a pulse")
	neighboring_cover.light_node.set_process(false)
	var mote_mesh: Mesh = neighboring_cover.light_node.get_node("CrystalMotes").mesh
	var shaft_mesh: Mesh = shafts.mesh
	neighboring_cover.light_node._process(0.20)
	neighboring_cover.light_node._process(0.10)
	_check(shafts.mesh == shaft_mesh and sources.mesh == shaft_mesh and neighboring_cover.light_node.get_node("CrystalMotes").mesh == mote_mesh, "Beam expansion and mote travel reuse their uploaded meshes throughout a pulse")
	_check(float(shafts.material_override.get_shader_parameter("beam_growth")) == 1.0 and float(neighboring_cover.light_node.get_node("CrystalMotes").material_override.get_shader_parameter("effect_progress")) > 0.3, "Reused light meshes still advance their expansion and particle animation")
	neighboring_cover.light_node._process(2.0)
	_check(sources != null and not sources.visible and not shafts.visible, "Completing a pulse hides both its colored shaft and source glow")
	neighboring_cover.hit(1.0, neighboring_cover.to_global(neighboring_cover.face_center))
	_check(sources != null and sources.is_visible_in_tree() and sources.mesh != null and sources.mesh == shafts.mesh, "A subsequent strike renews the source glow on the new beam geometry")
	_check(collectible.begin_collection(), "The linked gem can enter collection once")
	await _frames(2)
	_check(not neighboring_cover.is_gem_cover and neighboring_cover.cover_gem == null and not neighboring_cover.light_node.visible, "Collecting a gem clears surviving cover links and their light")
	_check(sources != null and not sources.is_visible_in_tree() and sources.mesh == null and shafts.mesh == null and float(sources.material_override.get_shader_parameter("pulse_amount")) == 0.0, "Clearing a collected gem's light releases both shared geometry references and extinguishes its source glow")
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
	_check(_crack_distance(point_a, normal.get_surface_crack_segments()) < 0.001, "Visible ordinary-stone cracks begin at the actual first strike")
	_check(_has_tapered_tip(first), "The first strike creates a visible fissure that narrows to a sharp free tip")
	_check(_has_angular_bend(first), "The first strike creates a distinctly angled path instead of straight radial spokes")
	normal.hit(0.25, normal.mesh_instance.to_global(point_b))
	var second: Array[Dictionary] = normal.get_visible_crack_segments().duplicate(true)
	_check(normal.impact_count == 2 and normal.latest_impact_local.distance_to(point_b) < 0.001, "A second ordinary-stone hit moves the latest crack origin")
	_check(_crack_distance(point_b, normal.get_surface_crack_segments()) < 0.001 and _old_cracks_remain(first, second), "A distant ordinary hit adds damage at its own point and preserves earlier cracks")
	point_c = _uncovered_contact(normal)
	_check(point_c.is_finite(), "The fatal ordinary fixture selects a genuinely uncovered point on the actual surface")
	normal.hit(normal.health, normal.mesh_instance.to_global(point_c))
	var fatal_normal := normal.get_visible_crack_segments()
	_check(normal.destroyed and normal.impact_count == 3 and normal.latest_impact_local.distance_to(point_c) < 0.001, "The fatal ordinary-stone hit still records its actual impact")
	_check(_crack_distance(point_c, normal.get_surface_crack_segments()) < 0.001 and _old_cracks_remain(second, fatal_normal), "Fatal ordinary damage updates geometry without erasing earlier cracks")

	var promoted := _make_chunk()
	promoted.hit(0.25, promoted.mesh_instance.to_global(point_a))
	var before_promotion: Array[Dictionary] = promoted.get_visible_crack_segments().duplicate(true)
	promoted.configure_gem_cover(_make_gem(5), 5)
	_check(_old_cracks_remain(before_promotion, promoted.get_visible_crack_segments()), "Promoting a damaged stone to gem cover preserves its visible crack history")
	promoted.hit(0.25, promoted.mesh_instance.to_global(point_b))
	_check(_old_cracks_remain(before_promotion, promoted.get_visible_crack_segments()), "The first cover pulse retains cracks made before the gem was discovered")
	_check(_light_matches_cracks(promoted), "A promoted cover's light uses its existing and new visible cracks")
	_check(_projected_sheets_follow_source(promoted), "Each promoted-cover sheet projects its complete crack edge from one internal light source")
	_check(_halo_follows_cracks(promoted), "The fissure halo widens around the stone's actual existing and new crack traces")

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
	_check(_projected_sheets_follow_source(cover), "The internal source projects continuous straight sheets under rotation, nonuniform scale and recoil")
	_check(_halo_follows_cracks(cover), "The fissure halo shares the visible crack centerlines under rotation and recoil")
	cover.mesh_instance.position = -cover.direction * 0.093
	cover.hit(0.2, cover.mesh_instance.to_global(point_b))
	var after_move := cover.get_visible_crack_segments()
	var rays_after: Array[Dictionary] = cover.light_node.get("_rays")
	_check(cover.impact_count == 2 and cover.latest_impact_local.distance_to(point_b) < 0.001, "A moved cover strike updates its mesh-local origin during recoil")
	_check(_crack_distance(point_b, cover.get_surface_crack_segments()) < 0.001 and _old_cracks_remain(before_move, after_move), "Moved cover damage starts at the new impact while preserving the first network")
	_check(_ray_field_changes(rays_before, rays_after, "origin", 0.015), "Moving the impact changes beam source positions")
	_check(_ray_field_changes(rays_before, rays_after, "direction", 0.015), "Moving the impact changes the beams' fan directions")
	_check(_rays_reference_impact(rays_after, point_b), "The new beam pulse includes geometry rooted at the latest impact")
	_check(_light_matches_cracks(cover), "Moved beams and fissures share the visible crack geometry in world space")
	_check(_projected_sheets_follow_source(cover), "Moved damage retains shared projected endpoints instead of opening gaps between connected crack sections")
	_check(_halo_follows_cracks(cover), "Moving the impact updates the halo around both retained and newly created cracks")

	var tangent := (point_b - point_a).normalized()
	var bitangent := cover.direction.cross(tangent).normalized()
	var last_nearby := point_b
	var first_cycle_connections := -1
	var stable_connections := true
	for i in range(128):
		last_nearby = point_b + tangent * float(i % 7 - 3) * 0.001 + bitangent * float(i % 5 - 2) * 0.001
		cover.hit(0.002, cover.mesh_instance.to_global(last_nearby))
		var connections := _contact_connection_stats(cover.get_visible_crack_segments())
		if i == 34:
			first_cycle_connections = int(connections.count)
		elif i > 34:
			stable_connections = stable_connections and int(connections.count) == first_cycle_connections
	var repeated: Array[Dictionary] = cover.get_visible_crack_segments().duplicate(true)
	var connection_stats := _contact_connection_stats(repeated)
	_check(cover.impact_count == 130 and cover.latest_impact_local.distance_to(last_nearby) < 0.001, "Every repeated nearby strike updates the latest impact")
	_check(_visible_crack_covers(last_nearby, cover.get_surface_crack_segments()) and _old_cracks_remain(before_move, repeated), "Repeated nearby hits keep old damage and leave the current strike covered by an actual visible crack ribbon")
	_check(repeated.size() <= 32 and int(connection_stats.major_segments) <= 18 and _large_crack_groups(repeated) <= 2 and float(connection_stats.length) < 0.01, "Nearby hits keep two compact networks and less than one centimetre of extra contact connections")
	_check(stable_connections, "Replaying all 35 nearby contact positions adds no further connections after their first complete cycle")
	_check(_light_matches_cracks(cover), "Repeated pulses remain bounded and attached to the actual visible cracks")
	_check(_projected_sheets_follow_source(cover), "Repeated hits preserve one coherent projection through all retained crack edges")
	_check(_halo_follows_cracks(cover), "Repeated nearby damage keeps its halo centered on the accumulated visible crack traces")
	var pulses_before_fatal: int = cover.light_node.pulse_count
	point_c = _uncovered_contact(cover)
	_check(point_c.is_finite(), "The fatal cover fixture selects a genuinely uncovered point on the actual surface")
	cover.hit(cover.health, cover.mesh_instance.to_global(point_c))
	var fatal_cover := cover.get_visible_crack_segments()
	var fatal_rays: Array[Dictionary] = cover.light_node.get("_rays")
	_check(cover.destroyed and cover.impact_count == 131 and cover.latest_impact_local.distance_to(point_c) < 0.001, "Fatal cover damage records the final moved strike before destruction")
	_check(_crack_distance(point_c, cover.get_surface_crack_segments()) < 0.001 and _old_cracks_remain(before_move, fatal_cover), "The fatal cover hit adds its own origin while retaining previous damage")
	_check(cover.light_node.pulse_count == pulses_before_fatal + 1 and _rays_reference_impact(fatal_rays, point_c), "The fatal pulse uses the final strike's new crack geometry")
	_check(_light_matches_cracks(cover), "The final hit retains its spatial sources without uploading an invisible final flash")
	_check(_light_has_no_visuals(cover.light_node), "The fatal hit leaves no halo, shaft or mote geometry to render")


func _validate_crack_density() -> void:
	var cover := _make_chunk()
	cover.configure_gem_cover(_make_gem(5), 5)
	var prior: Array[Dictionary] = []
	var maximum_segments := 0
	var maximum_networks := 0
	var contacts_covered := true
	var history_preserved := true
	var all_segments_lit := true
	for strike in range(16):
		# Spread actual contacts through the interior of the face instead of
		# replaying a fixed origin or relying on crack-generator internals.
		var boundary_position := float(strike) * float(cover.face_points.size()) / 16.0
		var edge := floori(boundary_position)
		var boundary: Vector3 = cover.face_points[edge].lerp(cover.face_points[(edge + 1) % cover.face_points.size()], fposmod(boundary_position, 1.0))
		var point := cover.face_center.lerp(boundary, 0.36 + float(strike % 3) * 0.14)
		cover.hit(1.0, cover.mesh_instance.to_global(point))
		var current := cover.get_visible_crack_segments()
		maximum_segments = maxi(maximum_segments, current.size())
		maximum_networks = maxi(maximum_networks, _large_crack_groups(current))
		contacts_covered = contacts_covered and _visible_crack_covers(point, cover.get_surface_crack_segments())
		history_preserved = history_preserved and (prior.is_empty() or _old_cracks_remain(prior, current))
		var matches := _light_matches_cracks(cover)
		if not matches:
			print("DENSITY_LIGHT_DIAG strike=", strike + 1, " reason=", light_failure_reason)
		all_segments_lit = all_segments_lit and matches
		prior = current.duplicate(true)
	_check(maximum_segments <= 32 and maximum_networks <= 2, "Sixteen separated strikes keep at most two major crack networks and a bounded set of contact connections")
	_check(contacts_covered, "Every scattered strike remains covered by its actual visible crack ribbon")
	_check(history_preserved, "Adding scattered contact connections preserves earlier visible crack traces")
	_check(all_segments_lit, "Scattered strikes track every crack exactly once and suppress geometry on the fatal strike")


func _validate_miter_contacts() -> void:
	var cover := _make_chunk()
	cover.configure_gem_cover(_make_gem(5), 5)
	var first_point: Vector3 = cover.face_center.lerp(cover.face_points[0], 0.50)
	cover.hit(0.25, cover.mesh_instance.to_global(first_point))
	var cracks := cover.get_surface_crack_segments()
	var miter_point := Vector3.ZERO
	var found_miter := false
	for segment in cracks:
		if not bool(segment.has_centerline):
			continue
		var travel := Vector3(segment.b) - Vector3(segment.a)
		for end_key: String in ["a", "b"]:
			var endpoint: Vector3 = segment[end_key]
			var other: Vector3 = segment["b" if end_key == "a" else "a"]
			for sign_value: float in [-1.0, 1.0]:
				var candidate := endpoint + Vector3(segment["side_" + end_key]) * sign_value * 0.85 + (other - endpoint) * 0.01
				var t := (candidate - Vector3(segment.a)).dot(travel) / travel.length_squared()
				if (t < -0.0001 or t > 1.0001) and _visible_crack_covers(candidate, cracks):
					miter_point = candidate
					found_miter = true
					break
			if found_miter:
				break
		if found_miter:
			break
	_check(found_miter, "The contact fixture samples a real miter overhang beyond a segment's finite centerline range")
	if found_miter:
		var before := int(_contact_connection_stats(cover.get_visible_crack_segments()).count)
		cover.hit(0.01, cover.mesh_instance.to_global(miter_point))
		cracks = cover.get_surface_crack_segments()
		_check(int(_contact_connection_stats(cover.get_visible_crack_segments()).count) == before and cover.latest_impact_local.distance_to(miter_point) < 0.0001, "Striking an already rendered miter records the contact without adding a redundant connection")
	var outside_point := Vector3.ZERO
	var found_outside := false
	for segment in cracks:
		if bool(segment.has_centerline) and float(segment.width_b) < 0.00001:
			var candidate := Vector3(segment.b) + (Vector3(segment.b) - Vector3(segment.a)).normalized() * 0.01
			if _convex_contains(candidate, segment.triangle, segment.normal) and not _visible_crack_covers(candidate, cracks):
				outside_point = candidate
				found_outside = true
				break
	_check(found_outside, "The contact fixture also samples uncovered stone just beyond a tapering crack tip")
	if found_outside:
		var before := int(_contact_connection_stats(cover.get_visible_crack_segments()).count)
		cover.hit(0.01, cover.mesh_instance.to_global(outside_point))
		cracks = cover.get_surface_crack_segments()
		_check(int(_contact_connection_stats(cover.get_visible_crack_segments()).count) > before and _crack_distance(outside_point, cracks) < 0.0001 and _visible_crack_covers(outside_point, cracks), "Striking genuinely uncovered stone adds a connection at that actual contact instead of ignoring it")
	_check(_light_matches_cracks(cover), "Miter and uncovered-tip contacts retain exact one-to-one crack light geometry")


func _light_matches_cracks(cover: Chunk) -> bool:
	light_failure_reason = ""
	var segments := cover.get_surface_crack_segments()
	var rays: Array[Dictionary] = cover.light_node.get("_rays")
	var source_count := 0
	for segment in segments:
		if bool(segment.get("has_centerline", true)) and Vector3(segment.a).distance_squared_to(segment.b) > 0.00000001 and float(segment.width) > 0.0:
			source_count += 1
	if segments.is_empty() or rays.size() != source_count:
		light_failure_reason = "ray count %d expected %d" % [rays.size(), source_count]
		return false
	var shafts := cover.light_node.get_node_or_null("LightShafts") as MeshInstance3D
	var beam_vertices := PackedVector3Array()
	if cover.destroyed:
		if not _light_has_no_visuals(cover.light_node):
			return false
	else:
		if shafts == null or shafts.mesh == null or shafts.mesh.get_surface_count() != 1:
			return false
		beam_vertices = shafts.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if beam_vertices.size() != rays.size() * 6:
			return false
	var illuminated_sources: Dictionary = {}
	for ray_index in range(rays.size()):
		var ray := rays[ray_index]
		var source_index: int = ray.source_index
		if source_index < 0 or source_index >= segments.size() or illuminated_sources.has(source_index):
			return false
		illuminated_sources[source_index] = true
		var source: Dictionary = segments[source_index]
		var normal: Vector3 = source.get("normal", cover.direction)
		var offset_a: Vector3 = source.get("offset_a", normal)
		var offset_b: Vector3 = source.get("offset_b", normal)
		if not bool(source.get("has_centerline", true)):
			return false
		if Vector3(ray.source_a).distance_to(source.a) > 0.001 or Vector3(ray.source_b).distance_to(source.b) > 0.001:
			return false
		var planar_origin: Vector3 = ray.origin - (offset_a + offset_b) * 0.5 * Light.RAY_OFFSET
		if _point_segment_distance(planar_origin, source.a, source.b) > 0.001:
			return false
		if absf(normal.dot(Vector3(source.b) - Vector3(source.a))) > 0.001:
			return false
		var world_origin: Vector3 = cover.light_node.to_global(ray.origin)
		var world_a := cover.mesh_instance.to_global(Vector3(source.a) + offset_a * Light.RAY_OFFSET)
		var world_b := cover.mesh_instance.to_global(Vector3(source.b) + offset_b * Light.RAY_OFFSET)
		if _point_segment_distance(world_origin, world_a, world_b) > 0.002:
			return false
		# Measure the rendered root edge, not just its provenance metadata: the
		# whole crack segment must emit the sheet even after rotation and recoil.
		if not cover.destroyed:
			var root_a := shafts.to_global(beam_vertices[ray_index * 6])
			var root_b := shafts.to_global(beam_vertices[ray_index * 6 + 1])
			var direct_error := maxf(root_a.distance_to(world_a), root_b.distance_to(world_b))
			var reverse_error := maxf(root_a.distance_to(world_b), root_b.distance_to(world_a))
			if minf(direct_error, reverse_error) > 0.002:
				return false
			# Relative length also catches a collapsed point root on short cracks.
			var expected_length := world_a.distance_to(world_b)
			if absf(root_a.distance_to(root_b) - expected_length) > expected_length * 0.01:
				return false
		if world_origin.distance_to(world_a.lerp(world_b, 0.5)) > 0.002:
			return false
		var world_normal := (cover.mesh_instance.global_basis.inverse().transposed() * normal).normalized()
		var world_direction: Vector3 = (cover.light_node.global_basis * Vector3(ray.direction)).normalized()
		if world_direction.dot(world_normal) <= 0.0:
			return false
	if cover.destroyed:
		return true
	return _surface_light_attached(cover, "LitFissures", Light.CRACK_OFFSET)


func _light_has_no_visuals(light: Node3D) -> bool:
	if light.visible or light.is_processing():
		return false
	for child in light.get_children():
		if child is MeshInstance3D and child.mesh != null:
			return false
	return true


func _projected_sheets_follow_source(cover: Chunk) -> bool:
	var light := cover.light_node
	var emitter_value = light.get("_emitter_position")
	if not emitter_value is Vector3:
		return false
	var emitter: Vector3 = emitter_value
	var shafts := light.get_node_or_null("LightShafts") as MeshInstance3D
	var sources := light.get_node_or_null("LightSources") as MeshInstance3D
	if shafts == null or shafts.mesh == null or sources == null or sources.mesh != shafts.mesh:
		return false
	var arrays := shafts.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var roots: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var travel: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var rays: Array[Dictionary] = light.get("_rays")
	if vertices.size() != rays.size() * 6 or roots.size() != vertices.size() * 4 or travel.size() != roots.size():
		return false
	var common_scale := -1.0
	var projected_endpoints: Dictionary = {}
	var shared_endpoints := 0
	for ray_index in rays.size():
		var ray := rays[ray_index]
		var first := ray_index * 6
		var root_a := vertices[first]
		var root_b := vertices[first + 1]
		var tip_a := vertices[first + 5]
		var tip_b := vertices[first + 2]
		if not root_a.is_finite() or not root_b.is_finite() or not tip_a.is_finite() or not tip_b.is_finite():
			return false
		if not ray.has("tip_a") or not ray.has("tip_b") or Vector3(ray.tip_a).distance_to(tip_a) > 0.001 or Vector3(ray.tip_b).distance_to(tip_b) > 0.001:
			return false
		var origin: Vector3 = ray.origin
		var expected_direction := (origin - emitter).normalized()
		if expected_direction.length_squared() < 0.9 or expected_direction.dot(ray.direction) < 0.9999:
			return false
		# The stored, actually rendered far corners must lie beyond their roots
		# on rays from the same emitter, with one magnification for the whole net.
		for pair: Array in [[root_a, tip_a], [root_b, tip_b]]:
			var root_point: Vector3 = pair[0]
			var tip_point: Vector3 = pair[1]
			var from_source := root_point - emitter
			var to_tip := tip_point - emitter
			if from_source.length_squared() <= 0.000001:
				return false
			var factor := to_tip.dot(from_source) / from_source.length_squared()
			if factor <= 1.01 or to_tip.cross(from_source).length() / from_source.length() > 0.001:
				return false
			if common_scale < 0.0:
				common_scale = factor
			elif absf(factor - common_scale) > 0.001:
				return false
			var key := Vector3i(roundi(root_point.x * 100000.0), roundi(root_point.y * 100000.0), roundi(root_point.z * 100000.0))
			if projected_endpoints.has(key):
				shared_endpoints += 1
				if Vector3(projected_endpoints[key]).distance_to(tip_point) > 0.001:
					return false
			else:
				projected_endpoints[key] = tip_point
		var source_edge := root_b - root_a
		var far_edge := tip_b - tip_a
		if source_edge.length_squared() <= 0.00000001 or far_edge.distance_to(source_edge * common_scale) > 0.001:
			return false
		var sheet_normal := source_edge.cross(tip_a - root_a)
		if sheet_normal.length_squared() <= 0.000000000001 or absf(sheet_normal.normalized().dot(tip_b - root_a)) > 0.001:
			return false
		# Inspect the uploaded GPU-animation inputs as well as the rest mesh.
		# Every root stays fixed; far vertices carry their own endpoint's full
		# displacement, so growth cannot collapse the source line or tear a seam.
		for corner in 6:
			var index := first + corner
			var offset := index * 4
			var encoded_root := Vector3(roots[offset], roots[offset + 1], roots[offset + 2])
			var encoded_travel := Vector3(travel[offset], travel[offset + 1], travel[offset + 2])
			var expected_root := root_b if corner in [1, 2, 4] else root_a
			if encoded_root.distance_to(expected_root) > 0.001 or encoded_travel.distance_to(vertices[index] - expected_root) > 0.001:
				return false
	return common_scale > 1.0 and shared_endpoints > 0


func _halo_follows_cracks(cover: Chunk) -> bool:
	if Light.CRACK_CORE_RATIO <= 0.0 or Light.CRACK_CORE_RATIO >= 1.0 or Light.CRACK_GLOW_RATIO <= 1.0:
		return false
	return _surface_light_attached(cover, "FissureGlow", Light.GLOW_OFFSET) and _surface_light_attached(cover, "LitFissures", Light.CRACK_OFFSET)


func _surface_light_attached(cover: Chunk, node_name: String, depth: float) -> bool:
	var node := cover.light_node.get_node_or_null(node_name) as MeshInstance3D
	if node == null or node.mesh == null or node.mesh.get_surface_count() != 1:
		return false
	var ratio := Light.CRACK_CORE_RATIO if node_name == "LitFissures" else Light.CRACK_GLOW_RATIO
	var segments := cover.get_surface_crack_segments()
	var solid := _solid_offset_geometry(cover)
	var expected: Array[Dictionary] = []
	var junction_probes: Array[Dictionary] = []
	for segment in segments:
		if not segment.has_all(["ribbon", "triangle", "polygon", "normal"]):
			return false
		var ribbon: PackedVector3Array = segment.ribbon
		var scaled := PackedVector3Array()
		var junction := bool(segment.get("junction", false))
		var center: Vector3 = segment.get("junction_center", Vector3.ZERO)
		var radius := 0.00001
		for i in ribbon.size():
			var axis: Vector3 = center if junction else (segment.ribbon_a if i < 2 else segment.ribbon_b)
			scaled.append(axis + (ribbon[i] - axis) * ratio)
			radius = maxf(radius, ribbon[i].distance_to(center))
		# Independent convex intersection oracle: contained original corners
		# and pairwise edge intersections, rather than production clip order.
		var corners := _intersection_corners(scaled, segment.triangle, segment.normal)
		for point in corners:
			expected.append({"point": point + _physical_surface_offset(point, segment.normal, solid) * depth, "base": point, "ribbon": scaled, "junction": junction, "center": center, "normal": segment.normal, "radius": radius, "ratio": ratio})
		if junction and corners.size() >= 3:
			var centroid := Vector3.ZERO
			for point in corners:
				centroid += point
			centroid /= float(corners.size())
			junction_probes.append({"point": centroid, "normal": segment.normal})
			for i in corners.size():
				junction_probes.append({"point": centroid.lerp(corners[i].lerp(corners[(i + 1) % corners.size()], 0.5), 0.7), "normal": segment.normal})
	var arrays := node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if vertices.is_empty() or vertices.size() % 3 != 0 or vertices.size() != uvs.size():
		return false
	var bases := PackedVector3Array()
	for i in vertices.size():
		var actual := cover.mesh_instance.to_local(node.to_global(vertices[i]))
		if not actual.is_finite() or not uvs[i].is_finite() or uvs[i].x < -0.0001 or uvs[i].x > 1.0001 or uvs[i].y < -0.0001 or uvs[i].y > 1.0001:
			return false
		var found := false
		var closest_error := INF
		var closest_base := Vector3.ZERO
		for corner in expected:
			var error := actual.distance_to(corner.point)
			if error <= 0.0003 and error < closest_error and _surface_uv_matches(uvs[i], corner):
				closest_error = error
				closest_base = corner.base
				found = true
		if not found:
			light_failure_reason = "%s unmatched vertex %s uv=%s" % [node_name, actual, uvs[i]]
			return false
		bases.append(closest_base)
	# A central hull must fill the small gaps between root banks. Checking
	# just each branch centerline would miss an unchanged three-arm pinhole.
	for probe in junction_probes:
		if not _uploaded_surface_covers(probe.point, probe.normal, bases):
			light_failure_reason = "%s uncovered junction interior %s" % [node_name, probe.point]
			return false
	# The actual uploaded triangles must cover each source line after clipping.
	# This catches missing facets despite their surviving provenance metadata.
	for segment in segments:
		if not bool(segment.has_centerline) or Vector3(segment.a).distance_squared_to(segment.b) <= 0.00000001 or float(segment.width) <= 0.0:
			continue
		for t: float in [0.15, 0.5, 0.85]:
			var point: Vector3 = Vector3(segment.a).lerp(segment.b, t)
			if not _uploaded_surface_covers(point, segment.normal, bases):
				light_failure_reason = "%s uncovered centerline %s (face %d hit %d)" % [node_name, point, int(segment.face_id), int(segment.hit_id)]
				return false
	return true


func _surface_uv_matches(uv: Vector2, corner: Dictionary) -> bool:
	if not bool(corner.junction):
		return _uv_has_basis(uv, corner.base, corner.ribbon)
	var normal: Vector3 = corner.normal
	var x := normal.cross(Vector3.UP).normalized()
	if x.length_squared() < 0.1:
		x = normal.cross(Vector3.RIGHT).normalized()
	var y := normal.cross(x).normalized()
	var delta: Vector3 = (Vector3(corner.base) - Vector3(corner.center)) / float(corner.ratio)
	var expected := Vector2.ONE * 0.5 + Vector2(delta.dot(x), delta.dot(y)) / (float(corner.radius) * 2.0)
	return uv.distance_to(expected) < 0.0003


func _uploaded_surface_covers(point: Vector3, normal: Vector3, vertices: PackedVector3Array) -> bool:
	for i in range(0, vertices.size(), 3):
		if _convex_contains(point, PackedVector3Array([vertices[i], vertices[i + 1], vertices[i + 2]]), normal):
			return true
	return false


func _intersection_corners(first: PackedVector3Array, second: PackedVector3Array, normal: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for point in first:
		if _convex_contains(point, second, normal):
			points.append(point)
	for point in second:
		if _convex_contains(point, first, normal):
			points.append(point)
	for i in first.size():
		var a := first[i]
		var ab := first[(i + 1) % first.size()] - a
		for j in second.size():
			var c := second[j]
			var cd := second[(j + 1) % second.size()] - c
			var denominator := normal.dot(ab.cross(cd))
			if absf(denominator) < 0.000000001:
				continue
			var t := normal.dot((c - a).cross(cd)) / denominator
			var u := normal.dot((c - a).cross(ab)) / denominator
			if t >= -0.00001 and t <= 1.00001 and u >= -0.00001 and u <= 1.00001:
				points.append(a + ab * clampf(t, 0.0, 1.0))
	return points


func _convex_contains(point: Vector3, polygon: PackedVector3Array, normal: Vector3, tolerance: float = 0.0003) -> bool:
	if polygon.size() < 3 or absf((point - polygon[0]).dot(normal)) > tolerance:
		return false
	var sign_value := 0
	var area := 0.0
	for i in polygon.size():
		if absf((polygon[i] - polygon[0]).dot(normal)) > tolerance:
			return false
		var edge := polygon[(i + 1) % polygon.size()] - polygon[i]
		area += normal.dot(polygon[i].cross(polygon[(i + 1) % polygon.size()]))
		var side := normal.dot(edge.cross(point - polygon[i]))
		if absf(side) <= tolerance * edge.length():
			continue
		var current := 1 if side > 0.0 else -1
		if sign_value != 0 and sign_value != current:
			return false
		sign_value = current
	return absf(area) > 0.0000000001


func _solid_offset_geometry(cover: Chunk) -> Dictionary:
	var mesh := cover.mesh_instance.mesh
	var key := mesh.get_instance_id()
	if solid_offset_cache.has(key):
		return solid_offset_cache[key]
	var vertices := PackedVector3Array()
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			vertices.append_array(points)
		else:
			for index in indices:
				vertices.append(points[index])
	var corners := {}
	var edges := {}
	for i in range(0, vertices.size(), 3):
		var triangle := PackedVector3Array([vertices[i], vertices[i + 1], vertices[i + 2]])
		var cross := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
		if cross.length_squared() <= 0.000000000001:
			continue
		var normal := cross.normalized()
		if normal.dot((triangle[0] + triangle[1] + triangle[2]) / 3.0 - cover.gem_socket_center) < 0.0:
			normal = -normal
		for j in 3:
			var a := triangle[j]
			var b := triangle[(j + 1) % 3]
			var a_key := str(a.snapped(Vector3.ONE * 0.00001))
			var b_key := str(b.snapped(Vector3.ONE * 0.00001))
			if not corners.has(a_key):
				corners[a_key] = {"point": a, "normals": []}
			_add_unique_normal(corners[a_key].normals, normal)
			var edge_key := a_key + "/" + b_key if a_key < b_key else b_key + "/" + a_key
			if not edges.has(edge_key):
				edges[edge_key] = {"a": a, "b": b, "normals": []}
			_add_unique_normal(edges[edge_key].normals, normal)
	var solid := {"corners": corners.values(), "edges": edges.values()}
	solid_offset_cache[key] = solid
	return solid


func _add_unique_normal(normals: Array, normal: Vector3) -> void:
	for existing: Vector3 in normals:
		if existing.dot(normal) > 0.999999:
			return
	normals.append(normal)


func _physical_surface_offset(point: Vector3, normal: Vector3, solid: Dictionary) -> Vector3:
	# Only real solid corners/creases contribute a miter. Crack polygon banks
	# inside one planar facet cannot tilt or lift the core/glow off that facet.
	for corner: Dictionary in solid.corners:
		if corner.normals.size() < 2 or point.distance_to(corner.point) > 0.00003:
			continue
		var combined := Vector3.ZERO
		for adjacent: Vector3 in corner.normals:
			combined += adjacent
		combined = combined.normalized()
		var clearance := INF
		for adjacent: Vector3 in corner.normals:
			clearance = minf(clearance, combined.dot(adjacent))
		return combined / maxf(clearance, 0.25)
	for edge: Dictionary in solid.edges:
		if edge.normals.size() != 2 or _point_segment_distance(point, edge.a, edge.b) > 0.00003:
			continue
		var first: Vector3 = edge.normals[0]
		var second: Vector3 = edge.normals[1]
		if maxf(normal.dot(first), normal.dot(second)) > 0.999999:
			return (first + second) / maxf(1.0 + first.dot(second), 0.25)
	return normal


func _uv_has_basis(uv: Vector2, point: Vector3, corners: PackedVector3Array) -> bool:
	# Clipping interpolates both UVs and positions. All valid convex weights
	# for a given UV lie on this interval, even for a tapered non-parallelogram.
	var base := corners[0] * (1.0 - uv.x - uv.y) + corners[1] * uv.x + corners[3] * uv.y
	var mixed := corners[0] - corners[1] + corners[2] - corners[3]
	var first := base + mixed * maxf(0.0, uv.x + uv.y - 1.0)
	var last := base + mixed * minf(uv.x, uv.y)
	return _point_segment_distance(point, first, last) < 0.0003


func _has_tapered_tip(segments: Array[Dictionary]) -> bool:
	for segment in segments:
		if float(segment.get("width_a", 0.0)) > 0.005 and float(segment.get("width_b", 1.0)) < 0.00001:
			var joined := false
			for other in segments:
				if other != segment and (_point_segment_distance(segment.b, other.a, other.b) < 0.0001):
					joined = true
			if not joined:
				return true
	return false


func _has_angular_bend(segments: Array[Dictionary]) -> bool:
	for first in segments:
		for second in segments:
			if first == second or int(first.hit_id) != int(second.hit_id) or Vector3(first.b).distance_to(second.a) > 0.0001:
				continue
			var incoming := (Vector3(first.b) - Vector3(first.a)).normalized()
			var outgoing := (Vector3(second.b) - Vector3(second.a)).normalized()
			if incoming.dot(outgoing) < cos(deg_to_rad(15.0)) and incoming.dot(outgoing) > -0.95:
				return true
	return false


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
		if not bool(segment.get("has_centerline", true)):
			continue
		closest = minf(closest, _point_segment_distance(point, segment.a, segment.b))
	return closest


func _uncovered_contact(cover: Chunk) -> Vector3:
	var cracks := cover.get_surface_crack_segments()
	for fraction: float in [0.35, 0.5, 0.65]:
		for i in cover.face_points.size():
			var boundary: Vector3 = Vector3(cover.face_points[i]).lerp(cover.face_points[(i + 1) % cover.face_points.size()], 0.43)
			var point := cover.face_center.lerp(boundary, fraction)
			if not _visible_crack_covers(point, cracks) and _crack_distance(point, cracks) > 0.025:
				return point
	return Vector3.INF


func _visible_crack_covers(point: Vector3, segments: Array[Dictionary]) -> bool:
	for segment in segments:
		if segment.has("polygon"):
			if _convex_contains(point, segment.polygon, segment.normal, 0.00001):
				return true
			continue
		var travel := Vector3(segment.b) - Vector3(segment.a)
		var side := Vector3(segment.side_a) + Vector3(segment.side_b)
		var normal := travel.cross(side).normalized()
		if normal.length_squared() < 0.5:
			continue
		if _actual_ribbon_covers(point, [segment], normal):
			return true
	return false


func _actual_ribbon_covers(point: Vector3, segments: Array[Dictionary], normal: Vector3) -> bool:
	var u := normal.cross(Vector3.UP).normalized()
	if u.length_squared() < 0.1:
		u = normal.cross(Vector3.RIGHT).normalized()
	var v := normal.cross(u).normalized()
	for segment in segments:
		if absf((point - Vector3(segment.a)).dot(normal)) > 0.00001:
			continue
		var polygon := PackedVector2Array()
		for corner: Vector3 in [Vector3(segment.a) - Vector3(segment.side_a), Vector3(segment.a) + Vector3(segment.side_a), Vector3(segment.b) + Vector3(segment.side_b), Vector3(segment.b) - Vector3(segment.side_b)]:
			var delta := corner - point
			polygon.append(Vector2(delta.dot(u), delta.dot(v)))
		if Geometry2D.is_point_in_polygon(Vector2.ZERO, polygon):
			return true
		# Contacts on an actual edge still count, including a zero-width tip.
		for i in polygon.size():
			var edge := polygon[(i + 1) % polygon.size()] - polygon[i]
			var t := clampf(-polygon[i].dot(edge) / maxf(edge.length_squared(), 0.0000000001), 0.0, 1.0)
			if (polygon[i] + edge * t).length() < 0.00001:
				return true
	return false


func _contact_connection_stats(segments: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for segment in segments:
		counts[int(segment.hit_id)] = int(counts.get(int(segment.hit_id), 0)) + 1
	var result := {"count": 0, "length": 0.0, "major_segments": 0}
	for segment in segments:
		if int(counts[int(segment.hit_id)]) > 3:
			result.major_segments += 1
		else:
			result.count += 1
			result.length += Vector3(segment.a).distance_to(segment.b)
	return result


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
