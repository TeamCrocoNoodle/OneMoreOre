extends SceneTree
## Bounded model-presence, shared-cache, and lifecycle checks in actual Main.
const Gem = preload("res://scripts/gem.gd")
const Pickaxe = preload("res://scripts/pickaxe.gd")

class TestGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var checks := 0
var failures := 0
var finished := false

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func():
		if not finished:
			push_error("MODELED_UI_VALIDATION_TIMEOUT")
			quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	var game := TestGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.round_state.wallet_gold = 1234
	await process_frame
	await process_frame
	var gallery: Node = game.model_gallery
	var ui: Node = game.skill_ui
	var display: Control = ui.tools_panel
	_check(gallery != null and game.hud.model_gallery == gallery and ui.model_gallery == gallery and display.model_gallery == gallery, "HUD, skills, and tools reuse the same Main-owned model gallery")
	gallery.ensure_ready()
	gallery.ensure_ready()
	await process_frame
	_check(gallery.build_count == 1 and gallery.is_ready, "Repeated gallery requests retain a single completed model build")
	_check(gallery.viewports.size() == 7, "Exactly one coin and six rarity models supply every UI icon")
	var worlds: Array[int] = []
	var tiers: Array[int] = []
	var coin_count := 0
	for viewport: SubViewport in gallery.viewports:
		_check(viewport.transparent_bg and viewport.world_3d != null and viewport.get_camera_3d() != null, "Each icon has an actual transparent 3D viewport, world, and camera")
		var world_id: int = viewport.world_3d.get_instance_id()
		_check(not worlds.has(world_id), "Icon lighting worlds remain isolated from one another and gameplay")
		worlds.append(world_id)
		var meshes: Array[MeshInstance3D] = []
		_find_meshes(viewport, meshes)
		_check(not meshes.is_empty(), "Each cached icon is rendered from real mesh geometry")
		if str(viewport.get_meta("model_kind", "")) == "coin":
			coin_count += 1
			var solid := false
			for mesh in meshes:
				var size: Vector3 = mesh.mesh.get_aabb().size
				solid = solid or minf(size.x, minf(size.y, size.z)) > 0.001
			_check(solid, "The gold coin has physical thickness instead of a flat UI polygon")
		else:
			var tier := int(viewport.get_meta("tier", -1))
			tiers.append(tier)
			var gem: Node = _find_script(viewport, Gem)
			_check(gem != null and gem.grade == tier and gem.light_tier == tier and gem.collision_layer == 0 and gem.process_mode == Node.PROCESS_MODE_DISABLED, "Rarity icons reuse the corresponding actual gem model without gameplay collision or animation")
		_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Completed icon caches stop rendering their viewport")
	tiers.sort()
	_check(coin_count == 1 and tiers == [0, 1, 2, 3, 4, 5], "The shared gallery contains one gold coin and every grade exactly once")
	var coin: Texture2D = gallery.get_coin_texture()
	_check(coin != null and coin == gallery.get_coin_texture(), "Repeated coin draws reuse the same cached texture resource")
	for tier in 6:
		var texture: Texture2D = gallery.get_gem_texture(tier)
		_check(texture != null and texture != coin and texture == gallery.get_gem_texture(tier), "Each gem grade reuses its retained model texture")
	game._open_upgrades()
	ui.select_tab("tools")
	await process_frame
	await process_frame
	_check(display.cabinet_model != null and display.cabinet_model.get_meta("modeled_cabinet", false), "The displayed wooden cabinet is an actual retained Node3D model")
	_check(display.cabinet_viewport != null and display.cabinet_viewport.transparent_bg and display.cabinet_viewport.get_camera_3d() != null, "The cabinet and tools share an actual transparent camera render")
	var cabinet_meshes: Array[MeshInstance3D] = []
	_find_meshes(display.cabinet_model, cabinet_meshes)
	var part_types: Array[String] = []
	var solid_parts := 0
	for mesh in cabinet_meshes:
		if mesh.has_meta("cabinet_part"):
			var kind := str(mesh.get_meta("cabinet_part"))
			if not part_types.has(kind):
				part_types.append(kind)
			var size: Vector3 = mesh.mesh.get_aabb().size
			if minf(size.x, minf(size.y, size.z)) > 0.001:
				solid_parts += 1
	_check(part_types.size() >= 3 and solid_parts >= 6, "Separate solid boards, frame, and back parts form the modeled wooden shelf")
	var previews: Array[Node] = []
	_find_previews(display.cabinet_model, previews)
	_check(previews.size() == 6, "All six existing pickaxes occupy the same modeled cabinet")
	for preview in previews:
		var original := _find_script(preview, Pickaxe)
		_check(original != null and original.process_mode == Node.PROCESS_MODE_DISABLED, "Each shelf tool retains the original pickaxe geometry without running gameplay animation")
	var viewports: Array[SubViewport] = []
	_find_viewports(display, viewports)
	_check(viewports.size() == 1 and viewports[0] == display.cabinet_viewport, "The shelf uses a single cached scene render instead of per-frame or per-item extra viewports")
	for dimensions: Vector2i in [Vector2i(360, 800), Vector2i(800, 450)]:
		root.size = dimensions
		await process_frame
		game._resize()
		game._process(0.0)
		display.scroll_by(100000.0)
		_check(root.get_visible_rect().intersects(display.get_price_tag_rect(5)), "The modeled cabinet preserves access to the last item and price tag after resize")
		_check(game.hud.model_gallery == gallery and gallery.build_count == 1, "Responsive layouts continue sharing the original icon cache")
	ui.close_tree()
	await process_frame
	_check(display.cabinet_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not display.is_visible_in_tree(), "Closing the upgrade window stops cabinet rendering")
	_check(game.round_state.wallet_gold == 1234 and game.upgrades.stats().damage == 1.0 and game.round_state.gem_counts == PackedInt32Array([0, 0, 0, 0, 0, 0]), "Model previews do not purchase equipment, modify upgrades, or create real cargo")
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	finished = true
	print("MODELED_UI_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _find_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		output.append(node)
	for child in node.get_children():
		_find_meshes(child, output)

func _find_script(node: Node, script: Script) -> Node:
	if node.get_script() == script:
		return node
	for child in node.get_children():
		var found := _find_script(child, script)
		if found != null:
			return found
	return null

func _find_previews(node: Node, output: Array[Node]) -> void:
	if node.has_meta("variant_index") and node.has_meta("tool_id"):
		output.append(node)
	for child in node.get_children():
		_find_previews(child, output)

func _find_viewports(node: Node, output: Array[SubViewport]) -> void:
	if node is SubViewport:
		output.append(node)
	for child in node.get_children():
		_find_viewports(child, output)

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MODELED_UI_CHECK_FAILED: " + message)
