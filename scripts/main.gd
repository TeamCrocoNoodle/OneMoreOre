extends Node3D
## Timed mining, physical feedback, collected crystal flights, and round settlement.

const Geometry = preload("res://scripts/rock_geometry.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Pickaxe = preload("res://scripts/pickaxe.gd")
const MiningAudio = preload("res://scripts/mining_audio.gd")
const Effects = preload("res://scripts/mining_effects.gd")
const Gem = preload("res://scripts/gem.gd")
const GemLight = preload("res://scripts/gem_light.gd")
const RoundModel = preload("res://scripts/mining_round.gd")
const MiningHud = preload("res://scripts/mining_hud.gd")
const RewardAudio = preload("res://scripts/reward_audio.gd")
const GemFlightOverlay = preload("res://scripts/gem_flight_overlay.gd")
const SkillTreeModel = preload("res://scripts/skill_tree.gd")
const SkillTreeUI = preload("res://scripts/skill_tree_ui.gd")
const ModelGallery = preload("res://scripts/ui_model_gallery.gd")
const MiningSkills = preload("res://scripts/mining_skills.gd")
const AttackRange = preload("res://scripts/attack_range.gd")
const SkillBalance = preload("res://scripts/skill_balance.gd")
const MainTools = preload("res://scripts/main_tools.gd")
const AuxTools = preload("res://scripts/aux_tools.gd")
const AuxRuntime = preload("res://scripts/aux_runtime.gd")
const OreProgression = preload("res://scripts/ore_progression.gd")
const BossCampaign = preload("res://scripts/boss_campaign.gd")
const BossRuntime = preload("res://scripts/boss_runtime.gd")
const ROCK_RADIUS := 2.6
const LAYER_COUNT := 3
const LAYER_COUNTS := [38, 24, 12]
const COMMON_GEM_COUNT := 3
const SPECIAL_GEM_COUNT := 1
const SHOWCASE_RADIUS := 4.9
const SHOWCASE_LAYER_COUNTS := [100, 80, 60, 42, 26, 14]
const ORE_RESPAWN_DELAY := 0.10
const ORE_SPAWN_DURATION := 0.16
const OreBlast = preload("res://scripts/ore_blast.gd")
var _bulk_job: RefCounted
var _bulk_committing := false
var last_bulk_receipt: Dictionary = {}

func _advance_bulk_breaks() -> void:
	if _bulk_job == null or not focused: return
	_bulk_committing = true
	_bulk_job.advance(self,3000)
	_bulk_committing = false
	if _bulk_job.complete:
		last_bulk_receipt = _bulk_job.receipt
		_bulk_job = null
		_check_exhausted()

var camera := Camera3D.new()
var rock_motion := Node3D.new()
var shell := Node3D.new()
var effects := Effects.new()
var audio := MiningAudio.new()
var pickaxe := Pickaxe.new()
var gems: Array[StaticBody3D] = []
var collecting_gems: Array[Dictionary] = []
var marker := MeshInstance3D.new()
var attack_range := AttackRange.new()
var _attack_preview_chunks: Array[StaticBody3D] = []
var ground_shadow := MeshInstance3D.new()
var chunks: Array[StaticBody3D] = []
var hovered: StaticBody3D
var aim_position := Vector2.ZERO
var pending_aim := Vector2.ZERO
var mouse_down := false
var dragging := false
var touch_id := -1
var touch_start := Vector2.ZERO
var touch_rotating := false
var touch_time := 0.0
var using_controller := false
var controller_id := -1
var impact_pending := false
var swing_cooldown := 0.0
var idle_time := 0.0
var elapsed := 0.0
var camera_shake := 0.0
var hit_stop := 0.0
var wobble := Vector3.ZERO
var wobble_velocity := Vector3.ZERO
var squash := 0.0
var completion_time := -1.0
var rock_number := 0
var rock_seed := 0
var showcase_mode := false
var showcase_on_start := false
var active_rock_radius := ROCK_RADIUS
var ore_profile: Dictionary = OreProgression.profile(0)
var active_layer_counts: Array = LAYER_COUNTS.duplicate()
var showcase_covers: Array[StaticBody3D] = []
var light_pulse_history: Array[int] = []
var gems_collected_this_rock := 0
var special_collected_count := 0
var collected_by_rarity := Gem.Rarity.empty_counts()
var pending_rock_number := -1
var hit_count := 0
var broken_count := 0
var collected_count := 0
var focused := true
var camera_rest := Vector3(0, 2.0, 18.0)
var rng := RandomNumberGenerator.new()
var capture_mode := false
var capture_stage := 0
var capture_clock := 0.0
var capture_saved_tier := -1
var capture_impact_points: Array[Vector3] = []
var capture_fracture_center := Vector3.ZERO
var capture_fracture_count := 0
var capture_plain_count := 0
var capture_plain: StaticBody3D
var spawn_time := 1.0
var spawn_tween: Tween
var capture_gem: StaticBody3D
var capture_seed := 12873
var round_enabled := true
var round_state := RoundModel.new()
var hud: Node
var reward_audio: Node
var flight_overlay: Node
var displayed_gems := Gem.Rarity.empty_counts()
var _last_warning_second := 6
var _wait_for_mine_release := false
var _wait_for_navigation_release := false
var upgrades := SkillTreeModel.new()
var upgrade_stats: Dictionary = upgrades.stats()
var skill_ui: Node
var model_gallery: Node
var mining_skills := MiningSkills.new()
var _reactions: Array[Dictionary] = []
var main_tools := MainTools.new()
var aux_tools := AuxTools.new()
var auxiliary: Node3D
var _tool_impact_queue: Array[Dictionary] = []
var ore_building := false
var _ore_builder: RefCounted
var _ore_build_layer := 0
var _ore_gem_plan: Dictionary = {}
var _last_presented_ore_stage := 0
var campaign := BossCampaign.new()
var campaign_enabled := true
var boss: Node3D
var _pending_boss := false
var _ore_counted_number := -1
var backdrop_material: ShaderMaterial
const ORE_BUILD_BUDGET_USEC := 5000
const OrePreparation = preload("res://scripts/ore_preparation.gd")
var _ore_preparation := OrePreparation.new()
var _prepared_cells: Array[StaticBody3D] = []
var _visible_ore_depth := 0
var _ore_layers: Dictionary = {}
var _ore_collision_mask := 1
var _ore_bank_path := ""
var _ore_bank: Resource
var _ore_bank_cursor := 0
var _using_prepared_build := false
var _ore_grid: Dictionary = {}
const ORE_GRID_SIZE := 2.0
var _retired_chunks: Array[Node] = []
var _retired_ids: Dictionary = {}
var _retired_containers: Array[Node3D] = []
var _fracture_frame := -1
var _fractures_this_frame := 0
var _pending_damage_visuals: Array[WeakRef] = []
var _visual_work_frame := -1
var _visual_work_usec := 0

func _reset_visual_budget() -> void:
	var frame := Engine.get_process_frames()
	if _visual_work_frame != frame:
		_visual_work_frame = frame
		_visual_work_usec = 0

func _queue_damage_visual(body: StaticBody3D) -> void:
	if body.visual_update_queued or not body.visible or body.destroyed: return
	body.visual_update_queued = true
	_pending_damage_visuals.append(weakref(body))
	if _pending_damage_visuals.size() > 96:
		var previous = _pending_damage_visuals.pop_front().get_ref()
		if is_instance_valid(previous): previous.visual_update_queued = false

func _advance_damage_visuals() -> void:
	if _bulk_job != null: return
	_reset_visual_budget()
	var count := 0
	while not _pending_damage_visuals.is_empty() and _visual_work_usec < 3500 and count < 2:
		var chunk = _pending_damage_visuals.pop_back().get_ref()
		if not is_instance_valid(chunk): continue
		chunk.visual_update_queued = false
		if chunk.destroyed or not chunk.visible: continue
		var started := Time.get_ticks_usec()
		chunk.flush_damage_visuals()
		_visual_work_usec += Time.get_ticks_usec()-started
		count += 1

func _advance_ore_retirement() -> void:
	# queue_free() still destroys every queued mesh/body in one end-of-frame
	# flush. Retire already hidden, non-colliding stones in bounded slices.
	var deadline := Time.get_ticks_usec()+1200
	var count := 0
	while not _retired_chunks.is_empty() and count < 48 and Time.get_ticks_usec() < deadline:
		var chunk: Node = _retired_chunks.pop_back()
		if is_instance_valid(chunk):
			_retired_ids.erase(chunk.get_instance_id())
			chunk.free()
		count += 1
	for i in range(_retired_containers.size()-1,-1,-1):
		var container := _retired_containers[i]
		if not is_instance_valid(container): _retired_containers.remove_at(i)
		elif container.get_child_count() == 0:
			container.free()
			_retired_containers.remove_at(i)

func _retire_chunk(chunk: Node) -> void:
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return
	var id := chunk.get_instance_id()
	if _retired_ids.has(id): return
	_retired_ids[id] = true
	_retired_chunks.append(chunk)

func _retire_ore_container(container: Node3D) -> void:
	if container.has_meta("retiring"): return
	container.set_meta("retiring",true)
	container.hide()
	container.set_as_top_level(true)
	_retired_containers.append(container)
	# Containers outlive their individually retired children.
	for child in container.get_children():
		if child is CollisionObject3D: child.collision_layer = 0
		if child is Chunk: child.destroyed = true
		child.hide()
		child.set_process(false)
		_retire_chunk(child)

func _discard_ore_preparation() -> void:
	if is_instance_valid(_ore_preparation.root_node):
		_retire_ore_container(_ore_preparation.root_node)
		_ore_preparation.root_node = null
		_ore_preparation.chunks = []
		_ore_preparation.gems = []
	_ore_preparation.clear()

func _index_ore_chunk(chunk: StaticBody3D) -> void:
	var key := Vector3i((chunk.position/ORE_GRID_SIZE).floor())
	if not _ore_grid.has(key): _ore_grid[key] = []
	_ore_grid[key].append(chunk)
	if not _ore_layers.has(chunk.layer_index): _ore_layers[chunk.layer_index] = []
	_ore_layers[chunk.layer_index].append(chunk)

func _fracture_detail_available(body: StaticBody3D) -> bool:
	var frame := Engine.get_process_frames()
	if frame != _fracture_frame:
		_fracture_frame = frame
		_fractures_this_frame = 0
	# One primary break keeps the full crack-shaped fracture; simultaneous
	# secondary breaks share the existing solid-chip particle batches.
	if not body.visible or _fractures_this_frame >= 1: return false
	_fractures_this_frame += 1
	return true

func _exit_tree() -> void:
	_ore_preparation.clear()
	OrePreparation.Bank.shutdown()
	for chunk in _prepared_cells:
		if is_instance_valid(chunk): chunk.free()
	_prepared_cells.clear()
	_retired_chunks.clear()
	_retired_ids.clear()
	_retired_containers.clear()

func _advance_ore_preparation() -> void:
	if not focused or ore_building or showcase_mode or not round_enabled or campaign.won: return
	var stage := campaign.cleared if campaign_enabled else int(ore_profile.index)
	if is_instance_valid(boss) and boss.active: stage = mini(stage+1,6)
	var info := OreProgression.profile(round_state.lifetime_mining_gold,stage)
	if not _ore_preparation.matches(info,upgrade_stats):
		_discard_ore_preparation()
		OrePreparation.Bank.release_other_stages(stage)
		_ore_preparation.begin(info,int(rng.randi()),self,upgrade_stats)
	_ore_preparation.advance(1500,self)

func _reveal_ore_depth(depth: int, source: StaticBody3D = null) -> void:
	# Reveal the complete conservative sight cone behind an opening, rather
	# than drawing every buried cell around the far side of the entire sphere.
	# The tangent from the opening to an inner sphere bounds every possible
	# viewing direction, including side/back orbiting and the cell's full skirt.
	if showcase_mode or (is_instance_valid(boss) and boss.active): return
	_visible_ore_depth = maxi(_visible_ore_depth,depth)
	for chunk in _ore_layers.get(depth,[]):
		if not is_instance_valid(chunk) or chunk.destroyed or chunk.visible: continue
		if source != null:
			var angle: float = acos(clampf(chunk.occlusion_inner_radius/maxf(source.occlusion_outer_radius,.01),0,1))+source.occlusion_angle+chunk.occlusion_angle+.02
			if chunk.direction.dot(source.direction) < cos(minf(angle,PI)): continue
		chunk.show()
		if not chunk._pending_visual_hits.is_empty(): _queue_damage_visual(chunk)

func _ready() -> void:
	capture_mode = "--capture-sequence" in OS.get_cmdline_user_args()
	if capture_mode or showcase_on_start or "--mining-sandbox" in OS.get_cmdline_user_args():
		round_enabled = false
	rng.seed = capture_seed if capture_mode else int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	_create_actions()
	_create_stage()
	add_child(attack_range)
	add_child(audio)
	add_child(effects)
	add_child(rock_motion)
	rock_motion.add_child(shell)
	if capture_mode or showcase_on_start:
		_spawn_rock(capture_seed, true)
	else:
		_spawn_rock()
	add_child(pickaxe)
	pickaxe.setup(camera)
	pickaxe.impacted.connect(_on_pickaxe_impact)
	pickaxe.swing_started.connect(audio.play_swing)
	get_viewport().size_changed.connect(_resize)
	_resize()
	aim_position = get_viewport().get_visible_rect().size * Vector2(0.48, 0.46)
	if showcase_covers.size() == 6 and is_instance_valid(showcase_covers[5]):
		aim_position = camera.unproject_position(showcase_covers[5].to_global(showcase_covers[5].face_center))
	pickaxe.set_target(aim_position)
	if capture_mode:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	Input.joy_connection_changed.connect(_controller_connection)
	for device in Input.get_connected_joypads():
		controller_id = device
	if round_enabled:
		model_gallery = ModelGallery.new()
		add_child(model_gallery)
		reward_audio = RewardAudio.new()
		add_child(reward_audio)
		hud = MiningHud.new()
		hud.model_gallery = model_gallery
		add_child(hud)
		hud.next_round_requested.connect(_next_round)
		hud.settlement_animation_finished.connect(_finish_settlement)
		hud.cue.connect(reward_audio.play_cue)
		hud.upgrades_requested.connect(_open_upgrades)
		hud.auction_requested.connect(_start_auction)
		hud.auction_animation_finished.connect(_finish_auction)
		hud.begin_round(round_state.round_index, round_state.wallet_gold)
		flight_overlay = GemFlightOverlay.new()
		add_child(flight_overlay)
		flight_overlay.setup(camera)
		skill_ui = SkillTreeUI.new()
		skill_ui.model_gallery = model_gallery
		add_child(skill_ui)
		skill_ui.setup(upgrades)
		skill_ui.setup_tools(main_tools,aux_tools)
		skill_ui.purchase_requested.connect(_purchase_upgrade)
		skill_ui.tool_action_requested.connect(_tool_action)
		skill_ui.closed.connect(_close_upgrades)
		skill_ui.cue.connect(reward_audio.play_cue)
		auxiliary = AuxRuntime.new()
		add_child(auxiliary)
		boss = BossRuntime.new()
		add_child(boss)
		_apply_upgrade_stats()
		hud.set_ore_progress(_progress_status())
		hud.set_upgrades_available(true)
	_warm_gem_renderer.call_deferred()

func _warm_gem_renderer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Compatibility compiles rendering variants on their first actual draw.
	# Submit hidden gems and hit effects during startup in an offscreen world,
	# so the first hit/discovery does not have to do it. Real gems stay sealed.
	var warmup := SubViewport.new()
	warmup.name = "GemRenderWarmup"
	warmup.size = Vector2i(96, 96)
	warmup.msaa_3d = get_viewport().msaa_3d
	warmup.world_3d = World3D.new()
	warmup.world_3d.environment = get_world_3d().environment
	warmup.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(warmup)
	var warm_camera := Camera3D.new()
	warm_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	warm_camera.size = 4.0
	warm_camera.position = Vector3(0, 0, 5)
	warm_camera.current = true
	warmup.add_child(warm_camera)
	for child in get_children():
		if child is DirectionalLight3D:
			warmup.add_child(child.duplicate(0))
	for i in gems.size():
		var source: MeshInstance3D = gems[i].facets
		var proxy := MeshInstance3D.new()
		proxy.mesh = source.mesh
		proxy.material_override = source.material_override
		proxy.cast_shadow = source.cast_shadow
		proxy.position = Vector3((float(i % 3) - 1.0) * 1.15, 0.70 if i < 3 else -0.70, 0)
		warmup.add_child(proxy)
	if gems.is_empty():
		# A developer jump / immediate reset may replace the starter ore before
		# this deferred warmup. It must still submit the crystal shader safely.
		var standin := Gem.new()
		standin.configure(Gem.EXOTIC,0)
		warmup.add_child(standin)
	var warm_effects := Node3D.new()
	warm_effects.position.z = 1.2
	warmup.add_child(warm_effects)
	effects.append_render_warmup(warm_effects)
	if is_instance_valid(auxiliary): auxiliary.append_render_warmup(warm_effects)
	var warm_light := GemLight.new()
	warm_effects.add_child(warm_light)
	warm_light.position.z = 1.2
	warm_light.configure(PackedVector3Array(), Vector3.ZERO, Vector3.BACK, 0)
	var seam: Array[Dictionary] = [{"a": Vector3(-0.5, 0, 0), "b": Vector3(0.5, 0.1, 0), "width": 0.024}]
	warm_light.set_cracks(seam, Vector3.ZERO)
	warm_light.pulse(0, 0.5)
	warm_light.set_process(false)
	# The dark stone ribbon has a different unshaded, two-sided material.
	var dark_crack := MeshInstance3D.new()
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in [Vector3(-0.5, -0.02, 0), Vector3(0.5, -0.02, 0), Vector3(0.5, 0.02, 0)]:
		ribbon.set_normal(Vector3.BACK)
		ribbon.set_color(Color(0.12, 0.15, 0.16))
		ribbon.add_vertex(vertex)
	dark_crack.mesh = ribbon.commit()
	var dark_material := StandardMaterial3D.new()
	dark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark_material.vertex_color_use_as_albedo = true
	dark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	dark_material.disable_receive_shadows = true
	dark_crack.material_override = dark_material
	dark_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dark_crack.position = Vector3(0, -1.5, 1.2)
	warm_effects.add_child(dark_crack)
	await RenderingServer.frame_post_draw
	if is_instance_valid(warmup):
		warmup.queue_free()

func _create_actions() -> void:
	# Bind menu navigation explicitly, including script-driven launches where
	# Godot's built-in UI actions may contain keyboard events only.
	_bind_button("ui_accept", JOY_BUTTON_A)
	_bind_button("ui_cancel", JOY_BUTTON_B)
	_bind_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_bind_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_bind_button("ui_up", JOY_BUTTON_DPAD_UP)
	_bind_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_bind_axis("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("ui_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_key("mine", KEY_SPACE)
	_bind_button("mine", JOY_BUTTON_A)
	_bind_button("mine", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_axis("mine", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_key("orbit_left", KEY_A)
	_bind_key("orbit_left", KEY_LEFT)
	_bind_key("orbit_right", KEY_D)
	_bind_key("orbit_right", KEY_RIGHT)
	_bind_key("orbit_up", KEY_W)
	_bind_key("orbit_up", KEY_UP)
	_bind_key("orbit_down", KEY_S)
	_bind_key("orbit_down", KEY_DOWN)
	_bind_button("orbit_left", JOY_BUTTON_DPAD_LEFT)
	_bind_button("orbit_right", JOY_BUTTON_DPAD_RIGHT)
	_bind_button("orbit_up", JOY_BUTTON_DPAD_UP)
	_bind_button("orbit_down", JOY_BUTTON_DPAD_DOWN)
	_bind_axis("orbit_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("orbit_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("orbit_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("orbit_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)

func _action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)

func _bind_key(action: String, key: Key) -> void:
	_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func _bind_button(action: String, button: JoyButton) -> void:
	_action(action)
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	InputMap.action_add_event(action, event)

func _bind_axis(action: String, axis: JoyAxis, value: float) -> void:
	_action(action)
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)

func _create_stage() -> void:
	var backdrop := CanvasLayer.new()
	backdrop.layer = -10
	add_child(backdrop)
	var canvas := ColorRect.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_material = ShaderMaterial.new()
	backdrop_material.shader = preload("res://shaders/backdrop.gdshader")
	canvas.material = backdrop_material
	backdrop.add_child(canvas)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CANVAS
	settings.background_canvas_max_layer = -10
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("bad6e0")
	settings.ambient_light_energy = 0.40
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.tonemap_exposure = 1.0
	environment.environment = settings
	add_child(environment)
	add_child(camera)
	camera.position = camera_rest
	camera.look_at(Vector3(0, -0.08, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.near = 0.05
	camera.far = 60.0
	camera.current = true
	_light(Vector3(-42, -32, 0), Color("fff1d9"), 2.2, true)
	_light(Vector3(-18, 142, 0), Color("a1daef"), 0.30)
	_light(Vector3(35, 30, 0), Color("7394b0"), 0.18)
	var plane := QuadMesh.new()
	plane.size = Vector2(10.6, 1.8)
	ground_shadow.mesh = plane
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = preload("res://shaders/soft_shadow.gdshader")
	ground_shadow.material_override = shadow_material
	ground_shadow.rotation = camera.rotation
	ground_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground_shadow)
	var target_mesh := TorusMesh.new()
	target_mesh.inner_radius = 0.025
	target_mesh.outer_radius = 0.041
	target_mesh.rings = 16
	target_mesh.ring_segments = 4
	marker.mesh = target_mesh
	var target_material := StandardMaterial3D.new()
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_material.albedo_color = Color("fff0be")
	marker.material_override = target_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)

func _light(angles: Vector3, color: Color, energy: float, shadows: bool = false) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	# The fixed orthographic mining camera needs one shadow volume. Four
	# distance cascades redraw the same dense ore repeatedly without a useful
	# near/far detail transition in this scene.
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = 34.0
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 0.8
	add_child(light)

func _clear_ore_scene(preserve_collections: bool = false) -> void:
	_bulk_job = null
	_bulk_committing = false
	_clear_attack_preview()
	ore_building = false
	_ore_builder = null
	_ore_gem_plan.clear()
	for chunk in _prepared_cells:
		if is_instance_valid(chunk): chunk.free()
	_prepared_cells.clear()
	_visible_ore_depth = 0
	_ore_grid.clear()
	_ore_layers.clear()
	_pending_damage_visuals.clear()
	_ore_collision_mask = 1
	_ore_bank = null
	_ore_bank_path = ""
	_ore_bank_cursor = 0
	_using_prepared_build = false
	if is_instance_valid(hud): hud.set_ore_building(false,0)
	if is_instance_valid(auxiliary): auxiliary.clear_world()
	_tool_impact_queue.clear()
	pickaxe.cancel_swing()
	_reactions.clear()
	mining_skills.clear_target()
	effects.clear_fragments()
	for remnant in effects.get_children():
		if remnant.has_meta("gem_light_pulse") or remnant.get_script() == preload("res://scripts/gem_light.gd"):
			remnant.hide()
			remnant.queue_free()
	if spawn_tween != null and spawn_tween.is_valid():
		spawn_tween.kill()
	# Fast automatic transitions can finish before the last crystal's flight.
	# Collected models already belong to Main or the overlay, not this shell.
	if not preserve_collections:
		for extraction in collecting_gems:
			if round_enabled:
				_deliver_gem_to_hud(extraction)
			if is_instance_valid(extraction.node):
				extraction.node.queue_free()
		collecting_gems.clear()
	for child in shell.get_children():
		if child == _ore_preparation.root_node: continue
		if child.has_meta("ore_container"):
			_retire_ore_container(child)
			continue
		if child is CollisionObject3D:
			child.collision_layer = 0
		child.hide()
		child.set_process(false)
		_retire_chunk(child)
	chunks.clear()
	gems.clear()
	showcase_covers.clear()
	light_pulse_history.clear()

func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
	if is_instance_valid(boss) and boss.active: return
	if _try_spawn_boss(): return
	if is_instance_valid(boss): boss.clear()
	_clear_ore_scene(round_enabled and completion_time >= 0.0 and round_state.phase == RoundModel.Phase.MINING)
	shell.show()
	_set_stage_theme({})
	showcase_mode = showcase
	var cleared_bosses := campaign.cleared if campaign_enabled and round_enabled else -1
	ore_profile = OreProgression.profile(round_state.lifetime_mining_gold if round_enabled else 0,cleared_bosses)
	active_rock_radius = SHOWCASE_RADIUS if showcase else float(ore_profile.radius)
	hovered = null
	broken_count = 0
	gems_collected_this_rock = 0
	impact_pending = false
	rock_seed = seed_override if seed_override >= 0 else int(rng.randi())
	shell.rotation = Vector3(0.12, 0.24, -0.06)
	rock_motion.scale = Vector3.ONE
	rock_motion.position = Vector3.ZERO
	wobble = Vector3.ZERO
	wobble_velocity = Vector3.ZERO
	rock_motion.rotation = Vector3.ZERO
	squash = 0.0
	var layer_counts: Array = SHOWCASE_LAYER_COUNTS if showcase else ore_profile.layers
	active_layer_counts = layer_counts.duplicate()
	var stride: float = 0.78 if showcase else float(ore_profile.stride)
	var thickness: float = 0.86 if showcase else float(ore_profile.thickness)
	if not showcase and seed_override < 0 and is_instance_valid(_ore_preparation.root_node) and _ore_preparation.matches(ore_profile,upgrade_stats):
		if _ore_preparation.complete:
			_activate_prepared_ore()
		else:
			# A very fast clear must keep every already prepared stone. Finish the
			# same sealed ore at the foreground budget instead of restarting it.
			rock_seed = _ore_preparation.seed_value
			_using_prepared_build = true
			ore_building = true
			spawn_time = 0.0
			completion_time = -1.0
			if is_instance_valid(hud): hud.set_ore_building(true,float(_ore_preparation.chunks.size())/maxi(1,int(ore_profile.pieces)))
			_resize()
		return
	if not showcase and int(ore_profile.index) > 0:
		# Build larger ores across frames. They appear as they assemble, while
		# mining and the round clock wait until all hidden contents are sealed.
		ore_building = true
		_ore_build_layer = 0
		_ore_bank_path = OrePreparation.Bank.request(ore_profile,rock_seed)
		if _ore_bank_path.is_empty():
			_ore_builder = Geometry.LayerBuilder.new(active_rock_radius,0,rock_seed,active_layer_counts[0],thickness,ore_profile)
		spawn_time = 0.0
		completion_time = -1.0
		if is_instance_valid(hud): hud.set_ore_building(true,0)
		_resize()
		ground_shadow.position = Vector3(0,-active_rock_radius*1.092,-0.2)
		ground_shadow.scale = Vector3.ONE*(active_rock_radius/SHOWCASE_RADIUS)
		return
	for layer in range(layer_counts.size()):
		var radius := active_rock_radius - float(layer) * stride
		var cells: Array[Dictionary] = Geometry.build_layer(radius, layer, rock_seed, layer_counts[layer], thickness,{} if showcase else ore_profile)
		for data in cells:
			_add_ore_cell(data,layer)
	_place_gems(rock_seed)
	_complete_ore_spawn()

func _add_ore_cell(data: Dictionary, layer: int) -> void:
	var chunk: StaticBody3D
	if showcase_mode:
		chunk = Chunk.new()
		chunk.configure(data,layer)
		chunk.set_meta("stone_color",data.color)
		chunk.set_meta("outward",data.direction)
	else:
		chunk = OrePreparation.make_chunk(data,layer,ore_profile,round_enabled)
	shell.add_child(chunk)
	chunks.append(chunk)
	_index_ore_chunk(chunk)
	if not showcase_mode and not (is_instance_valid(boss) and boss.active) and layer > _visible_ore_depth: chunk.hide()

func _activate_prepared_ore() -> void:
	var prepared: Dictionary = _ore_preparation.activate()
	chunks = prepared.chunks
	gems = prepared.gems
	_ore_grid = prepared.grid
	_ore_layers = prepared.layers
	_ore_collision_mask = int(prepared.collision_bit)
	rock_seed = int(prepared.seed)
	_using_prepared_build = false
	ore_building = false
	if is_instance_valid(hud): hud.set_ore_building(false,1.0)
	_complete_ore_spawn(true)

func _advance_ore_build() -> void:
	if is_instance_valid(boss) and boss.building:
		boss.advance_build()
		return
	if not ore_building or not focused: return
	if _using_prepared_build:
		if not _ore_preparation.matches(ore_profile,upgrade_stats):
			_discard_ore_preparation()
			_ore_preparation.begin(ore_profile,rock_seed,self,upgrade_stats)
		_ore_preparation.advance(ORE_BUILD_BUDGET_USEC,self)
		if _ore_preparation.complete: _activate_prepared_ore()
		elif is_instance_valid(hud): hud.set_ore_building(true,float(_ore_preparation.chunks.size())/maxi(1,int(ore_profile.pieces)))
		return
	if not _ore_bank_path.is_empty() and _ore_bank == null:
		_ore_bank = OrePreparation.Bank.poll(_ore_bank_path)
		if _ore_bank == null: return
		if _ore_bank.signature != OrePreparation.Bank.profile_key(ore_profile):
			_ore_bank = null
			_ore_bank_path = ""
			_ore_builder = Geometry.LayerBuilder.new(active_rock_radius,0,rock_seed,active_layer_counts[0],ore_profile.thickness,ore_profile)
	var deadline := Time.get_ticks_usec()+ORE_BUILD_BUDGET_USEC
	while ore_building and Time.get_ticks_usec() < deadline:
		if not _prepared_cells.is_empty():
			var chunk: StaticBody3D = _prepared_cells.pop_back()
			shell.add_child(chunk)
			chunks.append(chunk)
			_index_ore_chunk(chunk)
			chunk.visible = chunk.layer_index <= _visible_ore_depth
		elif _ore_bank != null and _ore_bank_cursor < _ore_bank.cells.size():
			var data: Dictionary = _ore_bank.cell(_ore_bank_cursor)
			data.seed = rock_seed+_ore_bank_cursor*127+int(data.layer)*7919
			_ore_bank_cursor += 1
			_add_ore_cell(data,int(data.layer))
			if _ore_bank_cursor >= _ore_bank.cells.size(): _ore_build_layer = active_layer_counts.size()
		elif _ore_build_layer < active_layer_counts.size():
			if _ore_builder.cursor < _ore_builder.count:
				var data: Dictionary = _ore_builder.next_cell()
				if not data.is_empty(): _add_ore_cell(data,_ore_build_layer)
			else:
				_ore_build_layer += 1
				if _ore_build_layer < active_layer_counts.size():
					_ore_builder = Geometry.LayerBuilder.new(active_rock_radius-_ore_build_layer*float(ore_profile.stride),_ore_build_layer,rock_seed,active_layer_counts[_ore_build_layer],ore_profile.thickness,ore_profile)
		elif _ore_gem_plan.is_empty():
			_ore_gem_plan = _plan_gems(rock_seed)
		elif int(_ore_gem_plan.made) < _ore_gem_plan.grades.size():
			_create_planned_gem(_ore_gem_plan)
		elif int(_ore_gem_plan.placed) < gems.size():
			_contain_planned_gem(_ore_gem_plan)
		elif int(_ore_gem_plan.special_index) < chunks.size():
			var chunk: StaticBody3D = chunks[int(_ore_gem_plan.special_index)]
			_ore_gem_plan.special_index += 1
			_configure_special_stone(chunk,_ore_gem_plan.special_random)
			_apply_stone_health_reduction(chunk)
		else:
			ore_building = false
			_ore_builder = null
			_ore_gem_plan.clear()
			_complete_ore_spawn(true)
	if is_instance_valid(hud): hud.set_ore_building(ore_building,float(chunks.size())/maxi(1,int(ore_profile.pieces)))

func _complete_ore_spawn(assembled: bool = false) -> void:
	if not assembled and round_enabled and not showcase_mode:
		_place_special_stones(rock_seed)
		for chunk in chunks:
			_apply_stone_health_reduction(chunk)
	ground_shadow.position = Vector3(0, -active_rock_radius * 1.092, -0.2)
	ground_shadow.scale = Vector3.ONE * (active_rock_radius / SHOWCASE_RADIUS)
	_resize()
	rock_number += 1
	completion_time = -1.0
	if is_instance_valid(auxiliary): auxiliary.on_rock_changed()
	if int(ore_profile.index) > _last_presented_ore_stage and is_instance_valid(hud):
		_last_presented_ore_stage = ore_profile.index
		_skill_notice(get_viewport().get_visible_rect().size*Vector2(0.5,0.23),ore_profile.title+" 발견!",ore_profile.accent)
		reward_audio.play_cue("pickup",mini(5,int(ore_profile.index)))
	if rock_number > 1:
		audio.play_respawn()
		if assembled:
			spawn_time = ORE_SPAWN_DURATION
			return
		spawn_time = 0.0
		rock_motion.scale = Vector3.ONE * 0.01
		spawn_tween = create_tween()
		spawn_tween.tween_property(rock_motion, "scale", Vector3.ONE, ORE_SPAWN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _place_gems(seed_value: int) -> void:
	var plan := _plan_gems(seed_value)
	for i in plan.grades.size(): _create_planned_gem(plan)
	if showcase_mode:
		_place_showcase_gems()
		return
	for i in gems.size(): _contain_planned_gem(plan)

func _plan_gems(seed_value: int, info_override: Dictionary = {}, stats_override: Dictionary = {}) -> Dictionary:
	var info := ore_profile if info_override.is_empty() else info_override
	var values := upgrade_stats if stats_override.is_empty() else stats_override
	var showcase := showcase_mode and info_override.is_empty()
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = seed_value ^ 0x5F3759DF
	# The regular ore starts with four finds below the intact outside layer.
	# Shuffle their depths so the green gem does not have a predictable slot.
	var bands: Array[int] = []
	var grades: Array[int] = []
	if showcase:
		grades.assign([Gem.COMMON, Gem.SPECIAL, Gem.RARE, Gem.LEGENDARY, Gem.MYTHIC, Gem.ANCIENT])
	else:
		var loot := OreProgression.gem_plan(info,values if round_enabled else {},layout_rng)
		grades.assign(loot.grades)
		bands.assign(loot.bands)
	if not showcase:
		for i in grades.size(): grades[i] = mini(grades[i],int(info.rarity_cap) if not info_override.is_empty() else _max_gem_grade())
	for i in range(bands.size() - 1, 0, -1):
		var j := layout_rng.randi_range(0, i)
		var swap := bands[i]
		bands[i] = bands[j]
		bands[j] = swap
	var occupied: Array[StaticBody3D] = []
	var special_random := RandomNumberGenerator.new()
	special_random.seed = seed_value ^ 0x1E4F893
	return {"random":layout_rng,"grades":grades,"bands":bands,"made":0,"placed":0,"occupied":occupied,"special_index":0,"special_random":special_random}

func _create_planned_gem(plan: Dictionary, parent: Node3D = null, stats_override: Dictionary = {}) -> void:
	var values := upgrade_stats if stats_override.is_empty() else stats_override
	var destination: Node3D = shell if parent == null else parent
	var source_gems: Array = plan.get("gems",gems)
	var showcase := showcase_mode and parent == null
	var layout_rng: RandomNumberGenerator = plan.random
	var grades: Array[int] = plan.grades
	var i: int = plan.made
	plan.made += 1
	var jewel := Gem.new()
	var shape := i % 5 if showcase else layout_rng.randi_range(0, 5)
	jewel.configure(grades[i], shape)
	if round_enabled and not showcase and float(values.brilliant) > 0 and layout_rng.randf() < SkillBalance.value("brilliant_chance") + float(values.brilliant_chance_bonus):
		jewel.set_meta("value_multiplier", 1.0 + SkillBalance.value("brilliant_value") + float(values.brilliant_value_bonus))
		jewel.set_meta("brilliant", true)
	jewel.rotation = Vector3(layout_rng.randf_range(-0.5, 0.5), layout_rng.randf_range(-PI, PI), layout_rng.randf_range(-0.5, 0.5))
	destination.add_child(jewel)
	if ore_building or parent != null:
		jewel.hide()
		jewel.collision_layer = 0
	source_gems.append(jewel)

func _contain_planned_gem(plan: Dictionary) -> void:
	var source_gems: Array = plan.get("gems",gems)
	if not plan.has("chunks_by_layer"):
		plan["chunks_by_layer"] = {}
		for chunk in plan.get("chunks",chunks):
			if not plan.chunks_by_layer.has(chunk.layer_index): plan.chunks_by_layer[chunk.layer_index] = []
			plan.chunks_by_layer[chunk.layer_index].append(chunk)
	var layout_rng: RandomNumberGenerator = plan.random
	var bands: Array[int] = plan.bands
	var occupied: Array[StaticBody3D] = plan.occupied
	var i: int = plan.placed
	plan.placed += 1
	var candidates: Array[StaticBody3D] = []
	var largest_socket := 0.0
	var band: Array = plan.chunks_by_layer.get(bands[i],[])
	for chunk in band:
		if chunk.layer_index == bands[i] and not occupied.has(chunk):
			largest_socket = maxf(largest_socket, chunk.gem_socket_radius)
	for chunk in band:
		if chunk.layer_index == bands[i] and not occupied.has(chunk) and chunk.gem_socket_radius >= largest_socket * 0.72:
			candidates.append(chunk)
	assert(not candidates.is_empty(), "Every depth needs a solid stone that can contain a gem")
	# Prefer separated directions across depths as well as distinct hosts,
	# so one excavation tunnel is unlikely to reveal every find.
	var spaced: Array[StaticBody3D] = []
	for candidate in candidates:
		var separated := true
		for other in occupied:
			if Vector3(candidate.direction).dot(other.direction) > 0.80:
				separated = false
				break
		if separated:
			spaced.append(candidate)
	if not spaced.is_empty():
		candidates = spaced
	var host: StaticBody3D = candidates[layout_rng.randi_range(0, candidates.size() - 1)]
	var contained: bool = host.contain_gem(source_gems[i])
	assert(contained, "The selected stone must contain its gem")
	occupied.append(host)

func _place_special_stones(seed_value: int) -> void:
	var layout := RandomNumberGenerator.new()
	layout.seed = seed_value ^ 0x1E4F893
	for chunk in chunks:
		_configure_special_stone(chunk,layout)

func _apply_stone_health_reduction(chunk: StaticBody3D) -> void:
	if not chunk.is_gem_cover and int(upgrade_stats.stone_health_reduction) > 0:
		chunk.max_health = maxf(1.0,chunk.max_health-float(upgrade_stats.stone_health_reduction))
		chunk.health = chunk.max_health

func _configure_special_stone(chunk: StaticBody3D, layout: RandomNumberGenerator, stats_override: Dictionary = {}) -> void:
	var values := upgrade_stats if stats_override.is_empty() else stats_override
	if chunk.is_gem_cover: return
	var ticket := layout.randf()
	for kind: String in ["resonance", "healing", "bomb", "gold_stone"]:
		if float(values[kind]) <= 0:
			continue
		var chance := SkillBalance.value("special_spawn") + float(values[kind + "_chance_bonus"])
		if ticket < chance:
			chunk.configure_special(kind)
			chunk.set_meta("stone_color", chunk.stone_color)
			break
		ticket -= chance

func _place_showcase_gems() -> void:
	# Six front stones contain one gem each for testing all the light tiers.
	# Only an explicit debug/capture request uses this large visible-host layout.
	var slots := [Vector2(-0.42, 0.30), Vector2(0.0, 0.38), Vector2(0.42, 0.30), Vector2(-0.42, -0.28), Vector2(0.0, -0.38), Vector2(0.42, -0.28)]
	showcase_covers.resize(gems.size())
	var used: Array[StaticBody3D] = []
	# Place the larger red crystal first; it needs the widest face aperture.
	for i in range(gems.size() - 1, -1, -1):
		var jewel: StaticBody3D = gems[i]
		var slot: Vector2 = slots[i]
		var world_direction := (camera.global_basis.z + camera.global_basis.x * slot.x + camera.global_basis.y * slot.y).normalized()
		var local_direction := shell.basis.inverse() * world_direction
		var best: StaticBody3D
		var best_score := -INF
		for chunk in chunks:
			if chunk.layer_index != 0 or used.has(chunk):
				continue
			if _face_inradius(chunk) < jewel.bound_radius + 0.07:
				continue
			if chunk.gem_socket_radius <= 0.1:
				continue
			var score: float = chunk.direction.dot(local_direction)
			if score > best_score:
				best = chunk
				best_score = score
		assert(best != null, "No sufficiently wide stone cap for light showcase")
		if best == null:
			continue
		var contained: bool = best.contain_gem(jewel)
		assert(contained, "The showcase stone must contain its gem")
		showcase_covers[i] = best
		used.append(best)

func _face_inradius(chunk: StaticBody3D) -> float:
	var points: PackedVector3Array = chunk.face_points
	var radius := INF
	for i in range(points.size()):
		var a: Vector3 = points[i] - chunk.face_center
		var b: Vector3 = points[(i + 1) % points.size()] - chunk.face_center
		radius = minf(radius, a.cross(b).length() / maxf((b - a).length(), 0.00001))
	return radius

func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1)
	# KEEP_HEIGHT retains landscape composition; portrait increases height to fit the rock.
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var framing := 12.0 if showcase_mode else maxf(9.2,active_rock_radius*2.74)
	var width := 11.6 if showcase_mode else maxf(7.0,active_rock_radius*2.43)
	camera.size = maxf(framing, width / aspect)
	if aim_position != Vector2.ZERO:
		aim_position = aim_position.clamp(Vector2.ZERO, viewport_size)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if round_enabled and not _upgrade_window_open() and _aux_input(event):
		get_viewport().set_input_as_handled()
		return
	var upgrade_shortcut: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_U) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y)
	if upgrade_shortcut:
		if _upgrade_window_open():
			skill_ui.close_tree()
		else:
			_open_upgrades()
		get_viewport().set_input_as_handled()
		return
	if _upgrade_window_open():
		return
	if event.is_action_pressed("ui_accept") and get_viewport().gui_get_focus_owner() is BaseButton:
		return
	if round_enabled:
		if not _round_allows_mining():
			return
		if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventPanGesture:
			if _aim_over_hud(event.position):
				if not event is InputEventPanGesture:
					aim_position = event.position
					using_controller = false
				if event is InputEventMouseButton and not event.pressed:
					mouse_down = false
					dragging = false
				if event is InputEventScreenTouch and not event.pressed:
					touch_id = -1
					touch_rotating = false
				return
	if event is InputEventMouseMotion:
		using_controller = false
		aim_position = event.position
		if dragging:
			_orbit(event.relative * 0.007)
	elif event is InputEventMouseButton:
		using_controller = false
		aim_position = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_down = event.pressed
			if mouse_down:
				_request_swing()
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_orbit(Vector2(-0.14, 0))
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_orbit(Vector2(0.14, 0))
	elif event is InputEventPanGesture:
		_orbit(event.delta * 0.065)
	elif event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			touch_id = event.index
			touch_start = event.position
			aim_position = event.position
			touch_rotating = false
			touch_time = 0.0
			using_controller = false
		elif not event.pressed and event.index == touch_id:
			if not touch_rotating and touch_time < 0.18:
				_request_swing()
			touch_id = -1
			touch_rotating = false
	elif event is InputEventScreenDrag and event.index == touch_id:
		aim_position = event.position
		if event.position.distance_to(touch_start) > 14.0:
			touch_rotating = true
		if touch_rotating:
			_orbit(event.relative * 0.007)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadButton or absf(event.axis_value) > 0.22:
			using_controller = true
			controller_id = event.device
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			if not round_enabled: _reset_rock()
		elif event.physical_keycode == KEY_G:
			if not round_enabled:
				_spawn_rock(capture_seed, true)
	if event.is_action_pressed("mine"):
		_request_swing()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_attack_preview()
		focused = false
		mouse_down = false
		dragging = false
		touch_id = -1
		touch_rotating = false
		touch_time = 0.0
		if round_enabled:
			impact_pending = false
			pending_rock_number = -1
			_tool_impact_queue.clear()
			if is_instance_valid(pickaxe):
				pickaxe.cancel_swing()
			if is_instance_valid(auxiliary): auxiliary.pause_feedback()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func _controller_connection(device: int, connected: bool) -> void:
	if connected:
		controller_id = device
	elif controller_id == device:
		controller_id = -1
		using_controller = false

func _orbit(amount: Vector2) -> void:
	if completion_time >= 0.0 or not _round_allows_mining():
		return
	shell.quaternion = Quaternion(Vector3.UP, amount.x) * Quaternion(Vector3.RIGHT, amount.y) * shell.quaternion
	idle_time = 0.0

func _request_swing() -> void:
	if round_enabled and aux_tools.is_owned("detonator") and Input.is_physical_key_pressed(KEY_SPACE):
		return
	# Finish the previous cycle's deferred contacts before accepting another.
	# Even an unusually slow physics frame cannot accumulate unlimited bursts.
	if not _tool_impact_queue.is_empty():
		return
	if not _round_allows_mining() or _wait_for_mine_release or (not focused and not capture_mode) or completion_time >= 0.0 or spawn_time < ORE_SPAWN_DURATION or swing_cooldown > 0.0 or pickaxe.is_swinging or dragging or touch_rotating:
		return
	if _aim_over_hud(aim_position):
		return
	pending_aim = aim_position
	pending_rock_number = rock_number
	pickaxe.set_target(pending_aim)
	var contact := ray_at(pending_aim)
	if not contact.is_empty():
		_start_round()
		pickaxe.set_contact_point(contact.position)
	else:
		pickaxe.clear_contact_point()
	var speed := mining_skills.speed(round_state.remaining, round_state.duration) * (2.0 if mining_skills.extra_charges > 0 else 1.0) if round_enabled else 1.0
	pickaxe.speed_multiplier = speed
	pickaxe.swing()
	swing_cooldown = minf(0.30, pickaxe.get_cycle_duration()) / speed
	idle_time = 0.0

func _on_pickaxe_impact() -> void:
	# The tool follows the cursor during the swing. Mine where its tip struck,
	# while retaining the original rock number so a reset cannot inherit a hit.
	pending_aim = pickaxe.get_target_screen()
	_tool_impact_queue.append({"aim": pending_aim, "rock": pending_rock_number})
	impact_pending = true

func _process(delta: float) -> void:
	_advance_bulk_breaks()
	_advance_damage_visuals()
	_advance_ore_retirement()
	_advance_ore_build()
	_advance_ore_preparation()
	if _wait_for_mine_release and not Input.is_action_pressed("mine") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and touch_id < 0:
		_wait_for_mine_release = false
	elapsed += delta
	spawn_time += delta
	idle_time += delta
	swing_cooldown = maxf(0.0, swing_cooldown - delta)
	if touch_id >= 0:
		touch_time += delta
	if focused:
		var orbit := Input.get_vector("orbit_left", "orbit_right", "orbit_up", "orbit_down")
		var aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if _wait_for_navigation_release and orbit.length() <= 0.05 and aim.length() <= 0.05:
			_wait_for_navigation_release = false
		if orbit.length() > 0.05 and not _wait_for_navigation_release:
			_orbit(orbit * delta * 1.65)
		if using_controller and not _wait_for_navigation_release and not _upgrade_window_open():
			aim_position += aim * get_viewport().get_visible_rect().size.y * delta * 0.65
			aim_position = aim_position.clamp(Vector2.ONE * 30.0, get_viewport().get_visible_rect().size - Vector2.ONE * 30.0)
		if mouse_down or Input.is_action_pressed("mine") or (touch_id >= 0 and touch_time >= 0.18 and not touch_rotating):
			_request_swing()
	pickaxe.set_target(aim_position)
	hit_stop = maxf(0.0, hit_stop - delta)
	if hit_stop <= 0.0:
		wobble_velocity += (-wobble * 170.0 - wobble_velocity * 15.0) * delta
		wobble += wobble_velocity * delta
		rock_motion.rotation = wobble
		if completion_time < 0.0:
			rock_motion.position.y = sin(elapsed * 1.2) * 0.055
			if idle_time > 3.0 and _round_allows_mining():
				shell.rotate_y(delta * 0.055)
	squash = move_toward(squash, 0.0, delta * 0.5)
	if completion_time < 0.0 and spawn_time >= ORE_SPAWN_DURATION:
		rock_motion.scale = Vector3(1.0 + squash * 0.4, 1.0 - squash, 1.0 + squash * 0.4)
	camera_shake = move_toward(camera_shake, 0.0, delta * 0.8)
	camera.position = camera_rest + Vector3(sin(elapsed * 143.0), sin(elapsed * 117.0), 0) * camera_shake
	_update_collections(delta)
	if completion_time >= 0.0:
		completion_time += delta
		if completion_time >= ORE_RESPAWN_DELAY and _round_allows_mining():
			_spawn_rock()
	if round_enabled and is_instance_valid(hud):
		hud.set_skill_status(mining_skills.combo, mining_skills.combo_remaining, mining_skills.extra_charges, mining_skills.buff, mining_skills.buff_remaining, round_state.bonus_gold)
		hud.set_timer(round_state.seconds_remaining(), round_state.seconds_capacity(), round_state.phase != RoundModel.Phase.READY and focused and not ore_building)
		hud.set_upgrades_available(round_state.phase in [RoundModel.Phase.READY, RoundModel.Phase.COMPLETE] and not campaign.won and not _upgrade_window_open() and not hud.auction_ui.is_open)
		hud.set_auction_available(round_state.can_auction() and not _upgrade_window_open())
		if round_state.phase == RoundModel.Phase.DRAINING and collecting_gems.is_empty():
			_begin_settlement()
	if capture_mode:
		_capture_tick(delta)

func _physics_process(_delta: float) -> void:
	_advance_round(_delta)
	if is_instance_valid(boss): boss.advance(_delta)
	if is_instance_valid(auxiliary): auxiliary.advance(_delta)
	if not _round_allows_mining() or (round_enabled and not focused):
		impact_pending = false
		_tool_impact_queue.clear()
		pickaxe.cancel_swing()
		marker.hide()
		_clear_attack_preview()
		return
	if impact_pending:
		impact_pending = false
		var impact := {"aim": pending_aim, "rock": pending_rock_number}
		if not _tool_impact_queue.is_empty():
			impact = _tool_impact_queue.pop_front()
			impact_pending = not _tool_impact_queue.is_empty()
		if int(impact.rock) == rock_number:
			_mine_at(impact.aim)
	_drain_reactions()
	var result := {} if _aim_over_hud(aim_position) else ray_at(aim_position)
	pickaxe.set_target(aim_position)
	if result.is_empty():
		pickaxe.clear_contact_point()
	else:
		pickaxe.set_contact_point(result.position)
	var next_hover: StaticBody3D = result.get("collider") as StaticBody3D
	if next_hover != hovered:
		if is_instance_valid(hovered) and hovered.has_method("set_hovered"):
			hovered.set_hovered(false)
		hovered = next_hover
		if is_instance_valid(hovered) and hovered.has_method("set_hovered"):
			hovered.set_hovered(true)
	marker.visible = not result.is_empty() and completion_time < 0.0 and not dragging and touch_id < 0
	if marker.visible:
		marker.position = result.position + result.normal * 0.025
		marker.quaternion = Quaternion(Vector3.UP, result.normal.normalized())
	_update_attack_preview(result)

func _clear_attack_preview() -> void:
	attack_range.clear()
	for chunk in _attack_preview_chunks:
		if is_instance_valid(chunk):
			chunk.set_attack_preview(0.0)
	_attack_preview_chunks.clear()

func _update_attack_preview(primary: Dictionary) -> void:
	if not _round_allows_mining() or not focused or completion_time >= 0.0 or spawn_time < ORE_SPAWN_DURATION or dragging or touch_rotating or _aim_over_hud(aim_position):
		_clear_attack_preview()
		return
	var body: StaticBody3D = primary.get("collider") as StaticBody3D
	var radius := mining_skills.radius(round_state.spent) if round_enabled else 0.0
	if not is_instance_valid(body) or not chunks.has(body) or body.destroyed or radius <= 0.0:
		_clear_attack_preview()
		return
	attack_range.show_range(aim_position, _screen_attack_radius(radius, primary.position))
	# Preview the very same bounded surface samples used on impact. Never roll
	# a skill, damage a guard, or expose deeper chunks just to draw the preview.
	var targets: Array[StaticBody3D] = []
	if not is_instance_valid(boss) or boss.can_damage_chunk(body):
		targets.append(body)
	for contact in _area_targets(aim_position, primary):
		var chunk: StaticBody3D = contact.hit.collider
		if not is_instance_valid(boss) or boss.can_damage_chunk(chunk):
			targets.append(chunk)
	for previous in _attack_preview_chunks:
		if is_instance_valid(previous) and not targets.has(previous):
			previous.set_attack_preview(0.0)
	for chunk in targets:
		chunk.set_attack_preview(1.0 if chunk == body else 0.72)
	_attack_preview_chunks = targets

func _screen_attack_radius(radius: float, contact: Vector3) -> float:
	# Project actual world units: window stretch, portrait framing and the
	# camera's aspect policy must not change what the ring promises to hit.
	return camera.unproject_position(contact + camera.global_basis.x * radius).distance_to(camera.unproject_position(contact))

func ray_at(screen_position: Vector2) -> Dictionary:
	if _bulk_job != null and not _bulk_committing: return {}
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 40.0, _ore_collision_mask | 3)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _aim_over_hud(screen_position: Vector2) -> bool:
	return round_enabled and ((is_instance_valid(hud) and hud.is_pointer_blocked(screen_position)) or (is_instance_valid(auxiliary) and auxiliary.hud.is_pointer_blocked(screen_position)))

func _aux_input(event: InputEvent) -> bool:
	# Let settlement/auction buttons keep their normal Space/accept input.
	if not _round_allows_mining(): return false
	var id := ""
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: id = "crusher"
		if event.physical_keycode == KEY_SPACE and aux_tools.is_owned("detonator"): id = "detonator"
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_X: id = "crusher"
		if event.button_index == JOY_BUTTON_LEFT_STICK: id = "detonator"
		if not id.is_empty():
			using_controller = true
			controller_id = event.device
	if id.is_empty(): return false
	if is_instance_valid(auxiliary): auxiliary.activate(id)
	return true

func _mine_at(screen_position: Vector2) -> bool:
	if not _round_allows_mining() or (round_enabled and not focused) or completion_time >= 0.0 or spawn_time < ORE_SPAWN_DURATION:
		return false
	if _aim_over_hud(screen_position):
		return false
	var result := ray_at(screen_position)
	if result.is_empty():
		return false
	var body: StaticBody3D = result.collider
	if body.has_meta("splitting_pin") and is_instance_valid(auxiliary):
		return auxiliary.strike_pin(body)
	if body.has_meta("boss_wire") and is_instance_valid(boss):
		return boss.cut_wire(int(body.get_meta("boss_wire")))
	if gems.has(body):
		return _collect_gem(body)
	if not body.has_method("hit"):
		return false
	_start_round()
	# Resolve all surface contacts before breaking anything. A wide strike must
	# not drill through newly exposed layers or hit the same chunk twice.
	var surrounding := _area_targets(screen_position, result)
	var context := mining_skills.begin_attack(body.get_instance_id()) if round_enabled else {}
	context["count"] = surrounding.size() + 1
	context["reaction_marks"] = {}
	context["reaction_budget"] = {"used": 0}
	audio.begin_impact()
	_damage_chunk(result, screen_position, context)
	context["secondary_visual"] = true
	for contact: Dictionary in surrounding:
		_damage_chunk(contact.hit, contact.screen, context)
	if bool(context.get("shock", false)):
		var reach := mining_skills.radius(round_state.spent) * (SkillBalance.value("shock_range") + mining_skills.amount("shock_range_bonus"))
		var power := float(context.get("primary_damage", upgrade_stats.damage)) * (SkillBalance.value("shock_damage") + mining_skills.amount("shock_damage_bonus"))
		_queue_area(result.position, power, reach, context, [body])
		effects.skill_burst(result.position, result.normal, Color("87d9ef"), reach)
		_skill_notice(screen_position, "충격파", Color("87d9ef"))
	audio.end_impact()
	return true

func _area_targets(screen_position: Vector2, primary: Dictionary) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	var radius := mining_skills.radius(round_state.spent) if round_enabled else 0.0
	if radius <= 0.0 or primary.is_empty():
		return contacts
	var selected: Array = [primary.collider]
	var screen_radius := _screen_attack_radius(radius, primary.position)
	for ring: float in [0.60, 0.96]:
		for direction in 8:
			var sample := screen_position + Vector2.from_angle(TAU * float(direction) / 8.0) * screen_radius * ring
			if _aim_over_hud(sample):
				continue
			var hit := ray_at(sample)
			if hit.is_empty() or selected.has(hit.collider) or not chunks.has(hit.collider):
				continue
			if Vector3(hit.position).distance_to(primary.position) > radius:
				continue
			selected.append(hit.collider)
			contacts.append({"hit": hit, "screen": sample})
			if contacts.size() == 8:
				return contacts
	return contacts

func _damage_chunk(result: Dictionary, screen_position: Vector2, context: Dictionary = {}, damage_override: float = -1.0) -> void:
	var body: StaticBody3D = result.collider
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not chunks.has(body):
		return
	if is_instance_valid(boss) and boss.active and not boss.filter_hit(body,context): return
	if round_enabled and round_state.phase != RoundModel.Phase.MINING: return
	hit_count += 1
	var point: Vector3 = result.position
	var normal: Vector3 = result.normal
	var layer: int = body.layer_index
	var secondary_sound := bool(context.get("secondary", false))
	var color: Color = body.get_meta("stone_color")
	var placement: Transform3D = body.mesh_instance.global_transform
	var damage := float(upgrade_stats.damage) if round_enabled else 1.0
	var executed := false
	var critical := bool(context.get("critical", false)) and damage_override < 0
	if round_enabled and damage_override < 0:
		var modified := mining_skills.damage(context, body.get_instance_id(), body.impact_count == 0, body.is_gem_cover, body.health / body.max_health, int(context.get("count", 1)))
		damage = float(modified.damage)
		executed = bool(modified.execute) and not (is_instance_valid(boss) and boss.active)
	elif damage_override >= 0:
		damage = damage_override
	if not context.has("primary_damage"):
		context["primary_damage"] = damage
	var received := minf(damage, body.health)
	# Execution removes its target, but cannot turn the target's entire health
	# into shockwave or resonance damage. Boss resistance never rolls execution.
	if executed: damage = body.health
	var detailed_fracture: bool = damage >= body.health and _fracture_detail_available(body)
	var detail: bool = detailed_fracture or (damage < body.health and not bool(context.get("secondary",false)) and not bool(context.get("secondary_visual",false)))
	_reset_visual_budget()
	var hit_started := Time.get_ticks_usec()
	var broken: bool = body.hit(damage, point, detail)
	_visual_work_usec += Time.get_ticks_usec()-hit_started
	if not broken and not detail: _queue_damage_visual(body)
	if round_enabled:
		if executed or critical:
			_skill_notice(screen_position, "처형!" if executed else "치명타!", Color("ffba6b") if executed else Color("ffe39a"))
		var kind := str(body.get_meta("special_kind", ""))
		if kind == "resonance":
			_queue_special(body, point, received * (SkillBalance.value("resonance_damage") + mining_skills.amount("resonance_damage_bonus")), context)
		if broken:
			var reward := mining_skills.on_break(critical, executed)
			if kind == "healing":
				reward.heal += SkillBalance.value("healing_amount") * (1.0 + mining_skills.amount("healing_amount_bonus"))
			elif kind == "gold_stone":
				reward.gold += roundi(SkillBalance.value("gold_stone_amount") * (1.0 + mining_skills.amount("gold_stone_bonus")))
			elif kind == "bomb":
				_queue_special(body, point, mining_skills.bomb_damage(), context)
			_apply_skill_reward(reward, screen_position)
	var auto_collected := false
	if body.is_gem_cover and body.light_node != null:
		var tier: int = body.light_node.current_tier
		light_pulse_history.append(tier)
		if light_pulse_history.size() > 128:
			light_pulse_history.pop_front()
		if not broken:
			audio.play_resonance(tier, 1.0 - body.health / body.max_health, secondary_sound)
	effects.impact(point, normal, broken, color, body.is_gem_cover)
	if not broken and not body.is_gem_cover:
		if is_instance_valid(boss) and boss.active: boss.audio.play(boss.stage,"hit",1.0,secondary_sound)
		else: audio.play_hit(0.9, layer, secondary_sound)
	if broken:
		_reveal_ore_depth(body.layer_index+1,body)
		if round_enabled and not body.is_gem_cover and round_state.record_stone():
			hud.set_stones(round_state.ordinary_stones)
		body.set_process(false)
		if is_instance_valid(body.light_node):
			# Extinguish the fissures in this same impact. The light remains
			# owned by the stone and is freed with it, without a detached tail.
			body.light_node.clear()
		if body.cover_gem != null:
			var contained_gem: StaticBody3D = body.cover_gem.get_ref()
			if is_instance_valid(contained_gem) and contained_gem.is_embedded:
				# Emerge through the freshly struck opening, including side/back hits.
				var exit_point: Vector3 = point - camera.project_ray_normal(screen_position) * (contained_gem.bound_radius + 0.16)
				if contained_gem.release_from_chunk(self, to_local(exit_point)):
					auto_collected = _collect_gem(contained_gem, exit_point)
		# The discovery sound includes its own contact. Ordinary fractures,
		# or a failed gem release, still receive the stone destruction sound.
		if not auto_collected:
			if is_instance_valid(boss) and boss.active: boss.audio.play(boss.stage,"break",1.0,secondary_sound)
			else: audio.play_break(layer, secondary_sound)
		var fracture_started := Time.get_ticks_usec() if capture_mode else 0
		var fragments: Array[Dictionary] = []
		if detailed_fracture: fragments = body.build_fracture_fragments()
		if not fragments.is_empty(): effects.shed_fragments(fragments, body.mesh_instance.material_override, placement, normal, point)
		if capture_mode:
			print("FRACTURE_CAPTURE pieces=", fragments.size(), " build_and_spawn_ms=", float(Time.get_ticks_usec() - fracture_started) / 1000.0)
			capture_fracture_center = placement * body.face_center
			if body == capture_plain:
				capture_plain_count = fragments.size()
				_capture_fracture_motion("fracture_plain")
			elif capture_stage == 4:
				capture_fracture_count = fragments.size()
				_capture_fracture_motion("fracture_gem")
		chunks.erase(body)
		if is_instance_valid(boss) and boss.active: boss.on_chunk_broken(body)
		_retire_chunk(body)
		broken_count += 1
		_check_exhausted()
	camera_shake = maxf(camera_shake, 0.075 if broken else 0.035)
	hit_stop = 0.055 if broken else 0.025
	squash = 0.045 if broken else 0.022
	wobble_velocity += Vector3(normal.y * 0.8, -normal.x * 0.7, -normal.x * 0.6) + Vector3(0.3, 0.1, -0.12)
	if controller_id >= 0 and using_controller and not auto_collected:
		Input.start_joy_vibration(controller_id, 0.28 if broken else 0.1, 0.52 if broken else 0.25, 0.10 if broken else 0.055)

func _collect_gem(jewel: StaticBody3D, discovery_position: Vector3 = Vector3.INF, recovery: float = 1.0, bulk: bool = false) -> bool:
	if not _round_allows_mining() or not gems.has(jewel) or not jewel.begin_collection():
		return false
	_start_round()
	if round_enabled:
		round_state.record_gem(jewel.grade, float(jewel.get_meta("value_multiplier", 1.0)),recovery)
		_apply_skill_reward(mining_skills.on_gem(), camera.unproject_position(jewel.global_position))
		if jewel.get_meta("brilliant", false):
			_skill_notice(camera.unproject_position(jewel.global_position), "찬란함!", Color("fff0b1"))
	var special: bool = jewel.grade >= Gem.SPECIAL
	var location := jewel.global_position
	gems.erase(jewel)
	gems_collected_this_rock += 1
	collected_count += 1
	collected_by_rarity[jewel.grade] += 1
	# Retain the aggregate enhanced-reward count; rarity totals remain exact.
	if special:
		special_collected_count += 1
	if not bulk:
		audio.play_discovery(special, jewel.variant)
		effects.gem_burst(discovery_position if discovery_position.is_finite() else location, special, jewel.light_tier)
		camera_shake = 0.10 if special else 0.045
	if jewel.get_parent() != self:
		jewel.reparent(self)
	collecting_gems.append({"node": jewel, "start": jewel.position, "age": 0.0, "life": 0.70 if round_enabled else (1.65 if special else 1.15), "special": special, "emerging": jewel.is_emerging,
		"tier": jewel.grade, "delivered": false, "flight_started": false})
	hovered = null
	if controller_id >= 0 and using_controller and not bulk:
		Input.start_joy_vibration(controller_id, 0.45 if special else 0.2, 0.65 if special else 0.35, 0.18 if special else 0.10)
	_check_exhausted()
	return true

func _skill_notice(screen: Vector2, message: String, color: Color) -> void:
	if is_instance_valid(hud):
		hud.skill_notice(screen, message, color)

func remove_with_auxiliary(targets: Array, recovery: float = 1.0, crush: bool = false, damage_limit: float = -1.0) -> Dictionary:
	# Small extractions finish immediately; extreme batches commit across frames.
	# A whole ore never builds thousands of fracture meshes at once.
	if not _round_allows_mining() or not focused or targets.is_empty():
		return {}
	_start_round()
	if is_instance_valid(boss) and boss.active:
		if crush: return {}
		var before := chunks.size()
		audio.begin_impact(true)
		for target in targets:
			if not is_instance_valid(target) or not chunks.has(target) or not boss.active: continue
			var point: Vector3 = target.to_global(target.face_center)
			_damage_chunk({"collider":target,"position":point,"normal":camera.global_basis.z},camera.unproject_position(point),{"secondary":true},SkillBalance.Balance.boss_aux_damage(float(upgrade_stats.damage),target.max_health))
		audio.end_impact()
		return {"removed":before-chunks.size(),"gems":0}
	_tool_impact_queue.clear()
	impact_pending = false
	pickaxe.cancel_swing()
	_reactions.clear()
	var job := OreBlast.new()
	job.begin(self,targets,recovery,crush,damage_limit)
	if targets.size() > 256:
		_bulk_job = job
		return {"pending":true,"stones":0,"gems":0}
	job.advance(self,1000000000)
	_check_exhausted()
	return job.receipt


func _apply_skill_reward(reward: Dictionary, screen: Vector2) -> void:
	var gold := int(reward.get("gold", 0))
	if round_state.record_bonus_gold(gold):
		_skill_notice(screen, "+%d G" % gold, Color("efd08d"))
		reward_audio.play_cue("tick", 0)
	var restored := round_state.recover(float(reward.get("heal", 0.0)))
	if restored > 0:
		_skill_notice(screen + Vector2(0, 23), "+%s 체력" % snappedf(restored, 0.1), Color("a7efc0"))
		if round_state.seconds_remaining() > 5.0:
			_last_warning_second = 6
		reward_audio.play_cue("confirm", 0)

func _queue_special(source: StaticBody3D, point: Vector3, damage: float, context: Dictionary) -> void:
	if not context.has("reaction_marks"):
		context["reaction_marks"] = {}
	if not context.has("reaction_budget"):
		context["reaction_budget"] = {"used": 0}
	var marks: Dictionary = context.reaction_marks
	var id := source.get_instance_id()
	if marks.has(id):
		return
	marks[id] = true
	if int(context.reaction_budget.used) >= 96 or _reactions.size() >= 256: return
	_queue_area(source.global_position, damage, SkillBalance.value("neighbor_radius"), context, [source])
	var color := Color("9fddea") if source.get_meta("special_kind") == "resonance" else Color("f3a76b")
	effects.skill_burst(point, (source.global_basis * source.direction).normalized(), color, SkillBalance.value("neighbor_radius"))

func _queue_area(point: Vector3, damage: float, radius: float, context: Dictionary, excluded: Array) -> void:
	if damage <= 0.0:
		return
	var budget: Dictionary = context.reaction_budget
	if int(budget.used) >= 96 or _reactions.size() >= 256: return
	var nearby: Array[Dictionary] = []
	var candidates: Array = chunks
	if chunks.size() > 256 and not _ore_grid.is_empty() and not (is_instance_valid(boss) and boss.active):
		candidates = []
		var local := shell.to_local(point)
		var reach := radius*shell.global_basis.inverse().get_scale().length()
		var low := Vector3i(((local-Vector3.ONE*reach)/ORE_GRID_SIZE).floor())
		var high := Vector3i(((local+Vector3.ONE*reach)/ORE_GRID_SIZE).floor())
		for x in range(low.x,high.x+1):
			for y in range(low.y,high.y+1):
				for z in range(low.z,high.z+1): candidates.append_array(_ore_grid.get(Vector3i(x,y,z),[]))
	for target in candidates:
		if not is_instance_valid(target): continue
		if excluded.has(target) or target.destroyed or target.is_queued_for_deletion():
			continue
		var distance: float = target.global_position.distance_to(point)
		if distance <= radius:
			nearby.append({"target": target, "distance": distance})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	for entry in nearby:
		if int(budget.used) >= 96 or _reactions.size() >= 256:
			break
		budget.used += 1
		_reactions.append({"target": weakref(entry.target), "damage": damage, "rock": rock_number,
			"context": {"secondary": true, "reaction_marks": context.reaction_marks, "reaction_budget": budget}})

func _drain_reactions() -> void:
	# One source can propagate once per original attack. At most three reactions
	# are resolved per physics frame, including all existing fracture/VFX work.
	if round_enabled and round_state.phase != RoundModel.Phase.MINING:
		_reactions.clear()
		return
	audio.begin_impact(true)
	for i in 3:
		if _reactions.is_empty():
			break
		var reaction: Dictionary = _reactions.pop_front()
		var target: StaticBody3D = reaction.target.get_ref()
		if not is_instance_valid(target) or target.destroyed or reaction.rock != rock_number or not chunks.has(target):
			continue
		var point: Vector3 = target.to_global(target.face_center)
		_damage_chunk({"collider": target, "position": point, "normal": (target.global_basis * target.direction).normalized()}, camera.unproject_position(point), reaction.context, float(reaction.damage))
	audio.end_impact()

func _update_collections(delta: float) -> void:
	for i in range(collecting_gems.size() - 1, -1, -1):
		var extraction: Dictionary = collecting_gems[i]
		var jewel: StaticBody3D = extraction.node
		# The award has already happened. Let the presentation finish before
		# moving this non-interactive visual into its collection flight.
		if jewel.is_emerging:
			continue
		if round_enabled:
			_update_gem_flight(extraction, delta)
			if bool(extraction.delivered):
				jewel.queue_free()
				collecting_gems.remove_at(i)
			continue
		if extraction.emerging:
			extraction.emerging = false
			extraction.start = jewel.position
		extraction.age += delta
		if extraction.age >= extraction.life:
			jewel.queue_free()
			collecting_gems.remove_at(i)
			continue
		var age: float = extraction.age
		var approach := smoothstep(0.0, 0.24, age)
		jewel.position = extraction.start + camera.global_basis.z * approach * 2.2 + Vector3.UP * age * 1.1
		jewel.rotation.y += delta * 2.4
		var grow := 1.0 + sin(minf(age / 0.45, 1.0) * PI) * 0.35
		var shrink := 1.0 - smoothstep(extraction.life - 0.35, extraction.life, age)
		jewel.scale = Vector3.ONE * maxf(0.001, grow * shrink)

func _check_exhausted() -> void:
	if is_instance_valid(boss) and boss.active:
		boss.check_victory()
		return
	# A find never removes unmined stone. Both excavation and collection must finish.
	if not ore_building and completion_time < 0.0 and chunks.is_empty() and gems.is_empty():
		completion_time = 0.0
		marker.hide()
		_clear_attack_preview()
		if round_enabled and campaign_enabled and round_state.phase == RoundModel.Phase.MINING and _ore_counted_number != rock_number:
			_ore_counted_number = rock_number
			campaign.record_ore(int(ore_profile.index))
			_pending_boss = campaign.eligible(int(ore_profile.index))
			hud.set_ore_progress(_progress_status())

func _reset_rock() -> void:
	if _round_allows_mining():
		_spawn_rock()

func _upgrade_window_open() -> bool:
	return is_instance_valid(skill_ui) and bool(skill_ui.is_open)

func _open_upgrades() -> void:
	if not round_enabled or campaign.won or not focused or _upgrade_window_open() or not is_instance_valid(skill_ui):
		return
	if round_state.phase not in [RoundModel.Phase.READY, RoundModel.Phase.COMPLETE]:
		return
	if hud.auction_ui.is_open:
		return
	_clear_upgrade_input()
	pickaxe.hide()
	marker.hide()
	if is_instance_valid(hovered):
		hovered.set_hovered(false)
	hovered = null
	hud.set_upgrades_available(false)
	skill_ui.open_tree(round_state.wallet_gold)

func _clear_upgrade_input() -> void:
	_clear_attack_preview()
	_tool_impact_queue.clear()
	mouse_down = false
	dragging = false
	touch_id = -1
	touch_rotating = false
	touch_time = 0.0
	impact_pending = false
	pending_rock_number = -1
	_wait_for_mine_release = true
	_wait_for_navigation_release = true
	pickaxe.cancel_swing()

func _close_upgrades() -> void:
	_clear_upgrade_input()
	if round_state.phase == RoundModel.Phase.READY:
		pickaxe.show()
	hud.set_wallet(round_state.wallet_gold)
	hud.set_upgrades_available(round_state.phase in [RoundModel.Phase.READY, RoundModel.Phase.COMPLETE])
	hud.restore_round_focus()

func _purchase_upgrade(node_id: String) -> bool:
	if not round_enabled or not _upgrade_window_open() or round_state.phase not in [RoundModel.Phase.READY, RoundModel.Phase.COMPLETE]:
		return false
	if skill_ui.selected_tab != "skills":
		return false
	var result: Dictionary = upgrades.purchase(node_id, round_state.wallet_gold)
	if not bool(result.ok):
		skill_ui.refresh(round_state.wallet_gold)
		return false
	round_state.wallet_gold = int(result.gold)
	_apply_upgrade_stats()
	if round_state.phase == RoundModel.Phase.READY and (upgrades.get_node(node_id).category == "ore" or node_id.begins_with("brilliant")):
		# This ore has not been touched yet. Apply its new composition now.
		_spawn_rock(rock_seed)
	hud.set_wallet(round_state.wallet_gold)
	skill_ui.refresh(round_state.wallet_gold)
	hud.set_auction_available(round_state.can_auction())
	return true

func _apply_upgrade_stats() -> void:
	upgrade_stats = aux_tools.apply_to(main_tools.apply_to(upgrades.stats()))
	mining_skills.configure(upgrade_stats)
	round_state.apply_stats(upgrade_stats)
	pickaxe.set_tool(main_tools.equipped)
	audio.set_tool(main_tools.equipped)
	pickaxe.speed_multiplier = float(upgrade_stats.attack_speed)
	if is_instance_valid(auxiliary): auxiliary.configure()
	if is_instance_valid(hud):
		hud.set_timer(round_state.seconds_remaining(), round_state.seconds_capacity(), round_state.phase != RoundModel.Phase.READY and focused and not ore_building)

func _tool_action(id: String) -> bool:
	if not round_enabled or not _upgrade_window_open() or skill_ui.selected_tab != "tools" or round_state.phase not in [RoundModel.Phase.READY, RoundModel.Phase.COMPLETE]:
		return false
	var changed := false
	if not AuxTools.definition(id).is_empty():
		var result := aux_tools.acquire(id,round_state.wallet_gold)
		changed = bool(result.ok)
		if changed:
			round_state.wallet_gold = int(result.gold)
			if is_instance_valid(auxiliary): auxiliary.acquired(id)
	elif main_tools.is_owned(id):
		changed = main_tools.equip(id)
	else:
		var result := main_tools.acquire(id, round_state.wallet_gold)
		changed = bool(result.ok)
		if changed:
			round_state.wallet_gold = int(result.gold)
	if changed:
		_clear_upgrade_input()
		_apply_upgrade_stats()
		hud.set_wallet(round_state.wallet_gold)
		hud.set_auction_available(round_state.can_auction())
		reward_audio.play_cue("pickup", 3)
	skill_ui.refresh(round_state.wallet_gold)
	return changed

func _round_allows_mining() -> bool:
	return (_bulk_job == null or _bulk_committing) and not ore_building and not (campaign_enabled and campaign.won) and (not round_enabled or (not _upgrade_window_open() and round_state.phase in [RoundModel.Phase.READY, RoundModel.Phase.MINING]))

func _start_round() -> void:
	if round_enabled:
		round_state.start()

func _advance_round(delta: float) -> void:
	if not round_enabled or not focused or ore_building or _bulk_job != null:
		return
	if round_state.phase == RoundModel.Phase.MINING:
		mining_skills.advance(delta)
	var drains: bool = not is_instance_valid(boss) or not boss.active or boss.time_drain_enabled()
	if round_state.advance(delta if drains else 0.0):
		_clear_attack_preview()
		if is_instance_valid(boss) and boss.active: boss.defeat()
		_tool_impact_queue.clear()
		pickaxe.cancel_swing()
		mouse_down = false
		dragging = false
		touch_id = -1
		touch_rotating = false
		impact_pending = false
		pending_rock_number = -1
		marker.hide()
		pickaxe.hide()
		if is_instance_valid(hovered):
			hovered.set_hovered(false)
		hovered = null
		reward_audio.play_cue("timeout", 0)
	elif round_state.phase == RoundModel.Phase.MINING:
		if round_state.last_advance_revives > 0:
			_last_warning_second = 6
			_skill_notice(get_viewport().get_visible_rect().size * Vector2(0.5, 0.30), "부활!", Color("a7efc0"))
			reward_audio.play_cue("total", 0)
		var second := ceili(round_state.seconds_remaining())
		if second >= 1 and second <= 5 and second != _last_warning_second:
			_last_warning_second = second
			reward_audio.play_cue("countdown", 5 - second)

func _update_gem_flight(extraction: Dictionary, delta: float) -> void:
	var jewel: StaticBody3D = extraction.node
	var viewport_size := get_viewport().get_visible_rect().size
	if not extraction.flight_started:
		extraction.flight_started = true
		extraction["start_uv"] = camera.unproject_position(jewel.global_position) / viewport_size
		extraction["start_rotation"] = jewel.quaternion
		extraction["start_scale"] = jewel.scale
		extraction.age = 0.0
		flight_overlay.adopt(jewel)
	extraction.age += delta
	var progress := clampf(float(extraction.age) / float(extraction.life), 0.0, 1.0)
	var travel := smoothstep(0.0, 1.0, progress)
	var start: Vector2 = extraction.start_uv * viewport_size
	var target: Vector2 = hud.gem_target_screen(int(extraction.tier))
	var screen := start.lerp(target, travel) + Vector2(0, -viewport_size.y * 0.12) * sin(progress * PI)
	# Move the actual discovered model in front of the scene on its journey.
	# Orthographic projection preserves its on-screen size at this handoff.
	jewel.global_position = camera.project_position(screen, 3.0)
	var target_scale: float = hud.gem_target_diameter_screen() * camera.size / maxf(viewport_size.y * jewel.bound_radius * 2.0, 1.0)
	jewel.scale = Vector3(extraction.start_scale).lerp(Vector3.ONE * target_scale, travel)
	jewel.quaternion = Quaternion(extraction.start_rotation) * Quaternion(Vector3.BACK, sin(progress * PI) * 0.45)
	if progress >= 1.0:
		_deliver_gem_to_hud(extraction)

func _deliver_gem_to_hud(extraction: Dictionary) -> void:
	if bool(extraction.get("delivered", false)):
		return
	extraction["delivered"] = true
	if is_instance_valid(flight_overlay) and is_instance_valid(extraction.node):
		flight_overlay.release(extraction.node)
	var tier := int(extraction.tier)
	displayed_gems[tier] += 1
	if is_instance_valid(hud):
		hud.pulse_gem(tier, displayed_gems[tier])

func _begin_settlement() -> void:
	if not round_enabled or round_state.phase != RoundModel.Phase.DRAINING or not collecting_gems.is_empty():
		return
	# Flights are only presentation. The report always uses break-time cargo.
	hud.set_gem_counts(round_state.gem_counts)
	hud.show_settlement(round_state.begin_settlement())

func _finish_settlement() -> void:
	var previous_stage := int(ore_profile.index)
	if round_enabled and round_state.commit_settlement():
		hud.set_wallet(round_state.wallet_gold)
		hud.set_auction_available(round_state.can_auction())
		var progress := _progress_status()
		hud.set_ore_progress(progress,progress.index > previous_stage)
		if campaign.last_result == "victory" and not campaign.won: _open_upgrades.call_deferred()


func _start_auction() -> void:
	if not round_enabled or campaign.won or _upgrade_window_open() or not hud.auction_ui.is_open or hud.auction_ui.mode != hud.auction_ui.Mode.PREVIEW:
		return
	var result: Dictionary = round_state.begin_auction()
	if result.is_empty():
		return
	_clear_upgrade_input()
	hud.set_upgrades_available(false)
	hud.auction_ui.play_result(result)


func _finish_auction() -> void:
	if round_enabled and round_state.commit_auction():
		hud.apply_auction_result(round_state.last_report)

func _next_round() -> void:
	if not round_enabled or campaign.won or hud.auction_ui.is_open or not round_state.new_round():
		return
	campaign.new_round()
	_pending_boss = false
	if is_instance_valid(boss): boss.clear()
	_apply_upgrade_stats()
	mining_skills.reset_round()
	if is_instance_valid(auxiliary): auxiliary.reset_round()
	mouse_down = false
	dragging = false
	touch_id = -1
	touch_rotating = false
	impact_pending = false
	pending_rock_number = -1
	_wait_for_mine_release = true
	_last_warning_second = 6
	displayed_gems.fill(0)
	_spawn_rock()
	pickaxe.show()
	hud.begin_round(round_state.round_index, round_state.wallet_gold)
	hud.set_timer(round_state.seconds_remaining(), round_state.seconds_capacity(), false)
	hud.set_ore_progress(_progress_status())

func _capture_tick(delta: float) -> void:
	# Move between three parts of one cap while demonstrating all six colors.
	capture_clock += delta
	idle_time = 0.0
	if capture_stage == 0 and capture_clock > 1.1:
		_capture("lights_00_intact")
		capture_gem = gems[5]
		if not capture_gem.is_embedded or capture_gem.visible or capture_gem.collision_layer != 0 or capture_gem.get_parent() != showcase_covers[5].mesh_instance:
			push_error("Capture gem must start sealed inside its owning stone")
			get_tree().quit(1)
			return
		capture_stage = 1
		capture_clock = 0.0
	elif capture_stage == 1 and capture_clock > 0.60:
		var cap: StaticBody3D = showcase_covers[5]
		if cap.impact_count >= 1 and cap.impact_count <= 3:
			_capture("impacts_%02d_settled_cracks" % cap.impact_count)
		aim_position = _capture_cap_target(cap)
		_request_swing()
		capture_stage = 2
		capture_clock = 0.0
	elif capture_stage == 2 and capture_clock > 0.30:
		var cap: StaticBody3D = showcase_covers[5]
		var tier: int = cap.get_revealed_tier()
		if cap.impact_count >= 1 and cap.impact_count <= 3:
			_capture("impacts_%02d_light" % cap.impact_count)
			capture_impact_points.append(cap.latest_impact_local)
		if tier > capture_saved_tier:
			_capture("lights_%02d_%s" % [tier + 1, Gem.LIGHT_NAMES[tier]])
			capture_saved_tier = tier
		capture_stage = 3 if cap.health <= 1.0 else 1
		capture_clock = 0.0
	elif capture_stage == 3 and capture_clock > 0.85:
		var cap: StaticBody3D = showcase_covers[5]
		capture_fracture_center = cap.mesh_instance.to_global(cap.face_center)
		_capture("fracture_gem_00_before")
		aim_position = _capture_cap_target(cap)
		_request_swing()
		capture_stage = 4
		capture_clock = 0.0
	elif capture_stage == 4 and capture_clock > 0.30:
		_capture("lights_07_cap_break")
		if not capture_gem.collected or capture_gem.is_embedded or capture_gem.get_parent() != self or not capture_gem.visible or gems.has(capture_gem) or special_collected_count != 1:
			push_error("Breaking the owning stone must immediately award its gem")
			get_tree().quit(1)
			return
		capture_stage = 5
		capture_clock = 0.0
	elif capture_stage == 5 and capture_clock > 0.48:
		if capture_gem.is_emerging or capture_gem.collision_layer != 0 or not capture_gem.collected:
			push_error("The automatically acquired gem must remain non-interactive during its presentation")
			get_tree().quit(1)
			return
		aim_position = camera.unproject_position(capture_gem.global_position)
		_capture("lights_08_auto_acquired")
		capture_stage = 7
		capture_clock = 0.0
	elif capture_stage == 7 and capture_clock > 0.50:
		_capture("lights_09_collection")
		capture_stage = 8
		capture_clock = 0.0
	elif capture_stage == 8 and capture_clock > 1.8:
		capture_plain = _capture_plain_target()
		if capture_plain == null:
			push_error("No ordinary front stone for fracture capture")
			get_tree().quit(1)
			return
		capture_stage = 11
		capture_clock = 0.0
	elif capture_stage == 9 and capture_clock > 0.75:
		_capture("lights_10_portrait")
		capture_stage = 10
		capture_clock = 0.0
	elif capture_stage == 10 and capture_clock > 0.25:
		var observed: Array[int] = []
		for tier in light_pulse_history:
			if not observed.has(tier):
				observed.append(tier)
		var sealed_gems := 0
		for jewel in gems:
			if jewel.is_embedded:
				sealed_gems += 1
		if observed != [0, 1, 2, 3, 4, 5] or special_collected_count != 1 or sealed_gems != 5:
			push_error("Light capture did not demonstrate all six tiers and extraction: " + str(observed))
			get_tree().quit(1)
			return
		if capture_impact_points.size() != 3 or capture_impact_points[0].distance_to(capture_impact_points[1]) < 0.15 or capture_impact_points[1].distance_to(capture_impact_points[2]) < 0.15 or capture_impact_points[0].distance_to(capture_impact_points[2]) < 0.15:
			push_error("Impact capture did not strike three distinct positions: " + str(capture_impact_points))
			get_tree().quit(1)
			return
		if capture_fracture_count < 2 or capture_plain_count < 2:
			push_error("Both ordinary and gem stones must separate into multiple crack fragments")
			get_tree().quit(1)
			return
		print("LIGHT_CAPTURE_OK tiers=", observed, " hits=", hit_count, " gems=", collected_count, " still_embedded=", sealed_gems, " impact_positions=", capture_impact_points, " fragments_gem/plain=", capture_fracture_count, "/", capture_plain_count)
		get_tree().quit()
	elif capture_stage == 11 and capture_clock > 0.60:
		capture_fracture_center = capture_plain.mesh_instance.to_global(capture_plain.face_center)
		if capture_plain.health <= 1.0:
			_capture("fracture_plain_00_before")
		aim_position = _capture_cap_target(capture_plain)
		_request_swing()
		capture_stage = 12
		capture_clock = 0.0
	elif capture_stage == 12 and capture_clock > 0.40:
		capture_stage = 11 if is_instance_valid(capture_plain) else 13
		capture_clock = 0.0
	elif capture_stage == 13 and capture_clock > 1.0:
		get_window().size = Vector2i(600, 900)
		capture_stage = 9
		capture_clock = 0.0
	if elapsed > 65.0:
		push_error("Light capture timed out")
		get_tree().quit(1)

func _capture_plain_target() -> StaticBody3D:
	var best: StaticBody3D
	var best_distance := INF
	var center := get_viewport().get_visible_rect().size * 0.5
	for chunk in chunks:
		if chunk.is_gem_cover or chunk.layer_index != 0 or chunk.health < 3.0:
			continue
		var screen := camera.unproject_position(chunk.mesh_instance.to_global(chunk.face_center))
		if ray_at(screen).get("collider") != chunk:
			continue
		var distance := screen.distance_squared_to(center)
		if distance < best_distance:
			best = chunk
			best_distance = distance
	return best

func _capture_fracture_motion(prefix: String) -> void:
	await get_tree().create_timer(0.04).timeout
	_capture(prefix + "_01_opening")
	await get_tree().create_timer(0.10).timeout
	_capture(prefix + "_02_separating")
	await get_tree().create_timer(0.22).timeout
	_capture(prefix + "_03_falling")

func _capture_cap_target(cap: StaticBody3D) -> Vector2:
	var edge := int(float(cap.impact_count % 3) * float(cap.face_points.size()) / 3.0)
	var edge_midpoint: Vector3 = (cap.face_points[edge] + cap.face_points[(edge + 1) % cap.face_points.size()]) * 0.5
	var target: Vector3 = cap.face_center.lerp(edge_midpoint, 0.52)
	return camera.unproject_position(cap.mesh_instance.to_global(target))

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png("res://artifacts/" + label + ".png")
	var light_tier_shot := label.begins_with("lights_") and label.get_slice("_", 1).to_int() >= 1 and label.get_slice("_", 1).to_int() <= 6
	if label.begins_with("impacts_") or light_tier_shot:
		var cap: StaticBody3D = showcase_covers[5]
		var center := camera.unproject_position(cap.mesh_instance.to_global(cap.face_center))
		var pixel_scale := Vector2(screenshot.get_size()) / get_viewport().get_visible_rect().size
		var detail_size := Vector2i(680, 560) if light_tier_shot else Vector2i(400, 360)
		var region := Rect2i(Vector2i(center * pixel_scale) - detail_size / 2, detail_size)
		region = region.intersection(Rect2i(Vector2i.ZERO, screenshot.get_size()))
		screenshot.get_region(region).save_png("res://artifacts/" + label + "_detail.png")
	elif label.begins_with("fracture_"):
		var center := camera.unproject_position(capture_fracture_center)
		var pixel_scale := Vector2(screenshot.get_size()) / get_viewport().get_visible_rect().size
		var region := Rect2i(Vector2i(center * pixel_scale) - Vector2i(230, 200), Vector2i(460, 400))
		region = region.intersection(Rect2i(Vector2i.ZERO, screenshot.get_size()))
		screenshot.get_region(region).save_png("res://artifacts/" + label + "_detail.png")

func _max_gem_grade() -> int:
	return mini(campaign.cleared,Gem.EXOTIC) if campaign_enabled and round_enabled else Gem.EXOTIC

func _progress_status() -> Dictionary:
	var cleared_bosses := campaign.cleared if campaign_enabled and round_enabled else -1
	var result := OreProgression.status(round_state.lifetime_mining_gold,cleared_bosses)
	return campaign.decorate_status(result) if cleared_bosses >= 0 else result

func _try_spawn_boss() -> bool:
	if not _pending_boss or not campaign_enabled or not round_enabled or not is_instance_valid(boss): return false
	_pending_boss = false
	if round_state.phase != RoundModel.Phase.MINING or not campaign.begin(int(ore_profile.index)): return false
	boss.start(campaign.cleared,int(rng.randi()))
	return true

func _set_stage_theme(definition: Dictionary) -> void:
	if backdrop_material == null: return
	backdrop_material.set_shader_parameter("boss_strength",0.0 if definition.is_empty() else 1.0)
	if not definition.is_empty(): backdrop_material.set_shader_parameter("boss_tint",definition.back)

func _set_boss_skill_rules(enabled: bool) -> void:
	var disabled: Array[String] = []
	if enabled: disabled.append("ore")
	upgrade_stats = aux_tools.apply_to(main_tools.apply_to(upgrades.stats(disabled)))
	mining_skills.configure(upgrade_stats)
