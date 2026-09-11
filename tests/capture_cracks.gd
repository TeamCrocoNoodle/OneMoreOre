extends SceneTree
## Close views of the production stone, after its hit flash and light settle.

const Game = preload("res://scripts/main.gd")


func _initialize() -> void:
	_run.call_deferred()
	create_timer(25.0).timeout.connect(func(): quit(2))


func _run() -> void:
	var game := Game.new()
	game.showcase_on_start = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.marker.hide()
	game.pickaxe.hide()
	var cover: RockChunk = game.showcase_covers[5]
	cover.set_hovered(false)
	var focus := cover.mesh_instance.to_global(cover.face_center)
	var camera_basis := game.camera.global_basis
	game.camera.position = focus + camera_basis.z * 10.0
	game.camera.look_at(focus, camera_basis.y)
	game.camera.size = 3.4
	for strike in range(1, 16):
		var edge := int(float(cover.impact_count % 3) * float(cover.face_points.size()) / 3.0)
		var target := cover.face_center.lerp((cover.face_points[edge] + cover.face_points[(edge + 1) % cover.face_points.size()]) * 0.5, 0.52)
		cover.hit(1.0, cover.mesh_instance.to_global(target))
		if strike in [1, 3, 8, 15]:
			await create_timer(1.0).timeout
			await _save("cracks_%02d_settled" % strike)
	cover.light_node.pulse(5, 15.0 / 16.0)
	await create_timer(0.15).timeout
	await _save("cracks_15_lit")
	await create_timer(1.0).timeout
	game.camera.position = focus + (camera_basis.z + camera_basis.x * 0.50).normalized() * 10.0
	game.camera.look_at(focus, camera_basis.y)
	await _save("cracks_15_oblique")
	print("CRACK_CAPTURE_OK settled=4 lit=1 oblique=1")
	game.queue_free()
	await process_frame
	quit()


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://artifacts/" + label + ".png")
