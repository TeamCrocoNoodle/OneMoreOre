extends SceneTree
## Focused cover/light lifecycle checks, independent of a particular gem layout.

const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const Gem = preload("res://scripts/gem.gd")

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
