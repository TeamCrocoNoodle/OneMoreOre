extends SceneTree
## Reproduce simultaneous real damage; stress the recoil with long frame gaps.
const Game = preload("res://scripts/main.gd")
var game: Node3D
var checks := 0
var failures := 0
var peak := 0.0

func _initialize() -> void:
	_run.call_deferred()
	create_timer(90).timeout.connect(func(): push_error("WOBBLE_TIMEOUT"); quit(2))

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 12: push_error(message)

func _reset() -> void:
	game.wobble = Vector3.ZERO
	game.wobble_velocity = Vector3.ZERO
	game.rock_motion.rotation = Vector3.ZERO
	game.hit_stop = 0
	game.idle_time = 0

func _run() -> void:
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(1152,800)
	game = Game.new()
	root.add_child(game)
	for node in [game,game.pickaxe,game.hud,game.auxiliary]: node.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.focused = true
	game.campaign_enabled = false
	game._spawn_rock(12873)
	if game.spawn_tween != null: game.spawn_tween.kill()
	game.rock_motion.scale = Vector3.ONE
	game.spawn_time = 1
	game._start_round()
	await physics_frame
	await physics_frame
	var contacts: Array[Dictionary] = []
	for body in game.chunks:
		if body.is_gem_cover: continue
		var screen: Vector2 = game.camera.unproject_position(body.mesh_instance.to_global(body.face_center))
		var hit: Dictionary = game.ray_at(screen)
		if hit.get("collider") == body and not game._aim_over_hud(screen):
			body.health = 1000000
			body.max_health = 1000000
			contacts.append({"hit":hit,"screen":screen,"initial_hp":body.health})
			if contacts.size() == 9: break
	_check(contacts.size() == 9,"The stress fixture uses nine distinct actual surface contacts")
	if contacts.is_empty(): quit(1); return
	var hit_before: int = game.hit_count
	var amount := 4096
	var context := {"secondary":true}
	game.audio.begin_impact(true)
	for i in amount:
		var selected: Dictionary = contacts[i%contacts.size()]
		game._damage_chunk(selected.hit,selected.screen,context,1.0)
	game.audio.end_impact()
	var damage_sum := 0.0
	for selected in contacts: damage_sum += selected.initial_hp-selected.hit.collider.health
	_check(game.hit_count-hit_before == amount and damage_sum == amount,"Recoil limiting never drops or weakens any of 4,096 simultaneous hits")
	var accumulated: float = game.wobble_velocity.length()
	# Real frame path: a 250 ms stall ends the hit stop and advances feedback.
	game._process(.25)
	peak = game.wobble.length()
	print("WOBBLE_REPRO hits=",amount," velocity=",accumulated," angle_degrees=",rad_to_deg(peak))
	_check(game.wobble.is_finite() and peak <= deg_to_rad(6.01),"A mass hit followed by a long frame cannot spin the ore beyond six degrees")
	_validate_spring()
	_validate_lifecycle()
	_stop_audio(game)
	await create_timer(.10).timeout
	game.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	await create_timer(.10).timeout
	print("WOBBLE_VALIDATION checks=%d failures=%d peak_degrees=%.5f" % [checks,failures,rad_to_deg(peak)])
	quit(0 if failures == 0 else 1)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _validate_spring() -> void:
	# Integrating the same impulse for the same elapsed time is frame-rate independent.
	var reference := Vector3.ZERO
	for hz in [15,30,60,120,240]:
		_reset()
		game._add_rock_wobble(Vector3(.4,.2,.89).normalized())
		for frame in hz/3: game._advance_rock_wobble(1.0/hz)
		if hz == 15: reference = game.wobble
		_check(game.wobble.distance_to(reference) < .00001,"The spring agrees at 15 through 240 FPS for an isolated hit")
		_check(game.wobble.length() > .001,"A normal hit retains visible recoil")
	for hitch in [1.0/240,1.0/60,1.0/15,.12,.25,.5,1.0,4.0]:
		_reset()
		for frame in 60:
			for i in 256: game._add_rock_wobble(Vector3.RIGHT)
			game.hit_stop = .055
			game._advance_rock_wobble(hitch)
			peak = maxf(peak,game.wobble.length())
			_check(game.wobble.is_finite() and game.wobble_velocity.is_finite() and game.wobble.length() <= deg_to_rad(6.01),"Sustained simultaneous hits stay bounded even at long frame intervals")
		for frame in 240: game._advance_rock_wobble(1.0/120)
		_check(game.wobble == Vector3.ZERO and game.wobble_velocity == Vector3.ZERO,"Recoil settles completely after the last hit instead of accumulating hidden motion")
	_reset()
	game._add_rock_wobble(Vector3.RIGHT)
	game.hit_stop = .055
	game._process(1.0/120)
	_check(game.hit_stop > 0 and game.wobble.length() > 0,"Repeated hit stops cannot freeze and store the recoil spring")
	_reset()
	game.wobble = Vector3(.0002,0,0)
	game._advance_rock_wobble(.001)
	_check(game.wobble.length() > 0 and game.rock_motion.rotation == Vector3.ZERO,"Subpixel spring movement avoids needless ore hierarchy transform updates")
	game.wobble = Vector3(.002,0,0)
	game._advance_rock_wobble(.001)
	_check(game.rock_motion.rotation != Vector3.ZERO and game.rock_motion.rotation.distance_to(game.wobble) < .00001,"Visible spring movement still reaches the real ore transform")

func _validate_lifecycle() -> void:
	var orbit := Basis.from_euler(Vector3(.7,1.2,-.2))
	game.shell.basis = orbit
	for i in 120: game._advance_rock_wobble(1.0/120)
	_check(game.shell.basis.is_equal_approx(orbit),"Recoil settling preserves the player's chosen ore rotation")
	game._add_rock_wobble(Vector3.RIGHT)
	game._spawn_rock(61477)
	_check(game.wobble == Vector3.ZERO and game.wobble_velocity == Vector3.ZERO and game.rock_motion.rotation == Vector3.ZERO,"A new ore never inherits the old ore's recoil")
