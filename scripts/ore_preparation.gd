extends RefCounted
## One sealed future ore, staged invisibly on an unqueried physics layer.
## Meshes, colliders, gem sockets and special marks are ready before activation.
const Geometry = preload("res://scripts/rock_geometry.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Progress = preload("res://scripts/ore_progression.gd")
const Bank = preload("res://scripts/ore_mesh_bank.gd")
var profile: Dictionary = {}
var seed_value := 0
var chunks: Array[StaticBody3D] = []
var complete := false
var layer := 0
var builder: RefCounted
var geometry_complete := false
var bank: Resource
var bank_path := ""
var cursor := 0
var root_node: Node3D
var gems: Array[StaticBody3D] = []
var plan: Dictionary = {}
var stats: Dictionary = {}
var collision_bit := 8
var grid: Dictionary = {}

static func make_chunk(data: Dictionary, depth: int, info: Dictionary, balanced: bool = true) -> StaticBody3D:
	data = data.duplicate()
	data.color = Progress.color_for(info,data.color,depth,int(data.seed))
	data["theme"] = info.theme
	data["accent"] = info.accent
	if balanced:
		data["health"] = Progress.Balance.stone_health(int(info.index),depth,int(data.seed))
		data["cover_health"] = float(info.cover_health)
	var chunk := Chunk.new()
	chunk.configure(data,depth)
	chunk.set_meta("stone_color",data.color)
	chunk.set_meta("outward",data.direction)
	return chunk

func begin(info: Dictionary, next_seed: int, owner: Node3D = null, values: Dictionary = {}) -> void:
	clear()
	profile = info.duplicate(true)
	seed_value = next_seed
	layer = 0
	cursor = 0
	stats = values.duplicate()
	bank_path = Bank.request(info,next_seed)
	if bank_path.is_empty(): _make_builder()
	if owner != null:
		collision_bit = 16 if owner._ore_collision_mask == 8 else 8
		root_node = Node3D.new()
		root_node.name = "PreparedOre"
		root_node.set_meta("ore_container",true)
		root_node.hide()
		owner.shell.add_child(root_node)
		root_node.set_as_top_level(true)
		# Use the next ore's final rest pose now, so activation does not move
		# thousands of broad-phase bounds from the current player's orbit pose.
		root_node.global_transform = owner.global_transform*Transform3D(Basis.from_euler(Vector3(.12,.24,-.06)),Vector3.ZERO)

func _make_builder() -> void:
	builder = Geometry.LayerBuilder.new(float(profile.radius)-layer*float(profile.stride),layer,seed_value,profile.layers[layer],profile.thickness,profile)

func advance(budget_usec: int = 1000, owner: Node3D = null) -> void:
	if complete or profile.is_empty(): return
	if not bank_path.is_empty() and bank == null:
		bank = Bank.poll(bank_path)
		if bank == null: return
		if bank.signature != Bank.profile_key(profile):
			bank = null
			bank_path = ""
			_make_builder()
	var deadline := Time.get_ticks_usec()+budget_usec
	while not complete and Time.get_ticks_usec() < deadline:
		if not geometry_complete:
			var data: Dictionary = {}
			if bank != null:
				if cursor >= bank.cells.size(): geometry_complete = true; continue
				data = bank.cell(cursor)
				layer = int(data.layer)
				data.seed = seed_value+cursor*127+layer*7919
				cursor += 1
			elif builder.cursor < builder.count:
				data = builder.next_cell()
			else:
				layer += 1
				if layer >= profile.layers.size(): geometry_complete = true; builder = null
				else: _make_builder()
			if data.is_empty(): continue
			var chunk := make_chunk(data,layer,profile)
			chunks.append(chunk)
			var key := Vector3i((chunk.position/2.0).floor())
			if not grid.has(key): grid[key] = []
			grid[key].append(chunk)
			if root_node != null:
				chunk.collision_layer = collision_bit
				chunk.visible = layer == 0
				root_node.add_child(chunk)
		elif owner == null:
			complete = true
		elif plan.is_empty():
			plan = owner._plan_gems(seed_value,profile,stats)
			plan["chunks"] = chunks
			plan["gems"] = gems
		elif int(plan.made) < plan.grades.size():
			owner._create_planned_gem(plan,root_node,stats)
		elif int(plan.placed) < gems.size():
			owner._contain_planned_gem(plan)
		elif int(plan.special_index) < chunks.size():
			var chunk := chunks[int(plan.special_index)]
			plan.special_index += 1
			owner._configure_special_stone(chunk,plan.special_random,stats)
			owner._apply_stone_health_reduction(chunk)
		else:
			complete = true

func matches(info: Dictionary, values: Dictionary = {}) -> bool:
	return not profile.is_empty() and profile.index == info.index and (values.is_empty() or stats == values)

func activate() -> Dictionary:
	var result := {"root":root_node,"chunks":chunks,"gems":gems,"grid":grid,"layers":plan.chunks_by_layer,"collision_bit":collision_bit,"seed":seed_value}
	root_node.set_as_top_level(false)
	root_node.transform = Transform3D.IDENTITY
	root_node.show()
	root_node = null
	chunks = []
	gems = []
	grid = {}
	plan = {}
	profile = {}
	stats = {}
	bank = null
	complete = false
	geometry_complete = false
	return result

func take() -> Array[StaticBody3D]:
	var result := chunks
	chunks = []
	profile = {}
	complete = false
	return result

func clear() -> void:
	if is_instance_valid(root_node): root_node.free()
	else:
		for chunk in chunks:
			if is_instance_valid(chunk): chunk.free()
	root_node = null
	chunks.clear()
	gems.clear()
	grid.clear()
	plan.clear()
	stats.clear()
	profile.clear()
	builder = null
	bank = null
	bank_path = ""
	complete = false
	geometry_complete = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(root_node): root_node.free()
		else:
			for chunk in chunks:
				if is_instance_valid(chunk): chunk.free()
