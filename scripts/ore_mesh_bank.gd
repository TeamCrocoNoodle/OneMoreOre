extends Resource
## Immutable procedural geometry, baked by tools/build_ore_mesh_banks.gd.
## Gameplay rolls / health are applied at runtime, never stored in this bank.
const FORMAT := 2
@export var format := FORMAT
@export var signature := ""
@export var cells: Array[Dictionary] = []
var _native_cells: Dictionary = {}
static var _cache: Dictionary = {}
static var _pending: Dictionary = {}

static func profile_key(info: Dictionary, version: int = FORMAT) -> String:
	return str([version,info.radius,info.layers,info.stride,info.thickness,info.bevel,info.relief,info.face,info.corners])

func cell(index: int) -> Dictionary:
	# Loading thousands of Mesh resources on a worker still queues all OpenGL
	# uploads together. Banks contain CPU arrays only; native meshes and convex
	# shapes are materialized one cell at a time inside the caller's frame budget.
	var data := cells[index].duplicate()
	if not _native_cells.has(index):
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data.mesh_arrays)
		var shape := ConvexPolygonShape3D.new()
		shape.points = data.collision_points
		_native_cells[index] = {"mesh":mesh,"collision":shape}
	data.merge(_native_cells[index])
	return data

static func fetch(info: Dictionary, seed_value: int) -> Resource:
	# Four layouts retain irregular cell silhouettes and change the mining map.
	# A separate runtime seed controls stone variation, gem positions and skills.
	var variant := posmod(seed_value,4)
	var path := "res://assets/ore_geometry/stage_%d_%d.res" % [int(info.index),variant]
	var bank: Resource = _cache.get(path)
	if bank == null and ResourceLoader.exists(path):
		bank = load(path)
		_cache[path] = bank
	if bank == null or bank.format != FORMAT or bank.signature != profile_key(info): return null
	return bank

static func request(info: Dictionary, seed_value: int) -> String:
	var path := "res://assets/ore_geometry/stage_%d_%d.res" % [int(info.index),posmod(seed_value,4)]
	if not ResourceLoader.exists(path): return ""
	if not _cache.has(path) and not _pending.has(path):
		if ResourceLoader.load_threaded_request(path) != OK: return ""
		_pending[path] = true
	return path

static func poll(path: String) -> Resource:
	if _cache.has(path): return _cache[path]
	if not _pending.has(path): return null
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED: return null
	var bank := ResourceLoader.load_threaded_get(path)
	_pending.erase(path)
	_cache[path] = bank
	return bank

static func release_other_stages(stage: int) -> void:
	for path: String in _cache.keys():
		if not path.contains("stage_%d_" % stage): _cache.erase(path)

static func shutdown() -> void:
	# Consume outstanding threaded requests before releasing their script/cache.
	# This is teardown only; gameplay never waits on a pending load.
	for path: String in _pending:
		ResourceLoader.load_threaded_get(path)
	_pending.clear()
	_cache.clear()
