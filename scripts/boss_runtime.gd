extends Node3D
## Boss mechanics use the same physical stone hits and input devices as mining.
const Campaign = preload("res://scripts/boss_campaign.gd")
const Geometry = preload("res://scripts/rock_geometry.gd")
const Visual = preload("res://scripts/boss_visual.gd")
const Audio = preload("res://scripts/boss_audio.gd")
const Stamina = preload("res://scripts/stamina_display.gd")
var game: Node3D
var audio := Audio.new()
var visual: Node3D
var active := false
var building := false
var stage := -1
var info: Dictionary = {}
var random := RandomNumberGenerator.new()
var clock := 0.0
var cells: Array[Dictionary] = []
var guards: Array[int] = []
var weak_slots: Array[int] = []
var weak_destroyed := 0
var weak_next := 2.6
var wire_effects: Array[String] = []
var wire_cut := [false,false,false]
var bomb_remaining := 60.0
var bomb_pause := 0.0
var bomb_speed := 1.0
var bomb_slow := 0.0
var spikes_out := false
var spike_next := 3.5
var volley_rest := false
var volley_timer := 0.8
var volley_shots := 0
var projectiles: Array[Dictionary] = []
var regen_count := 0
var parry_count := 0
var _layer := 0
var _builder: RefCounted
var _pending_damage: Array[WeakRef] = []
var _last_block := -10.0
var _total_health := 1.0

func _ready() -> void:
	game = get_parent()
	audio.impact_mixer = game.audio
	add_child(audio)
	set_process(false)

func start(index: int, seed_value: int) -> void:
	clear()
	stage = index
	info = Campaign.BOSSES[stage].duplicate(true)
	active = true
	building = true
	random.seed = seed_value ^ 0x41A671
	game._clear_ore_scene(game.round_enabled and game.completion_time >= 0.0 and game.round_state.phase == game.RoundModel.Phase.MINING)
	game.showcase_mode = false
	game.ore_profile = game.OreProgression.profile(game.round_state.lifetime_mining_gold,stage)
	game.ore_profile.color = info.color
	game.ore_profile.accent = info.accent
	game.ore_profile.theme = mini(stage,6)
	game.rock_seed = seed_value
	game.active_layer_counts = info.layers.duplicate()
	game.active_rock_radius = float(info.radius)*1.20
	game.ore_building = true
	game.completion_time = -1.0
	game.spawn_time = 0
	game.rock_motion.scale = Vector3.ONE
	game.rock_motion.position = Vector3.ZERO
	game.rock_motion.rotation = Vector3.ZERO
	game.shell.rotation = Vector3(0.05,0,0)
	game.wobble = Vector3.ZERO
	game.wobble_velocity = Vector3.ZERO
	game.impact_pending = false
	game.hovered = null
	game.broken_count = 0
	game._clear_upgrade_input()
	game.round_state.start()
	game.round_state.refill_for_boss()
	game._set_boss_skill_rules(true)
	game._set_stage_theme(info)
	game._resize()
	_layer = 0
	_make_builder()
	_refresh_hud()

func _make_builder() -> void:
	var stride := (float(info.radius)-1.2)/maxi(1,info.layers.size()-1)
	_builder = Geometry.LayerBuilder.new(float(info.radius)-_layer*stride,_layer,game.rock_seed,info.layers[_layer],stride+.08,game.ore_profile)

func advance_build() -> void:
	if not building or not game.focused: return
	var deadline := Time.get_ticks_usec()+5000
	while building and Time.get_ticks_usec() < deadline:
		if _layer >= info.layers.size():
			_complete_build()
		elif _builder.cursor < _builder.count:
			var data: Dictionary = _builder.next_cell()
			if data.is_empty(): continue
			var slot := cells.size()
			cells.append({"data":data,"layer":_layer,"generation":0,"chunk":null,"regen_at":-1.0})
			_spawn_cell(slot)
		else:
			_layer += 1
			if _layer < info.layers.size(): _make_builder()
	_refresh_hud()

func _spawn_cell(slot: int) -> StaticBody3D:
	var record: Dictionary = cells[slot]
	game._add_ore_cell(record.data.duplicate(),int(record.layer))
	var chunk: StaticBody3D = game.chunks.back()
	chunk.set_meta("boss_slot",slot)
	# Keep the mesh, collider, cracks and regeneration in the same shaped space.
	chunk.scale = info.get("shape",Vector3.ONE)
	chunk.position *= chunk.scale
	chunk._material.set_shader_parameter("theme_detail",.18)
	chunk.max_health = float(info.health)*pow(.5,int(record.generation))
	chunk.health = chunk.max_health
	record.chunk = weakref(chunk)
	record.regen_at = -1.0
	return chunk

func _complete_build() -> void:
	building = false
	game.ore_building = false
	_builder = null
	game.spawn_time = game.ORE_SPAWN_DURATION
	game.rock_number += 1
	game.ground_shadow.position = Vector3(0,-float(info.radius)*float(info.get("shape",Vector3.ONE).y)-.46,-.2)
	game.ground_shadow.scale = Vector3.ONE*(float(info.radius)/game.SHOWCASE_RADIUS)
	game.auxiliary.on_rock_changed()
	visual = Visual.new()
	add_child(visual)
	visual.build(game,info)
	_total_health = cells.size()*float(info.health)*(1.75 if stage == 0 else 1.0)
	match stage:
		1:
			guards = _spread_slots(6)
			_refresh_guards()
		2:
			weak_slots = _spread_slots(5)
			_refresh_weaknesses()
		3:
			wire_effects = ["accelerate","slow","defuse"]
			for i in range(2,0,-1):
				var j := random.randi_range(0,i)
				var swap := wire_effects[i]
				wire_effects[i] = wire_effects[j]
				wire_effects[j] = swap
			visual.add_wires()
			for wire in visual.wires: wire.collision_layer = 0
		4:
			for chunk in game.chunks: visual.add_spike(chunk)
			spike_next = random.randf_range(3.2,4.8)
	audio.play(stage,"entry")
	game._skill_notice(game.get_viewport().get_visible_rect().size*Vector2(.5,.25),info.title,info.accent)
	_refresh_hud()

func _body(slot: int) -> StaticBody3D:
	if slot < 0 or slot >= cells.size() or cells[slot].chunk == null: return null
	var chunk = cells[slot].chunk.get_ref()
	return chunk if is_instance_valid(chunk) and game.chunks.has(chunk) and not chunk.destroyed else null

func _spread_slots(count: int) -> Array[int]:
	var chosen: Array[int] = []
	for n in count:
		var best := -1
		var best_score := -INF
		for i in cells.size():
			var chunk := _body(i)
			if chunk == null or chunk.layer_index != 0 or chosen.has(i): continue
			var score := random.randf()*.04
			var separation := 2.0
			for previous in chosen: separation = minf(separation,1.0-chunk.direction.dot(_body(previous).direction))
			score += separation
			if score > best_score: best = i; best_score = score
		if best >= 0: chosen.append(best)
	return chosen

func _neighbors(slot: int, limit: int = 4) -> Array[int]:
	var choices: Array[Dictionary] = []
	var origin: Vector3 = cells[slot].data.center
	for i in cells.size():
		var chunk := _body(i)
		if i == slot or chunk == null: continue
		choices.append({"slot":i,"distance":origin.distance_squared_to(cells[i].data.center)})
	choices.sort_custom(func(a,b): return a.distance < b.distance)
	var found: Array[int] = []
	for i in mini(limit,choices.size()): found.append(choices[i].slot)
	return found

func _refresh_guards() -> void:
	var protected: Array[int] = []
	for guard in guards:
		if _body(guard) == null: continue
		for slot in _neighbors(guard,5):
			if not guards.has(slot) and not protected.has(slot): protected.append(slot)
	for slot in cells.size():
		var chunk := _body(slot)
		if chunk == null: continue
		chunk.set_meta("boss_protected",protected.has(slot))
		visual.mark(chunk,"guard" if guards.has(slot) else "protected" if protected.has(slot) else "",info.accent)

func _refresh_weaknesses() -> void:
	for slot in cells.size():
		var chunk := _body(slot)
		if chunk != null: visual.mark(chunk,"weak" if weak_slots.has(slot) else "",info.accent)

func can_damage_chunk(chunk: StaticBody3D) -> bool:
	if not active: return true
	return not building and not bool(chunk.get_meta("boss_protected", false)) and not (stage == 5 and not volley_rest and not chunk.has_meta("boss_projectile"))

func filter_hit(chunk: StaticBody3D, context: Dictionary) -> bool:
	if not active: return true
	if building: return false
	if stage == 4 and spikes_out and not bool(context.get("secondary",false)) and not bool(context.get("boss_checked",false)):
		context["boss_checked"] = true
		_hurt_player(maxf(2.0,game.round_state.duration*.08))
		if not active: return false
	if not can_damage_chunk(chunk):
		if clock-_last_block > .18:
			_last_block = clock
			audio.play(stage,"hit",.68,bool(context.get("secondary",false)))
			game.effects.skill_burst(chunk.to_global(chunk.face_center),game.camera.global_basis.z,info.accent,.22)
		return false
	return true

func on_chunk_broken(chunk: StaticBody3D) -> void:
	if not active: return
	if chunk.has_meta("boss_projectile"):
		parry_count += 1
		for i in range(projectiles.size()-1,-1,-1):
			if projectiles[i].node == chunk: projectiles.remove_at(i)
		audio.play(stage,"ability",1.5)
		return
	if not chunk.has_meta("boss_slot"): return
	var slot := int(chunk.get_meta("boss_slot"))
	var record: Dictionary = cells[slot]
	if stage == 0 and int(record.generation) < 2:
		record.generation += 1
		record.regen_at = clock+1.6
	elif stage == 1 and guards.has(slot):
		guards.erase(slot)
		_refresh_guards()
	elif stage == 2 and weak_slots.has(slot):
		weak_slots.erase(slot)
		weak_destroyed += 1
		for neighbor in _neighbors(slot,4):
			var target := _body(neighbor)
			if target != null and not weak_slots.has(neighbor): _pending_damage.append(weakref(target))
		audio.play(stage,"ability")
	elif stage == 3 and bomb_armor_remaining() == 0:
		for wire in visual.wires:
			if not wire_cut[visual.wires.find(wire)]: wire.collision_layer = 1
	_refresh_hud()

func bomb_armor_remaining() -> int:
	return maxi(0,ceili(cells.size()*Campaign.Balance.BOMB_ARMOR_FRACTION)-(cells.size()-_stock().size()))

func cut_wire(index: int) -> bool:
	if not active or building or stage != 3 or index < 0 or index >= 3 or wire_cut[index]: return false
	if bomb_armor_remaining() > 0: return false
	wire_cut[index] = true
	visual.wires[index].sever()
	audio.play(stage,"ability",1.0+index*.15)
	match wire_effects[index]:
		"accelerate": bomb_pause = 2.0; bomb_speed = 2.0
		"slow": bomb_slow = 8.0
		"defuse": _finish(true)
	_refresh_hud()
	return true

func advance(delta: float) -> void:
	if not active or building or not game.focused or not game._round_allows_mining() or delta <= 0 or not is_finite(delta): return
	clock += delta
	var regen_deadline := Time.get_ticks_usec()+5000
	var regenerated := 0
	for record in cells:
		if float(record.regen_at) >= 0 and clock >= float(record.regen_at) and regenerated < 3 and Time.get_ticks_usec() < regen_deadline:
			var chunk := _spawn_cell(cells.find(record))
			regenerated += 1
			regen_count += 1
			chunk.mesh_instance.scale = Vector3.ONE*.15
			create_tween().tween_property(chunk.mesh_instance,"scale",Vector3.ONE,.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			audio.play(stage,"ability")
	for i in mini(3,_pending_damage.size()):
		var target = _pending_damage.pop_front().get_ref()
		if is_instance_valid(target) and game.chunks.has(target): _fatal_hit(target)
		if not active: return
	match stage:
		2:
			weak_next -= delta
			if weak_next <= 0:
				weak_next = 2.6
				for i in weak_slots.size():
					var choices := _neighbors(weak_slots[i],6)
					for slot in choices:
						if not weak_slots.has(slot):
							# Damage travels with the moving weakness; stronger bosses
							# must not erase progress every time the marker moves.
							var previous := _body(weak_slots[i])
							var remaining: float = previous.health
							previous.health = previous.max_health
							weak_slots[i] = slot
							_body(slot).health = remaining
							break
				_refresh_weaknesses()
				audio.play(stage,"ability")
		3: _advance_bomb(delta)
		4:
			spike_next -= delta
			while spike_next <= 0:
				spikes_out = not spikes_out
				spike_next += random.randf_range(1.7,2.8) if spikes_out else random.randf_range(3.2,5.0)
				audio.play(stage,"ability",1.0 if spikes_out else .75)
		5: _advance_artillery(delta)
	if is_instance_valid(visual): visual.animate(delta,spikes_out,not spikes_out and spike_next < .6)
	check_victory()
	_refresh_hud()

func _advance_bomb(delta: float) -> void:
	var remaining_delta := delta
	while remaining_delta > .000001 and active:
		var slice := remaining_delta
		if bomb_pause > 0: slice = minf(slice,bomb_pause)
		if bomb_slow > 0: slice = minf(slice,bomb_slow)
		if bomb_pause <= 0: bomb_remaining = maxf(0,bomb_remaining-slice*(.5 if bomb_slow > 0 else bomb_speed))
		bomb_pause = maxf(0,bomb_pause-slice)
		bomb_slow = maxf(0,bomb_slow-slice)
		remaining_delta -= slice
		if bomb_remaining <= 0: _finish(false)

func _advance_artillery(delta: float) -> void:
	volley_timer -= delta
	if volley_timer <= 0:
		if volley_rest:
			volley_rest = false
			volley_shots = 0
			volley_timer = .65
		elif volley_shots >= 4 or _stock().is_empty():
			volley_rest = true
			volley_timer = 4.5
			audio.play(stage,"ability",.68)
		else:
			_throw_stone()
			volley_shots += 1
			volley_timer = .85
	for i in range(projectiles.size()-1,-1,-1):
		var flight: Dictionary = projectiles[i]
		var chunk: StaticBody3D = flight.node
		if not is_instance_valid(chunk) or not game.chunks.has(chunk): projectiles.remove_at(i); continue
		flight.age += delta
		var t: float = clampf(flight.age/2.6,0,1)
		chunk.global_position = Vector3(flight.start).lerp(flight.target,t)+game.camera.global_basis.y*sin(t*PI)*.7
		chunk.rotate_object_local(Vector3.UP,delta*2.0)
		if t >= 1:
			projectiles.remove_at(i)
			game.chunks.erase(chunk)
			chunk.collision_layer = 0
			chunk.hide()
			chunk.queue_free()
			_hurt_player(maxf(3.0,game.round_state.duration*.12))
			if not active: return

func _stock() -> Array[StaticBody3D]:
	var found: Array[StaticBody3D] = []
	for chunk in game.chunks:
		if not chunk.has_meta("boss_projectile") and not chunk.destroyed: found.append(chunk)
	return found

func _throw_stone() -> void:
	var stock := _stock()
	if stock.is_empty(): return
	var source: StaticBody3D = stock[random.randi_range(0,stock.size()-1)]
	var record: Dictionary = cells[int(source.get_meta("boss_slot"))]
	# Parries protect the player. Projectiles are separate from the boss's
	# armor, so weak gear cannot win simply by waiting for it to throw itself away.
	game._add_ore_cell(record.data.duplicate(),int(record.layer))
	var chunk: StaticBody3D = game.chunks.back()
	chunk.position = source.position
	chunk.scale = source.scale*.55
	chunk.set_meta("boss_projectile",true)
	chunk.reparent(self)
	# Incoming stones take at most two ordinary strikes at the equipped power.
	chunk.max_health = minf(chunk.max_health,maxf(3.0,float(game.upgrade_stats.damage)*1.5))
	chunk.health = minf(chunk.health,chunk.max_health)
	var screen: Vector2 = game.get_viewport().get_visible_rect().size*Vector2(random.randf_range(.24,.74),random.randf_range(.30,.54))
	projectiles.append({"node":chunk,"start":chunk.global_position,"target":game.camera.project_position(screen,2.8),"age":0.0})
	audio.play(stage,"ability")

func _hurt_player(amount: float) -> void:
	# Damage uses the existing health/revival rules, independent of drain speed.
	var expired: bool = game.round_state.advance(amount/game.round_state.drain_rate)
	game.camera_shake = maxf(game.camera_shake,.18)
	game._skill_notice(game.get_viewport().get_visible_rect().size*Vector2(.5,.70),"−%s 스태미나" % Stamina.amount(amount),Color("ff947e"))
	audio.play(stage,"break",.65)
	if expired: _finish(false)

func _fatal_hit(chunk: StaticBody3D) -> void:
	var point: Vector3 = chunk.to_global(chunk.face_center)
	game._damage_chunk({"collider":chunk,"position":point,"normal":game.camera.global_basis.z},game.camera.unproject_position(point),{"secondary":true},chunk.health)

func check_victory() -> void:
	if not active or building: return
	if stage == 2 and weak_destroyed >= 5: _finish(true); return
	if not (_stock().is_empty() if stage == 5 else game.chunks.is_empty()): return
	for record in cells:
		if float(record.regen_at) >= 0: return
	_finish(true)

func time_drain_enabled() -> bool:
	# The defusal encounter has its own explicit sixty-second deadline.
	return stage != 3

func defeat() -> void:
	if active: _finish(false)

func _finish(victory: bool) -> void:
	if not active: return
	active = false
	building = false
	game.ore_building = false
	_pending_damage.clear()
	for record in cells: record.regen_at = -1.0
	for flight in projectiles:
		if is_instance_valid(flight.node): flight.node.collision_layer = 0
	if is_instance_valid(visual):
		for wire in visual.wires:
			if is_instance_valid(wire): wire.collision_layer = 0
	var reward: int = game.campaign.finish(victory)
	if victory:
		game.round_state.record_boss_reward(reward,info.title)
		for chunk in game.chunks:
			chunk.collision_layer = 0
			chunk.hide()
			chunk.queue_free()
		game.chunks.clear()
		game.effects.skill_burst(game.shell.global_position,game.camera.global_basis.z,info.accent,4.0)
		visual.body.hide()
		audio.play(stage,"victory")
	else: audio.play(stage,"entry",.60)
	game.round_state.phase = game.RoundModel.Phase.DRAINING
	game._set_boss_skill_rules(false)
	game._clear_upgrade_input()
	game.marker.hide()
	game.pickaxe.hide()
	game.auxiliary.pause_feedback()
	game.hud.set_boss_info({})
	game.hud.set_boss_result(info.title,victory,game.campaign.won,mini(game.campaign.cleared,6))
	game.hud.set_ore_progress(game._progress_status())

func _refresh_hud() -> void:
	if not active or not is_instance_valid(game.hud): return
	var health := 0.0
	for i in cells.size():
		var chunk := _body(i)
		if chunk != null: health += float(chunk.health)
		if stage == 0:
			var generation: int = cells[i].generation
			if cells[i].regen_at >= 0: health += float(info.health)*pow(.5,generation)
			for next in range(generation+1,3): health += float(info.health)*pow(.5,next)
	var status := "남은 조각 %d" % game.chunks.size()
	match stage:
		0: status += " · 재생 %d" % regen_count
		1: status += " · 보호석 %d" % guards.size()
		2: status = "약점 %d / 5" % weak_destroyed
		3: status = "폭발까지 %.1f초 · %s" % [bomb_remaining,"갑피 %d개 남음" % bomb_armor_remaining() if bomb_armor_remaining() > 0 else "정지" if bomb_pause > 0 else "×0.5" if bomb_slow > 0 else "×%.1f" % bomb_speed]
		4: status = "가시! 공격을 멈추세요" if spikes_out else "틈이 열렸습니다 · %.1f초" % spike_next
		5: status = "휴식 · 본체 공격 가능" if volley_rest else "포격 중 · 날아오는 돌을 쳐내세요"
	game.hud.set_boss_info({"active":true,"title":info.title,"hint":info.hint,"stage":stage,"status":"보스 준비 중" if building else status,"ratio":health/_total_health,"accent":info.accent,"danger":spikes_out or (stage == 3 and bomb_remaining < 10)})

func clear() -> void:
	active = false
	building = false
	if is_instance_valid(visual): visual.clear()
	visual = null
	for flight in projectiles:
		if is_instance_valid(flight.node): flight.node.collision_layer = 0; flight.node.queue_free()
	projectiles.clear()
	cells.clear()
	guards.clear()
	weak_slots.clear()
	_pending_damage.clear()
	wire_cut = [false,false,false]
	clock = 0
	weak_destroyed = 0
	weak_next = 2.6
	bomb_remaining = 60
	bomb_pause = 0
	bomb_speed = 1
	bomb_slow = 0
	spikes_out = false
	spike_next = 3.5
	volley_rest = false
	volley_timer = .8
	volley_shots = 0
	regen_count = 0
	parry_count = 0
	if is_instance_valid(game) and is_instance_valid(game.hud): game.hud.set_boss_info({})
