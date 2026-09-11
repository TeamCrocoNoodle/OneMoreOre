extends SceneTree
## Real Main raycasts and real stone triangles; render-only integration fixture.
## --script res://tests/capture_all_face_cracks.gd
const Main = preload("res://scripts/main.gd")
const SEED := 12873

var game: Node3D
var chunk: StaticBody3D
var faces: Dictionary = {}
var saved: Array[String] = []
var observations: Array[Dictionary] = []
var finished := false

func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
		if not finished:
			push_error("ALL_FACE_CAPTURE_TIMEOUT")
			quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1200, 1000)
	root.content_scale_size = root.size
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	await _new_case()
	await _view("front")
	await _capture("allfaces_00_intact_front")
	for i in 15:
		if not await _strike("front"):
			return
	await _settle()
	for kind: String in ["front", "side", "rear"]:
		await _view(kind)
		await _capture("allfaces_front15_" + kind)
		chunk.light_node.pulse(5, 15.0 / 16.0)
		await create_timer(0.13).timeout
		await _capture("allfaces_front15_" + kind + "_lit")
		await _settle()
	await _new_case()
	await _view("side")
	if not await _strike("side"):
		return
	await _settle()
	await _capture("allfaces_side01_contact")
	for i in 14:
		if not await _strike("side"):
			return
	await _settle()
	for kind: String in ["side", "front", "rear"]:
		await _view(kind)
		await _capture("allfaces_side15_" + kind)
	await _view("side")
	var detail_normal: Vector3 = (chunk.mesh_instance.global_basis.inverse().transposed() * Vector3(faces.side.normal)).normalized()
	var detail_focus: Vector3 = chunk.mesh_instance.to_global(chunk.latest_impact_local)
	var detail_up := Vector3.UP if absf(detail_normal.dot(Vector3.UP)) < 0.90 else Vector3.RIGHT
	game.camera.global_position = detail_focus + detail_normal * 5.0
	game.camera.look_at(detail_focus, detail_up)
	game.camera.size *= 0.38
	await _capture("allfaces_side15_junction")
	await _new_case()
	await _view("rear")
	if not await _strike("rear"):
		return
	await _settle()
	await _capture("allfaces_rear01_contact")
	for i in 14:
		if not await _strike("rear"):
			return
	await _settle()
	for kind: String in ["rear", "side", "front"]:
		await _view(kind)
		await _capture("allfaces_rear15_" + kind)
	var file := FileAccess.open("res://artifacts/all_face_cracks_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed": SEED, "captures": saved, "hits": observations}, "\t"))
	file.close()
	finished = true
	print("ALL_FACE_CAPTURE_OK files=", saved.size(), " hits=", observations.size())
	game.queue_free()
	await process_frame
	quit()

func _new_case() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Main.new()
	game.capture_seed = SEED
	game.showcase_on_start = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.capture_mode = false
	game.pickaxe.hide()
	game.marker.hide()
	chunk = game.showcase_covers[5]
	for other in game.chunks:
		if other != chunk:
			other.hide()
			other.collision_layer = 0
	faces.clear()
	var triangles: PackedVector3Array = chunk.mesh_instance.mesh.get_faces()
	for i in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() < 0.0000000001:
			continue
		# Actual mesh winding, rather than the stored smooth/chamfer normal.
		var normal := -cross.normalized()
		var alignment: float = normal.dot(chunk.direction)
		var kind := "front" if alignment > 0.95 else ("rear" if alignment < -0.75 else "side")
		var area := cross.length() * 0.5
		if not faces.has(kind) or area > float(faces[kind].area):
			faces[kind] = {"point": (a + b + c) / 3.0, "normal": normal, "area": area, "triangle": i / 3}
	# Front-center is a real point on the broad cap, not a side-to-front clamp.
	if faces.has("front"):
		faces.front.point = chunk.face_center
	for kind: String in ["front", "side", "rear"]:
		if not faces.has(kind):
			push_error("ALL_FACE_CAPTURE_MISSING_FACE " + kind)
			finished = true
			quit(1)
	await physics_frame
	await process_frame
	# Spawn readiness normally advances in Main._process; camera framing is fixed here.
	game.spawn_time = 1.0

func _view(kind: String) -> void:
	var face: Dictionary = faces[kind]
	var transform: Transform3D = chunk.mesh_instance.global_transform
	var normal: Vector3 = (transform.basis.inverse().transposed() * Vector3(face.normal)).normalized()
	var bounds: AABB = chunk.mesh_instance.mesh.get_aabb()
	var center: Vector3 = transform * bounds.get_center()
	game.camera.global_position = center + normal * 5.0
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.90 else Vector3.RIGHT
	game.camera.look_at(center, up)
	game.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	game.camera.size = maxf(bounds.size.length() * 1.18, 1.8)
	game.camera.near = 0.02
	game.camera.far = 60.0
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _strike(kind: String) -> bool:
	var face: Dictionary = faces[kind]
	var requested: Vector3 = chunk.mesh_instance.to_global(face.point)
	var screen: Vector2 = game.camera.unproject_position(requested)
	var ray: Dictionary = game.ray_at(screen)
	if ray.get("collider") != chunk:
		push_error("ALL_FACE_CAPTURE_RAY_MISSED " + kind)
		finished = true
		quit(1)
		return false
	var hit_point: Vector3 = ray.position
	if not game._mine_at(screen):
		push_error("ALL_FACE_CAPTURE_HIT_REJECTED " + kind)
		finished = true
		quit(1)
		return false
	var surface_count := -1
	if chunk.has_method("get_surface_crack_segments"):
		surface_count = chunk.call("get_surface_crack_segments").size()
	observations.append({"face": kind, "triangle": face.triangle, "strike": chunk.impact_count,
		"health": chunk.health, "requested_world": _xyz(requested), "ray_hit_world": _xyz(hit_point),
		"recorded_local": _xyz(chunk.latest_impact_local), "surface_segment_count": surface_count})
	await create_timer(0.10).timeout
	return true

func _settle() -> void:
	await create_timer(1.05).timeout
	await RenderingServer.frame_post_draw

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/" + label + ".png"
	var status := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if status != OK:
		push_error("ALL_FACE_CAPTURE_SAVE_FAILED " + path)
		finished = true
		quit(1)
	else:
		saved.append(path)

func _xyz(point: Vector3) -> Array[float]:
	return [point.x, point.y, point.z]
