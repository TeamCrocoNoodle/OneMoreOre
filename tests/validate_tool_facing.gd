extends SceneTree
## Visible model orientation and live contacts across the whole ore silhouette.
const Pickaxe = preload("res://scripts/pickaxe.gd")
const Tools = preload("res://scripts/main_tools.gd")
var checks := 0
var failures := 0
var contacts := 0
var bad_contacts := 0

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30).timeout.connect(func(): quit(2))

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0.8, 2.5, 18)
	camera.look_at(Vector3.ZERO)
	camera.size = 14.0
	camera.current = true
	var pick := Pickaxe.new()
	pick.setup(camera)
	pick.set_process(false)
	pick.impacted.connect(func():
		contacts += 1
		var tip := camera.unproject_position(pick.to_global(pick.get_tip_local()))
		if tip.distance_to(pick.get_target_screen()) > 0.2: bad_contacts += 1
	)
	for dimensions: Vector2i in [Vector2i(1152,800), Vector2i(360,800), Vector2i(3840,2160)]:
		viewport.size = dimensions
		for projection in [Camera3D.PROJECTION_ORTHOGONAL, Camera3D.PROJECTION_PERSPECTIVE]:
			camera.projection = projection
			for keep_aspect in [Camera3D.KEEP_HEIGHT, Camera3D.KEEP_WIDTH]:
				camera.keep_aspect = keep_aspect
				await process_frame
				for radius: float in [2.3, 5.7]:
					# Off-center ore verifies that this is ore-relative, not a
					# fixed screen-center flip or a fixed pixel threshold.
					var ore := Vector3(0.5, -0.3, 0)
					pick.set_ore_bounds(ore, radius)
					var center := camera.unproject_position(ore)
					var span := camera.unproject_position(ore + camera.global_basis.x * radius).x - center.x
					var height := center.y - camera.unproject_position(ore + camera.global_basis.y * radius).y
					for entry: Dictionary in Tools.CATALOG:
						pick.set_tool(entry.id)
						var visual: Node3D = pick._visual
						var last_rotation := Quaternion.IDENTITY
						for step in 81:
							var lateral := lerpf(-1.25, 1.25, step / 80.0)
							var target := center + Vector2(span * lateral, 0)
							pick.set_target(target)
							pick._process(0)
							var actual := pick.basis.orthonormalized()
							var facing := actual.z.dot(Vector3.BACK)
							if lateral <= -1.0: _check(facing < -0.98, entry.id + " left shows the opposite broad face")
							if lateral >= 1.0: _check(facing > 0.98, entry.id + " right shows the broad face")
							if step == 40: _check(absf(facing) < 0.002, entry.id + " center shows the narrow edge")
							var current := actual.get_rotation_quaternion()
							if step > 0: _check(last_rotation.angle_to(current) < 0.08, entry.id + " turns continuously without a flip at the center or boundaries")
							last_rotation = current
						_check(pick._visual == visual, entry.id + " turning reuses the existing model")
						_validate_vertical(pick, camera, center, Vector2(span, height))
						# Cross the ore in a live swing, including slow frames that
						# pass multiple jackhammer contacts in one update.
						for speed: float in [1.0, 12.0]:
							pick.speed_multiplier = speed
							var before := contacts
							pick.swing()
							for step in 16:
								var travel := lerpf(-1.1, 1.1, step / 15.0)
								var target := center + Vector2(span * travel, height * sin(travel * PI * 0.5))
								pick.set_target(target)
								pick.set_contact_point(camera.project_position(target, 2.4 if step % 2 == 0 else 5.7))
								pick._process(0.033)
								if not pick._machine and pick._elapsed > 0.065 and pick._elapsed < Pickaxe.STRIKE_TIME:
									var tip := camera.to_local(pick.to_global(pick.get_tip_local()))
									_check(tip.distance_to(pick._stroke_tip(pick._elapsed)) < 0.001, entry.id + " trail follows the turned blade")
							_check(not pick.is_swinging and contacts - before == int(entry.burst), entry.id + " moving swing retains all contacts")
						pick.cancel_swing()
						pick.speed_multiplier = 1.0
						pick.set_target(center)
						var center_contacts := contacts
						pick.swing()
						pick._process(float(pick._strike_times[0]) + 0.0001)
						_check(contacts == center_contacts + 1, entry.id + " center pose is an actual emitted contact")
						if not pick._machine:
							var tip := camera.to_local(pick.to_global(pick.get_tip_local()))
							var grip := camera.to_local(pick.to_global(pick.get_grip_local()))
							_check(tip.z < grip.z - 0.8 * pick.scale.x, entry.id + " center strike points into the screen from the grip")
						pick.cancel_swing()
	_check(bad_contacts == 0, "Every contact reaches the live cursor in all facing directions and projections")
	viewport.queue_free()
	await process_frame
	print("TOOL_FACING_VALIDATION checks=%d failures=%d contacts=%d" % [checks, failures, contacts])
	quit(0 if failures == 0 else 1)

func _validate_vertical(pick: Node3D, camera: Camera3D, center: Vector2, half_size: Vector2) -> void:
	var id: String = pick.tool_id
	for lateral: float in [-0.65, 0.0, 0.65]:
		var previous := Quaternion.IDENTITY
		for step in 41:
			var vertical := lerpf(-1.25, 1.25, step / 40.0)
			pick.set_target(center + half_size * Vector2(lateral, vertical))
			pick._process(0)
			var actual := pick.basis.orthonormalized()
			var current := actual.get_rotation_quaternion()
			if step > 0: _check(previous.angle_to(current) < 0.11, id + " vertical and diagonal turning has no pole or edge flip")
			previous = current
			if lateral == 0.0 and vertical <= -1.0:
				_check(actual.y.z < -0.1, id + " above the ore tilts the handle away from the camera")
			if lateral == 0.0 and vertical >= 1.0:
				_check(actual.y.z > 0.7, id + " below the ore tilts the handle toward the camera")
		# Real contacts at all upper/lower corners, not just interpolated angles.
		for vertical: float in [-1.0, 1.0]:
			pick.set_target(center + half_size * Vector2(lateral, vertical))
			var before := contacts
			pick.swing()
			pick._process(float(pick._strike_times[0]) + 0.0001)
			_check(contacts == before + 1, id + " upper/lower pose emits a real contact")
			if not pick._machine:
				var tip := camera.to_local(pick.to_global(pick.get_tip_local()))
				var grip := camera.to_local(pick.to_global(pick.get_grip_local()))
				_check((tip.y - grip.y) * vertical > 0.7 * pick.scale.x, id + " upper/lower strike points vertically inward from its grip")
			pick.cancel_swing()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TOOL_FACING: " + message)
