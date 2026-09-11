extends SceneTree
## Normal startup and real raycast excavation of buried white/green gems.
const Main = preload("res://scripts/main.gd")
const Gem = preload("res://scripts/gem.gd")

var game: Main
var finished := false
var files: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
		if not finished:
			push_error("STARTER_CAPTURE_TIMEOUT")
			quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	game = Main.new()
	game.round_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.spawn_time = 1.0
	game.marker.hide()
	await physics_frame
	await create_timer(0.2).timeout
	var report := {"seed": game.rock_seed, "chunk_count": game.chunks.size(), "radius": game.active_rock_radius, "showcase": game.showcase_mode, "gems": []}
	var common: StaticBody3D
	var special: StaticBody3D
	for jewel in game.gems:
		var host: StaticBody3D = jewel.host_chunk.get_ref()
		report.gems.append({"rarity": Gem.GRADE_NAMES[jewel.grade], "color": Gem.LIGHT_NAMES[jewel.light_tier], "layer": host.layer_index, "position": [jewel.global_position.x, jewel.global_position.y, jewel.global_position.z], "hidden": not jewel.visible and jewel.is_embedded and jewel.collision_layer == 0})
		if jewel.grade == Gem.COMMON and common == null:
			common = jewel
		if jewel.grade == Gem.SPECIAL:
			special = jewel
	if game.showcase_mode or common == null or special == null:
		_fail("Normal startup must contain buried common and special gems")
		return
	await _save("starter_ore_initial")
	game.shell.rotate_y(PI)
	await physics_frame
	await _save("starter_ore_rotated")
	if not await _excavate(common, "common"):
		return
	if not await _excavate(special, "special"):
		return
	game._reset_rock()
	await create_timer(0.8).timeout
	game.spawn_time = 1.0
	await _save("starter_ore_rerolled")
	root.size = Vector2i(600, 1000)
	root.content_scale_size = root.size
	await process_frame
	game._resize()
	await _save("starter_ore_portrait")
	report["next_seed"] = game.rock_seed
	report["captures"] = files
	var file := FileAccess.open("res://artifacts/starter_ore_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	finished = true
	print("STARTER_CAPTURE_OK files=", files.size(), " first_seed=", report.seed, " next_seed=", game.rock_seed)
	game.queue_free()
	await process_frame
	quit()

func _excavate(jewel: StaticBody3D, label: String) -> bool:
	var host: StaticBody3D = jewel.host_chunk.get_ref()
	game.shell.quaternion = Quaternion(Vector3(host.direction).normalized(), game.camera.global_basis.z.normalized())
	await physics_frame
	for step in 80:
		var target: Vector2 = game.camera.unproject_position(host.mesh_instance.to_global(host.face_center))
		var ray := game.ray_at(target)
		if ray.is_empty():
			_fail("Excavation ray missed " + label)
			return false
		if ray.collider == host and host.health <= 1.0:
			host.light_node.pulse(jewel.light_tier, 15.0 / 16.0)
			await create_timer(0.12).timeout
			await _save("starter_ore_" + label + "_hint")
		game.pickaxe.set_target(target)
		if not game._mine_at(target):
			_fail("Excavation hit rejected " + label)
			return false
		if jewel.collected:
			await create_timer(0.43).timeout
			await _save("starter_ore_" + label + "_found")
			game._update_collections(3.0)
			await process_frame
			return true
		await create_timer(0.11).timeout
	_fail("Excavation did not reach " + label)
	return false

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/" + label + ".png"
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) != OK:
		_fail("Cannot save " + label)
		return
	files.append(path)

func _fail(message: String) -> void:
	finished = true
	push_error("STARTER_CAPTURE_FAILED: " + message)
	quit(1)
