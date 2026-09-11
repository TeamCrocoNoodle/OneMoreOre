extends SceneTree
## Real shared tabs, retained skill purchases, and display-only tool shelves.
const Pickaxe = preload("res://scripts/pickaxe.gd")

class TestGame:
	extends "res://scripts/main.gd"
	func _spawn_rock(seed_override: int = -1, showcase: bool = false) -> void:
		super._spawn_rock(12873 if seed_override < 0 else seed_override, showcase)

var game: Node3D
var checks := 0
var failures: Array[String] = []
var ended := false

func _initialize() -> void:
	_run.call_deferred()
	create_timer(30.0).timeout.connect(func():
		if not ended:
			push_error("TOOLS_VALIDATION_TIMEOUT")
			quit(2)
	)

func _run() -> void:
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	game = TestGame.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	game.focused = true
	game.spawn_time = 1.0
	game.round_state.wallet_gold = 1000
	await physics_frame
	game._open_upgrades()
	await process_frame
	var ui: Node = game.skill_ui
	_check(ui.is_open and ui.selected_tab == "skills", "The real upgrade entry opens on the existing Skill Tree tab")
	var skill_tab: Rect2 = ui.get_tab_rect("skills")
	var tools_tab: Rect2 = ui.get_tab_rect("tools")
	_check(skill_tab.size.x > 0 and tools_tab.size.x > 0 and not skill_tab.intersects(tools_tab), "Both shared top tabs have distinct real hit rectangles")
	await _click(ui.get_node_screen("power"))
	_check(ui.selected_id == "power" and ui.get_confirmation_rect().size.x > 0, "A real skill selection has a pending confirmation before tab switching")
	await _click(tools_tab.get_center())
	var display: Control = ui.tools_panel
	_check(ui.selected_tab == "tools" and display.visible and ui.selected_id.is_empty() and ui.hovered_id.is_empty() and ui.get_confirmation_rect().size == Vector2.ZERO, "Tools cancels the pending skill confirmation and shows the shelf instead")
	var graph_hidden := true
	for button: Button in ui._buttons.values():
		graph_hidden = graph_hidden and (not button.is_visible_in_tree() or button.disabled)
	_check(graph_hidden, "The hidden skill graph leaves no enabled visible native Buttons on Tools")
	await _click(ui.get_node_screen("power"))
	_check(ui.selected_id.is_empty() and not game.upgrades.is_unlocked("power") and game.round_state.wallet_gold == 1000, "Clicking an old graph location cannot select or purchase a hidden skill")
	var catalog: Array[Dictionary] = display.get_catalog()
	_check(catalog.size() == 6, "The wooden display presents the six existing tool variants")
	var ids: Array[String] = []
	for i in catalog.size():
		var item: Dictionary = catalog[i]
		_check(not ids.has(str(item.id)) and item.has("title") and item.has("price"), "Each displayed tool has a unique identity, title, and price-tag value")
		ids.append(str(item.id))
		var card: Rect2 = display.get_item_rect(i)
		var tag: Rect2 = display.get_price_tag_rect(i)
		_check(card.size.x > 0 and tag.size.x > 0 and card.intersects(tag), "Each shelf item has an actual associated price-tag rectangle")
		await _click(tag.get_center())
		_check(game.round_state.wallet_gold == 1000 and game.upgrades.stats().damage == 1.0, "Displayed tool clicks do not spend gold or apply unimplemented gameplay effects")
	_check(ids == ["base", "copper", "silver", "cobalt", "dark_iron", "gold"], "The catalog preserves the original pickaxe family without inventing new tool geometry")
	var previews: Array[Node] = []
	_find_previews(display, previews)
	_check(previews.size() == 6, "All six shelf models are real retained 3D previews")
	for preview in previews:
		var original: Node = preview.get_node_or_null("DisplayPose/OriginalPickaxe")
		_check(original != null and original.get_script() == Pickaxe and original.process_mode == Node.PROCESS_MODE_DISABLED, "Each preview uses the existing pickaxe script and disables gameplay animation processing")
		_check(_mesh_count(preview) > 2, "A preview retains the actual built handle, head, and detail meshes")
	await _click(skill_tab.get_center())
	_check(ui.selected_tab == "skills" and not display.visible and ui.selected_id.is_empty(), "Returning to Skill Tree restores the graph without reviving its cancelled confirmation")
	await _click(ui.get_node_screen("power"))
	await _click(ui.get_confirmation_rect().get_center())
	_check(game.upgrades.is_unlocked("power") and game.round_state.wallet_gold == 975, "The original confirmation purchase remains functional after a Tools round trip")
	await _validate_keyboard_tabs(ui)
	await _validate_layouts(ui)
	ui.close_tree()
	await process_frame
	_check(not display.is_visible_in_tree() and game.round_state.wallet_gold == 975, "Closing the shared upgrade window hides its shelf while preserving the actual wallet")
	var viewports: Array[Node] = []
	_find_viewports(display, viewports)
	for viewport: SubViewport in viewports:
		_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Closed tool previews stop drawing their offscreen viewport")
	_stop_audio(game)
	game.queue_free()
	await process_frame
	var deadline := Time.get_ticks_usec() + 40000
	while Time.get_ticks_usec() < deadline:
		await process_frame
	ended = true
	print("TOOLS_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _validate_keyboard_tabs(ui: Node) -> void:
	# Follow real Tab focus traversal instead of directly activating a tab API.
	var found := false
	for i in 18:
		await _key(KEY_TAB)
		var focus: Control = root.gui_get_focus_owner()
		if focus != null and focus.get_global_rect().intersects(ui.get_tab_rect("tools")):
			found = true
			break
	_check(found, "Keyboard Tab can reach the actual Tools tab Button")
	if found:
		await _key(KEY_ENTER)
		_check(ui.selected_tab == "tools", "Enter activates the focused Tools tab instead of buying a graph node")
	else:
		# Keep the independent shortcut checks meaningful after a focus failure.
		await _click(ui.get_tab_rect("tools").get_center())
	await _key(KEY_Q)
	_check(ui.selected_tab == "skills", "Q cycles back to the Skill Tree tab")
	await _key(KEY_E)
	_check(ui.selected_tab == "tools", "E cycles forward to the Tools tab")
	await _joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(ui.selected_tab == "skills", "Controller LB switches to the Skill Tree tab")
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	_check(ui.selected_tab == "tools", "Controller RB switches to the Tools tab")
	var item_focused := false
	for i in 18:
		var focus: Control = root.gui_get_focus_owner()
		if focus != null:
			for index in 6:
				if ui.tools_panel.get_item_rect(index).has_point(focus.get_global_rect().get_center()):
					item_focused = true
		if item_focused:
			break
		await _key(KEY_TAB)
	_check(item_focused, "Native keyboard focus can reach an actual displayed tool Button")
	if item_focused:
		await _joy(JOY_BUTTON_A)
		_check(ui.tools_panel.selected_index >= 0 and game.round_state.wallet_gold == 975, "Controller A selects a displayed tool without purchasing or changing skills")

func _validate_layouts(ui: Node) -> void:
	for physical: Vector2i in [Vector2i(360, 800), Vector2i(800, 450)]:
		root.size = physical
		await process_frame
		game._resize()
		game._process(0.0)
		if ui.selected_tab != "tools":
			await _click(ui.get_tab_rect("tools").get_center())
		var view: Rect2 = game.get_viewport().get_visible_rect()
		_check(view.encloses(ui.get_tab_rect("skills")) and view.encloses(ui.get_tab_rect("tools")), "Both tabs remain fully on screen under the actual fixed-design portrait/small-window stretch")
		var display: Control = ui.tools_panel
		var limit: float = display.get_scroll_limit()
		display.scroll_by(100000.0)
		_check(display.get_scroll_offset() <= limit + 0.001 and display.get_scroll_offset() >= 0.0, "Shelf scrolling clamps to its actual content limit")
		_check(view.intersects(display.get_price_tag_rect(5)), "The last tool's price tag can be reached in each constrained layout")
		display.scroll_by(-100000.0)
		_check(is_zero_approx(display.get_scroll_offset()) and game.round_state.wallet_gold == 975, "Scrolling back reaches the first shelf without affecting gold")
	root.size = Vector2i(1152, 800)
	await process_frame

func _find_previews(node: Node, output: Array[Node]) -> void:
	if node.has_meta("variant_index") and node.has_meta("tool_id"):
		output.append(node)
	for child in node.get_children():
		_find_previews(child, output)

func _find_viewports(node: Node, output: Array[Node]) -> void:
	if node is SubViewport:
		output.append(node)
	for child in node.get_children():
		_find_viewports(child, output)

func _mesh_count(node: Node) -> int:
	var total := 1 if node is MeshInstance3D and node.mesh != null else 0
	for child in node.get_children():
		total += _mesh_count(child)
	return total

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _joy(button_index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 3
	event.button_index = button_index
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("TOOLS_CHECK_FAILED: " + message)
