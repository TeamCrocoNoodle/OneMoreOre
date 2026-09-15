extends SceneTree
## Measure the actual model's grip/head travel, not only the node's rotation.
const Pickaxe = preload("res://scripts/pickaxe.gd")
const Tools = preload("res://scripts/main_tools.gd")
const HAND_TOOLS := ["pickaxe", "axe", "hammer", "gold_pickaxe"]

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
	camera.position = Vector3(0.8, 2.5, 10)
	camera.look_at(Vector3.ZERO)
	camera.size = 8.4
	camera.current = true
	var pick := Pickaxe.new()
	pick.setup(camera)
	pick.set_process(false)
	pick.impacted.connect(func():
		contacts += 1
		var tip := camera.unproject_position(pick.to_global(pick.get_tip_local()))
		if tip.distance_to(pick.get_target_screen()) > 0.2: bad_contacts += 1
	)
	for dimensions: Vector2i in [Vector2i(1152,800),Vector2i(360,800),Vector2i(3840,2160)]:
		viewport.size = dimensions
		for projection in [Camera3D.PROJECTION_ORTHOGONAL,Camera3D.PROJECTION_PERSPECTIVE]:
			camera.projection = projection
			await process_frame
			var target := Vector2(dimensions) * Vector2(0.43,0.55)
			for id: String in HAND_TOOLS:
				pick.set_tool(id)
				pick.set_target(target)
				pick.set_contact_point(camera.project_position(target,5.7))
				pick.speed_multiplier = 1.0
				pick._process(0)
				pick.swing()
				pick._process(0)
				var grip := pick.to_global(pick.get_grip_local())
				var start_head := pick._visual.to_global(Vector3.ZERO)
				var previous_tip := pick.to_global(pick.get_tip_local())
				var tip_distance := 0.0
				var grip_error := 0.0
				var start_contacts := contacts
				for frame in 30:
					pick._process(0.005)
					grip_error = maxf(grip_error,grip.distance_to(pick.to_global(pick.get_grip_local())))
					var tip := pick.to_global(pick.get_tip_local())
					tip_distance += previous_tip.distance_to(tip)
					previous_tip = tip
					if pick._elapsed > 0.065 and pick._elapsed < Pickaxe.STRIKE_TIME:
						_check(pick._stroke_tip(pick._elapsed).distance_to(camera.to_local(tip)) < 0.001,id+" trail follows the real striking edge")
				_check(grip_error < 0.001,id+" grip remains the physical pivot during windup and strike")
				_check(tip_distance > 1.5*pick.scale.x,id+" blade travels through a broad arc")
				_check(start_head.distance_to(pick._visual.to_global(Vector3.ZERO)) > pick.scale.x,id+" head moves instead of acting as the hinge")
				_check(contacts == start_contacts+1,id+" swing has one contact")
				var recoil_error := 0.0
				for frame in 40:
					pick._process(0.005)
					recoil_error = maxf(recoil_error,grip.distance_to(pick.to_global(pick.get_grip_local())))
				_check(recoil_error < 0.20*pick.scale.x,id+" recovery gives the grip only a small recoil")
				_check(not pick.is_swinging,id+" recovery finishes on schedule")
				# Both aim axes turn the whole swing without stretching the tool
				# or changing its phase. The stationary grip checks above still hold.
				pick.swing()
				pick._process(0.09)
				var before_pose := pick.transform
				var before_length := pick.to_global(pick.get_grip_local()).distance_to(pick.to_global(pick.get_tip_local()))
				var offset := Vector2(dimensions)*Vector2(0.10,0.08)
				pick.set_target(target+offset)
				pick.set_contact_point(camera.project_position(target+offset,5.7))
				pick._process(0)
				var after_length := pick.to_global(pick.get_grip_local()).distance_to(pick.to_global(pick.get_tip_local()))
				_check(absf(after_length-before_length) < 0.001 and not pick.transform.is_equal_approx(before_pose),id+" diagonal aim turns the rigid tool around its grip")
				pick.set_target(target)
				pick.set_contact_point(camera.project_position(target,5.7))
				pick._process(0)
				_check(pick.transform.is_equal_approx(before_pose),id+" returning aim restores the same swing pose")
				pick.cancel_swing()
	# High attack speeds and frame stalls cannot skip or misplace a contact.
	for entry: Dictionary in Tools.CATALOG:
		pick.set_tool(entry.id)
		pick.set_target(Vector2(viewport.size)*0.5)
		for speed: float in [0.65,1.0,4.0,12.0]:
			pick.speed_multiplier = speed
			var before := contacts
			pick.swing()
			for frame in ceili(pick.get_cycle_duration()/speed/0.037)+2:
				pick._process(0.037)
			_check(contacts-before == int(entry.burst),str(entry.id)+" preserves contact count at speed "+str(speed))
		var before := contacts
		pick.swing()
		pick._process(1.0)
		_check(contacts-before == int(entry.burst),str(entry.id)+" preserves contacts across a stalled frame")
	_check(bad_contacts == 0,"Every impact signal occurs with the striking tip on the live cursor")
	viewport.queue_free()
	await process_frame
	print("TOOL_PIVOT_VALIDATION checks=%d failures=%d contacts=%d" % [checks,failures,contacts])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TOOL_PIVOT: "+message)
