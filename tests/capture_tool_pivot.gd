extends "res://tests/capture_tools.gd"
## Real game frames plus a diagnostic grip marker; no gameplay art is changed.
const HAND_TOOLS := ["pickaxe","axe","hammer","gold_pickaxe"]

class PivotMarkers extends Control:
	var pick: Node3D
	var camera: Camera3D
	var font := ThemeDB.fallback_font
	var caption := ""
	func _draw() -> void:
		var grip := camera.unproject_position(pick.to_global(pick.get_grip_local()))
		var target: Vector2 = pick.get_target_screen()
		draw_circle(grip,5,Color("63e3bd"))
		draw_arc(target,7,0,TAU,24,Color("e2a557"),2,true)
		draw_line(target-Vector2(12,0),target+Vector2(12,0),Color("e2a557"),1,true)
		draw_line(target-Vector2(0,12),target+Vector2(0,12),Color("e2a557"),1,true)
		draw_string(font,Vector2(20,30),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)

func _initialize() -> void:
	_run.call_deferred()
	create_timer(60).timeout.connect(func():
		if not finished: _fail("Tool pivot capture timed out")
	)

func _run() -> void:
	root.size = Vector2i(1152,800)
	root.content_scale_size = Vector2i(1440,1000)
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/tool_pivot"))
	game = CaptureGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game._process(0)
	await physics_frame
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var markers := PivotMarkers.new()
	markers.pick = game.pickaxe
	markers.camera = game.camera
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(markers)
	var aim := root.get_visible_rect().size*Vector2(0.43,0.57)
	var phases := [0.0,0.04,0.065,0.092,0.108,0.12,0.18,0.27,0.34]
	var sheet := Image.create(360*phases.size(),360*HAND_TOOLS.size(),false,Image.FORMAT_RGBA8)
	var trajectories: Array[Dictionary] = []
	for row in HAND_TOOLS.size():
		var id: String = HAND_TOOLS[row]
		game.pickaxe.cancel_swing()
		game.pickaxe.set_tool(id)
		game.pickaxe.speed_multiplier = 1
		game.pickaxe.set_target(aim)
		var contact: Dictionary = game.ray_at(aim)
		if not contact.is_empty(): game.pickaxe.set_contact_point(contact.position)
		game.pickaxe._process(0)
		game.pickaxe.swing()
		var elapsed := 0.0
		for col in phases.size():
			var phase: float = phases[col]
			game.pickaxe._process(phase-elapsed)
			elapsed = phase
			markers.caption = "%s   %.3f s   green: grip   gold: target" % [id,phase]
			markers.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			var physical_target: Vector2 = root.get_final_transform()*aim
			var crop := picture.get_region(Rect2i(Vector2i(physical_target)-Vector2i(85,300),Vector2i(500,500)))
			crop.resize(360,360,Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(crop,Rect2i(0,0,360,360),Vector2i(col*360,row*360))
			var path := "res://artifacts/tool_pivot/%s_%02d.png" % [id,col]
			picture.save_png(ProjectSettings.globalize_path(path))
			var grip: Vector2 = game.camera.unproject_position(game.pickaxe.to_global(game.pickaxe.get_grip_local()))
			var tip: Vector2 = game.camera.unproject_position(game.pickaxe.to_global(game.pickaxe.get_tip_local()))
			trajectories.append({"tool":id,"seconds":phase,"grip":[grip.x,grip.y],"tip":[tip.x,tip.y],"target":[aim.x,aim.y],"file":path})
		game._tool_impact_queue.clear()
		game.impact_pending = false
		_stop_audio(game)
	sheet.save_png(ProjectSettings.globalize_path("res://artifacts/tool_pivot/swing_sequences.png"))
	var report := FileAccess.open("res://artifacts/tool_pivot/trajectories.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(trajectories,"\t"))
	report.close()
	finished = true
	print("TOOL_PIVOT_CAPTURE_OK frames=",trajectories.size())
	layer.queue_free()
	game.queue_free()
	await process_frame
	quit()
