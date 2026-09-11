extends SceneTree
## Render-only material/shape comparison using the game's actual stage setup.
## Run with --script res://tests/capture_gems.gd -- --tag=before for a baseline.

const Gem = preload("res://scripts/gem.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const ANGLE_A := Vector3(8.0, -22.0, 4.0)
const ANGLE_B := Vector3(-8.0, 42.0, -6.0)
const HERO_TIER := 1


class PreviewStage:
	extends "res://scripts/main.gd"

	func _ready() -> void:
		# Reuse the production environment, lights, background, shadow and camera.
		# The gameplay _ready() never runs, so no rock population or input loop starts.
		_create_stage()
		marker.hide()
		for spare in [rock_motion, shell, effects, audio, pickaxe]:
			spare.free()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)


var _stage: PreviewStage
var _gems: Array[Gem] = []
var _stone: Chunk
var _prefix := "gems"
var _saved: Array[String] = []
var _finished := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			var tag := argument.trim_prefix("--tag=").validate_filename().substr(0, 32)
			if not tag.is_empty():
				_prefix += "_" + tag
	_run.call_deferred()
	create_timer(25.0).timeout.connect(func():
		if not _finished:
			push_error("GEM_CAPTURE_TIMEOUT")
			quit(2)
	)


func _run() -> void:
	root.size = Vector2i(1440, 1000)
	root.content_scale_size = Vector2i(1440, 1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	_stage = PreviewStage.new()
	root.add_child(_stage)
	_stage.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_stage.camera.size = 7.1
	_build_catalog()
	_build_stone_comparison()
	_set_catalog_angle(ANGLE_A)
	await _settle()
	await _capture("angle_a")
	_set_hover(true)
	await _settle()
	await _capture("angle_a_hover")
	_set_hover(false)
	_set_catalog_angle(ANGLE_B)
	await _settle()
	await _capture("angle_b")
	_set_hover(true)
	await _settle()
	await _capture("angle_b_hover")
	_set_hover(false)
	_stage.camera.size = 5.2
	_stone.hide()
	for jewel in _gems:
		jewel.hide()
	var hero := _gems[HERO_TIER]
	hero.show()
	hero.position = _view_plane_position(0.0, -0.04)
	hero.rotation_degrees = ANGLE_A
	hero.scale = Vector3.ONE * 6.1
	await _settle()
	await _capture("hero")
	_finished = true
	print("GEM_CAPTURE_OK files=", _saved, " tiers=6 angles=2 hover=on/off hero_tier=", HERO_TIER)
	_stage.queue_free()
	await process_frame
	quit()


func _build_catalog() -> void:
	# Two rows, three columns: white/green/blue, then yellow/purple/red.
	# Every item is a real game Gem body with its unmodified facets and material.
	for tier in range(6):
		var jewel := Gem.new()
		jewel.configure(tier, tier if tier < Gem.ANCIENT else 0)
		_stage.add_child(jewel)
		var column := tier % 3
		var row := tier / 3
		jewel.position = _view_plane_position(-3.4 + float(column) * 2.5, 1.65 - float(row) * 3.0)
		jewel.scale = Vector3.ONE * 2.15
		_gems.append(jewel)


func _build_stone_comparison() -> void:
	var plates := Geometry.build_layer(4.9, 0, 12873, 100, 0.86)
	var chosen: Dictionary = plates[0]
	for plate in plates:
		if Vector3(plate.normal).z > Vector3(chosen.normal).z:
			chosen = plate
	_stone = Chunk.new()
	_stage.add_child(_stone)
	_stone.configure(chosen, 0)
	var face_radius := 0.0
	for vertex: Vector3 in chosen.face_points:
		face_radius = maxf(face_radius, vertex.distance_to(chosen.face_center))
	var toward_viewer := _stage.camera.global_basis.z.rotated(Vector3.UP, -0.18).normalized()
	_stone.quaternion = Quaternion(Vector3(chosen.normal).normalized(), toward_viewer)
	_stone.scale = Vector3.ONE * (0.83 / maxf(face_radius, 0.01))
	_stone.position = _view_plane_position(4.05, 0.15) - _stone.basis * Vector3(chosen.face_center)


func _view_plane_position(x: float, y: float) -> Vector3:
	return Vector3(0.0, -0.08, 0.0) + _stage.camera.global_basis.x * x + _stage.camera.global_basis.y * y


func _set_catalog_angle(degrees: Vector3) -> void:
	for jewel in _gems:
		jewel.rotation_degrees = degrees


func _set_hover(value: bool) -> void:
	for jewel in _gems:
		jewel.set_hovered(value)


func _settle() -> void:
	for i in range(4):
		await process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	if rendered.is_empty():
		push_error("GEM_CAPTURE_EMPTY_IMAGE: " + label)
		_finished = true
		quit(1)
		return
	var path := "res://artifacts/" + _prefix + "_" + label + ".png"
	var error := rendered.save_png(path)
	if error != OK:
		push_error("GEM_CAPTURE_WRITE_FAILED: " + path)
		_finished = true
		quit(1)
		return
	_saved.append(path)
