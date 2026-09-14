extends SceneTree
const Geometry = preload("res://scripts/rock_geometry.gd")
const Chunk = preload("res://scripts/rock_chunk.gd")
const Progress = preload("res://scripts/ore_progression.gd")
const Bank = preload("res://scripts/ore_mesh_bank.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/ore_geometry")
	for stage in 7:
		var info := Progress.profile(0,stage)
		for variant in 4:
			var path := "res://assets/ore_geometry/stage_%d_%d.res" % [stage,variant]
			if ResourceLoader.exists(path):
				var existing: Resource = load(path)
				if existing.format == Bank.FORMAT and existing.signature == Bank.profile_key(info): continue
				if existing.format == 1 and existing.signature == Bank.profile_key(info,1):
					for data: Dictionary in existing.cells: _store_cpu_geometry(data)
					existing.format = Bank.FORMAT
					existing.signature = Bank.profile_key(info)
					assert(ResourceSaver.save(existing,path,ResourceSaver.FLAG_COMPRESS) == OK)
					print("ORE_BANK_CONVERTED ",path)
					await process_frame
					continue
			var bank := Bank.new()
			bank.signature = Bank.profile_key(info)
			for layer in info.layers.size():
				var builder := Geometry.LayerBuilder.new(info.radius-layer*info.stride,layer,12872+variant,info.layers[layer],info.thickness,info)
				while builder.cursor < builder.count:
					var data: Dictionary = builder.next_cell()
					if data.is_empty(): continue
					var probe := Chunk.new()
					probe.configure(data,layer)
					data["socket_cache"] = {"planes":probe._containment_planes,"vertices":probe._fracture_source_vertices,"center":probe.gem_socket_center,"radius":probe.gem_socket_radius,"axis_min":probe._socket_axis_min,"axis_max":probe._socket_axis_max,"refined":probe._socket_refined}
					data["layer"] = layer
					_store_cpu_geometry(data)
					bank.cells.append(data)
					probe.free()
				await process_frame
			assert(bank.cells.size() == info.pieces)
			var error := ResourceSaver.save(bank,path,ResourceSaver.FLAG_COMPRESS)
			if error != OK: push_error("Cannot save " + path); quit(1); return
			print("ORE_BANK_BUILT ",path," cells=",bank.cells.size())
	print("ORE_BANKS_OK")
	quit()

func _store_cpu_geometry(data: Dictionary) -> void:
	data["mesh_arrays"] = data.mesh.surface_get_arrays(0)
	data["collision_points"] = data.collision.points
	data.erase("mesh")
	data.erase("collision")
