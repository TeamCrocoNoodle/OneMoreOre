extends Node3D
## One authoritative controller for passive tools, input actions and ore epochs.
const Aux = preload("res://scripts/aux_tools.gd")
const Visual = preload("res://scripts/aux_tool_visual.gd")
const Pin = preload("res://scripts/aux_pin.gd")
const Hud = preload("res://scripts/aux_hud.gd")
const Audio = preload("res://scripts/aux_audio.gd")
var game: Node3D
var audio: Node
var hud: CanvasLayer
var random := RandomNumberGenerator.new()
var laser_remaining := 20.0
var laser_shots := 0
var detonator_used := false
var crusher_remaining := 0.0
var detector_level := 0
var detector_distance := INF
var detector_valid := false
var pin: StaticBody3D
var pin_roll_rock := -1
var _rock := -1
var _skip_remaining := -1.0
var _skip_rock := -1
var _beep_remaining := 0.0
var _sensor_remaining := 0.0
var _last_gem_count := -1
var _visuals: Dictionary = {}
var _beam: MeshInstance3D
var _beam_core: MeshInstance3D
var _beam_time := 0.0
var _beam_end := Vector3.ZERO
var _flash_id := ""
var _flash_time := 0.0
var _ghosts: Array[Dictionary] = []

func _ready() -> void:
	game = get_parent()
	random.randomize()
	audio = Audio.new()
	add_child(audio)
	hud = Hud.new()
	add_child(hud)
	hud.setup(game,self)
	_beam = _beam_mesh(Color(0.2,0.86,0.95,0.23),0.10)
	_beam_core = _beam_mesh(Color(0.88,1,1,0.95),0.024)
	reset_round()
	configure()

func configure() -> void:
	for id: String in ["laser","beer","crusher","detonator"]:
		if game.aux_tools.is_owned(id) and not _visuals.has(id):
			var model := Visual.new()
			model.build(id)
			model.hide()
			add_child(model)
			_visuals[id] = model
	hud.refresh()

func acquired(id: String) -> void:
	configure()
	audio.play({"laser":"laser_ready","beer":"beer","detector":"detector_ready","crusher":"crusher_ready","xray":"xray_scan","pin":"pin_ready","detonator":"detonator_ready"}.get(id,""))
	_last_gem_count = game.gems.size()
	if id == "beer": game._skill_notice(game.get_viewport().get_visible_rect().size*0.5,"최대 체력 +%s" % Aux.BEER_HEALTH,Color("efd39a"))

func reset_round() -> void:
	detonator_used = false
	crusher_remaining = 0.0
	laser_remaining = random.randf_range(Aux.LASER_MIN,Aux.LASER_MAX)
	_skip_remaining = -1.0
	_skip_rock = -1
	clear_world()

func on_rock_changed() -> void:
	_rock = game.rock_number
	_skip_remaining = -1.0
	_skip_rock = -1
	clear_world()
	detector_valid = false
	detector_distance = INF
	detector_level = 0
	_sensor_remaining = 0

func clear_world() -> void:
	_clear_pin()
	_beam_time = 0
	_flash_time = 0
	if is_instance_valid(_beam): _beam.hide()
	if is_instance_valid(_beam_core): _beam_core.hide()
	for ghost in _ghosts:
		if is_instance_valid(ghost.node): ghost.node.queue_free()
	_ghosts.clear()

func pause_feedback() -> void:
	_beam_time = 0
	_beam.hide()
	_beam_core.hide()
	audio.stop_all()

func can_activate(id: String) -> bool:
	if id == "crusher" and crusher_remaining > 0.0: return false
	if id == "crusher" and is_instance_valid(game.boss) and game.boss.active: return false
	return game.aux_tools.is_owned(id) and id in ["crusher","detonator"] and game.focused and game._round_allows_mining() and game.spawn_time >= game.ORE_SPAWN_DURATION and game.completion_time < 0 and not game.chunks.is_empty() and _skip_remaining < 0 and (id != "detonator" or not detonator_used)

func activate(id: String) -> bool:
	if not can_activate(id): return false
	game._start_round()
	game._clear_upgrade_input()
	_flash_id = id
	_flash_time = 0.95
	_layout_devices()
	if id == "crusher": _snapshot_intake()
	var damage := Aux.Balance.bulk_damage(id,float(game.upgrade_stats.damage),game.chunks.size())
	var result: Dictionary = game.remove_with_auxiliary(game.chunks.duplicate(),Aux.CRUSHER_RECOVERY if id == "crusher" else 1.0,id == "crusher",damage)
	if result.is_empty(): return false
	if id == "crusher": crusher_remaining = Aux.CRUSHER_COOLDOWN
	if id == "detonator": detonator_used = true
	_skip_remaining = game.ORE_RESPAWN_DELAY if game.chunks.is_empty() else -1.0
	_skip_rock = game.rock_number
	if id == "crusher":
		audio.play("crusher_start")
		audio.play("crusher_grind")
		game._skill_notice(game.camera.unproject_position(game.shell.global_position),"분쇄 · 회수 보석 가치 50%",Color("e9b97a"))
	else:
		audio.play("detonator_blast")
		game.effects.skill_burst(game.shell.global_position,game.camera.global_basis.z,Color("f7bc75"),3.6)
		game.camera_shake = 0.16
		game._skill_notice(game.camera.unproject_position(game.shell.global_position),"광맥 폭파!",Color("ffe1a3"))
	if game.using_controller and game.controller_id >= 0:
		Input.start_joy_vibration(game.controller_id,0.48,0.76,0.22)
	hud.refresh()
	return true

func advance(delta: float) -> void:
	if _rock != game.rock_number: on_rock_changed()
	if not game.focused or not game._round_allows_mining():
		if game.round_state.phase not in [game.RoundModel.Phase.READY,game.RoundModel.Phase.MINING]:
			_skip_remaining = -1
		hud.refresh()
		return
	if game.spawn_time < game.ORE_SPAWN_DURATION:
		detector_valid = false
		hud.refresh()
		return
	if game.aux_tools.is_owned("pin") and pin_roll_rock != game.rock_number:
		pin_roll_rock = game.rock_number
		if random.randf() < Aux.PIN_CHANCE: spawn_pin()
	if is_instance_valid(pin):
		var anchor: Node = pin.anchor.get_ref()
		if not is_instance_valid(anchor) or not game.chunks.has(anchor): _clear_pin()
	_sensor_remaining -= delta
	if _sensor_remaining <= 0:
		_sensor_remaining = 0.08
		update_detector()
	if game.aux_tools.is_owned("xray") and _last_gem_count != game.gems.size():
		_last_gem_count = game.gems.size()
		if not game.gems.is_empty(): audio.play("xray_scan",1.05)
	if game.round_state.phase != game.RoundModel.Phase.MINING:
		hud.refresh()
		return
	crusher_remaining = maxf(0.0,crusher_remaining-delta)
	if _skip_remaining >= 0:
		_skip_remaining -= delta
		if _skip_remaining <= 0 and _skip_rock == game.rock_number:
			_skip_remaining = -1
			if _flash_id == "crusher": audio.play("crusher_finish")
			game._spawn_rock()
			return
	if game.aux_tools.is_owned("laser") and not game.chunks.is_empty():
		laser_remaining -= delta
		if laser_remaining <= 0 and fire_laser():
			laser_remaining = random.randf_range(Aux.LASER_MIN,Aux.LASER_MAX)
	_beep_remaining -= delta
	if game.aux_tools.is_owned("detector") and detector_valid and detector_level > 0 and _beep_remaining <= 0:
		audio.play("detector_ping",0.90+detector_level*0.12)
		_beep_remaining = 1.45-detector_level*0.30
	hud.refresh()

func exposed_contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for body in game.chunks:
		if body.destroyed: continue
		var point: Vector3 = body.mesh_instance.to_global(body.face_center)
		var screen: Vector2 = game.camera.unproject_position(point)
		if game._aim_over_hud(screen) or not game.get_viewport().get_visible_rect().has_point(screen): continue
		var hit: Dictionary = game.ray_at(screen)
		if hit.get("collider") == body: result.append({"hit":hit,"screen":screen})
	return result

func fire_laser() -> bool:
	if not game.aux_tools.is_owned("laser") or game.round_state.phase != game.RoundModel.Phase.MINING or not game._round_allows_mining() or not game.focused: return false
	var contacts := exposed_contacts()
	if contacts.is_empty(): return false
	var selected: Dictionary = contacts[random.randi_range(0,contacts.size()-1)]
	var body: StaticBody3D = selected.hit.collider
	_beam_end = selected.hit.position
	_beam_time = 0.24
	var damage: float = Aux.Balance.boss_aux_damage(float(game.upgrade_stats.damage),body.max_health) if is_instance_valid(game.boss) and game.boss.active else body.health
	game._damage_chunk(selected.hit,selected.screen,{"secondary":true},damage)
	laser_shots += 1
	audio.play("laser_fire")
	_layout_devices()
	_update_beam()
	return true

func update_detector() -> void:
	detector_valid = false
	detector_distance = INF
	detector_level = 0
	if not game.aux_tools.is_owned("detector") or game._aim_over_hud(game.aim_position): return
	var contact: Dictionary = game.ray_at(game.aim_position)
	if contact.is_empty(): return
	detector_valid = true
	for jewel in game.gems:
		detector_distance = minf(detector_distance,Vector3(contact.position).distance_to(jewel.global_position))
	# World distance from the precise attack centre, independent of AOE size.
	if detector_distance < 0.85: detector_level = 3
	elif detector_distance < 1.65: detector_level = 2
	elif detector_distance < 3.0: detector_level = 1

func spawn_pin() -> bool:
	if not game.aux_tools.is_owned("pin") or is_instance_valid(pin) or not game._round_allows_mining(): return false
	var contacts := exposed_contacts()
	if contacts.is_empty(): return false
	var contact: Dictionary = contacts[random.randi_range(0,contacts.size()-1)]
	# Prefer a shared visible seam, rather than the silhouette of the ore.
	var placement := Vector3.INF
	var first := contacts.find(contact)
	for offset in contacts.size():
		var trial: Dictionary = contacts[(first+offset)%contacts.size()]
		var candidate: StaticBody3D = trial.hit.collider
		for index in candidate.face_points.size():
			var edge_point: Vector3 = candidate.mesh_instance.to_global((candidate.face_points[index]+candidate.face_points[(index+1)%candidate.face_points.size()])*0.5)
			var edge_screen: Vector2 = game.camera.unproject_position(edge_point)
			var across: Vector2 = (edge_screen-Vector2(trial.screen)).normalized()*game.get_viewport().get_visible_rect().size.y/game.camera.size*0.20
			var neighbour: Dictionary = game.ray_at(edge_screen+across)
			if neighbour.get("collider") != candidate and game.chunks.has(neighbour.get("collider")):
				# A raised neighbour must not hide the cap after the second hit.
				for lift: float in [0.075,0.16,0.24]:
					var proposed: Vector3 = edge_point+Vector3(trial.hit.normal)*lift
					if _pin_cap_clear(proposed,trial.hit.normal):
						contact = trial
						placement = proposed
						break
				if placement.is_finite(): break
		if placement.is_finite(): break
	var body: StaticBody3D = contact.hit.collider
	var normal: Vector3 = contact.hit.normal
	var edge: Vector3 = (body.face_points[0]+body.face_points[1])*0.5
	var world: Vector3 = body.mesh_instance.to_global(edge.lerp(body.face_center,0.10))+normal*0.075
	if placement.is_finite(): world = placement
	elif not _pin_cap_clear(world,normal): return false
	pin = Pin.new()
	game.shell.add_child(pin)
	pin.anchor = weakref(body)
	pin.position = game.shell.to_local(world)
	pin.surface_normal = (game.shell.global_basis.inverse()*normal).normalized()
	pin.quaternion = Quaternion(Vector3.UP,pin.surface_normal)
	pin.origin = pin.position
	var cap: Vector3 = pin.to_global(Vector3(0,0.35,0))
	game.effects.skill_burst(cap,normal,Color("e5cb89"),0.30)
	audio.play("pin_spawn")
	return true

func _pin_cap_clear(world: Vector3, normal: Vector3) -> bool:
	for depth in Aux.PIN_HITS:
		var cap := world+normal*(0.34-depth*0.105)
		var screen: Vector2 = game.camera.unproject_position(cap)
		if game._aim_over_hud(screen): return false
		var obstruction: Dictionary = game.ray_at(screen)
		if not obstruction.is_empty() and (cap-Vector3(obstruction.position)).dot(game.camera.global_basis.z) < 0.025:
			return false
	return true

func strike_pin(body: StaticBody3D) -> bool:
	if body != pin or not is_instance_valid(pin) or not game._round_allows_mining() or not game.focused: return false
	game._start_round()
	var count: int = pin.drive()
	var point := pin.global_position
	audio.play("pin_hit_%02d" % mini(3,count))
	game.effects.impact(point,game.camera.global_basis.z,false,Color("c5b78c"))
	game.camera_shake = 0.055
	if count >= Aux.PIN_HITS:
		var targets: Array[StaticBody3D] = []
		for chunk in game.chunks:
			if chunk.global_position.distance_to(point) <= Aux.PIN_RADIUS: targets.append(chunk)
		_clear_pin()
		game.remove_with_auxiliary(targets)
		game.effects.skill_burst(point,game.camera.global_basis.z,Color("edd19c"),Aux.PIN_RADIUS)
		game.camera_shake = 0.10
		audio.play("pin_break")
	return true

func _clear_pin() -> void:
	if is_instance_valid(pin):
		pin.collision_layer = 0
		pin.hide()
		pin.queue_free()
	pin = null

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	hud.refresh()
	if not game.focused: return
	_beam_time = maxf(0,_beam_time-delta)
	_flash_time = maxf(0,_flash_time-delta)
	_layout_devices(delta)
	_update_beam()
	for ghost in _ghosts:
		ghost.age += delta
		var t: float = clampf(float(ghost.age)/0.62,0,1)
		var node: MeshInstance3D = ghost.node
		var destination: Vector3 = _visuals.crusher.global_position
		node.global_position = Vector3(ghost.start).lerp(destination,t*t)+game.camera.global_basis.y*sin(t*PI)*0.5
		node.scale = Vector3.ONE*maxf(0.001,1-t*t)
		node.rotate_z(delta*2.0)
		if t >= 1: node.hide()

func _layout_devices(delta: float = 0.0) -> void:
	var viewport_size := game.get_viewport().get_visible_rect().size
	var units: float = game.camera.size/viewport_size.y*game.hud._scale
	for id: String in _visuals:
		var model: Node3D = _visuals[id]
		var permanent := id == "laser"
		model.visible = game._round_allows_mining() and (permanent or (_flash_id == id and _flash_time > 0))
		if not model.visible: continue
		var screen: Vector2 = Vector2(57*game.hud._scale,viewport_size.y*0.43) if permanent else viewport_size*Vector2(0.32,0.53)
		var basis: Basis = game.camera.global_basis*Basis.from_euler(Vector3(-0.15,0.25,-0.02))
		if permanent and _beam_time > 0:
			var aim: Vector3 = game.camera.global_basis.inverse()*(_beam_end-game.camera.project_position(screen,4.0))
			basis = game.camera.global_basis*Basis(Vector3.BACK,atan2(aim.y,aim.x))*Basis.from_euler(Vector3(-0.15,0.25,0))
		model.global_transform = Transform3D(basis.scaled(Vector3.ONE*units*(30.0 if permanent else 54.0)),game.camera.project_position(screen,4.0))
		model.animate(delta,id == "crusher" and _flash_time > 0)
		if id == "detonator": model.plunger.position.y = -0.42*sin(clampf((0.95-_flash_time)*5,0,PI))

func _beam_mesh(color: Color, radius: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius*0.70
	mesh.height = 1.0
	mesh.radial_segments = 6
	var model := MeshInstance3D.new()
	model.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	model.material_override = material
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(model)
	model.hide()
	return model

func _update_beam() -> void:
	var show_beam: bool = _beam_time > 0 and _visuals.has("laser") and game._round_allows_mining()
	_beam.visible = show_beam
	_beam_core.visible = show_beam
	if not show_beam: return
	var source: Vector3 = _visuals.laser.muzzle.global_position
	var travel := _beam_end-source
	for node: MeshInstance3D in [_beam,_beam_core]:
		node.global_position = (source+_beam_end)*0.5
		# Length is along the cylinder's LOCAL Y, before aiming it at the stone.
		node.global_basis = Basis(Quaternion(Vector3.UP,travel.normalized()))*Basis.from_scale(Vector3(1,travel.length(),1))
		node.material_override.albedo_color.a = minf(1,_beam_time*8.0)*(0.24 if node == _beam else 0.92)

func append_render_warmup(parent: Node3D) -> void:
	# Draw the additive shader once at startup, before the first laser shot.
	for source: MeshInstance3D in [_beam,_beam_core]:
		var proxy := MeshInstance3D.new()
		proxy.mesh = source.mesh
		proxy.material_override = source.material_override
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.position = Vector3(1.5,1.3,0.4)
		parent.add_child(proxy)

func _snapshot_intake() -> void:
	for i in mini(10,game.chunks.size()):
		var body: StaticBody3D = game.chunks[i*game.chunks.size()/mini(10,game.chunks.size())]
		var copy := MeshInstance3D.new()
		copy.mesh = body.mesh_instance.mesh
		copy.material_override = body.mesh_instance.material_override
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(copy)
		copy.global_transform = body.mesh_instance.global_transform
		_ghosts.append({"node":copy,"start":copy.global_position,"age":-i*0.008})
