extends Node3D
## Authored low-poly bosses and seven stage sets; no external model assets.
const SURFACE = preload("res://shaders/boss_surface.gdshader")
const Wire = preload("res://scripts/boss_interactable.gd")
var body: Node3D
var scenery: Node3D
var rings: Array[Node3D] = []
var spikes: Array[Node3D] = []
var wires: Array[StaticBody3D] = []
var _materials: Dictionary = {}
var game: Node3D
var info: Dictionary
var age := 0.0

func build(owner_game: Node3D, definition: Dictionary) -> void:
	game = owner_game
	info = definition
	body = Node3D.new()
	body.name = "BossSculpture"
	game.shell.add_child(body)
	body.scale = info.get("shape",Vector3.ONE)
	scenery = Node3D.new()
	scenery.name = "BossStage"
	add_child(scenery)
	_build_stage()
	var r: float = info.radius
	var dark := Color("202735")
	var accent: Color = info.accent
	match info.id:
		"regenerator":
			for i in 7:
				var a := i*TAU/7
				var start := Vector3(cos(a)*r*0.62,-r*0.70,sin(a)*r*0.62)
				_line(body,start,start+Vector3(cos(a)*0.75,-0.75,sin(a)*0.75),0.18,Color("395e51"))
				_gem(body,start+Vector3(0,-0.20,0),Vector3(0.22,0.58,0.22),accent,0.10)
		"bastion":
			for side in [-1,1]:
				var p := Vector3(side*r*.63,r*.79,.05)
				_box(body,p,Vector3(.85,r*.67,.94),Color("384f48"))
				_box(body,p+Vector3(0,r*.29,0),Vector3(1.02,.22,1.09),accent.darkened(.50))
				for tooth in 3: _box(body,p+Vector3((tooth-1)*.36,r*.39,0),Vector3(.22,.35,1.09),accent.darkened(.32))
		"wanderer":
			for i in 9:
				var a := i*TAU/9
				var p := Vector3(cos(a)*r*0.76,r*0.62,sin(a)*r*0.60)
				_gem(body,p,Vector3(0.18,0.90,0.20),accent,0.14)
			_ring(body,Vector3(0,0,-r*0.52),r*1.12,0.045,accent,Vector3(1.1,0.3,0.2),0.15)
		"timebomb":
			_ring(body,Vector3(0,0,r*.62),r*.84,.12,Color("34424b"),Vector3(PI/2,0,0))
			_ring(body,Vector3(0,0,r*.65),r*.85,.035,accent,Vector3(PI/2,0,0),.10)
			for i in 12:
				var a := i*TAU/12
				_box(body,Vector3(cos(a)*r*.85,sin(a)*r*.85,r*.65),Vector3(.18,.18,.20),Color("d5bd8a"))
		"thorn":
			_ring(body,Vector3(0,-r*0.73,0),r*0.65,0.11,dark,Vector3.ZERO)
		"artillery":
			# A hexagonal volcanic muzzle, with a deep black aperture and copper lip.
			# Open collar leaves the real stone plates visible and targetable inside.
			_ring(body,Vector3(0,-.12,r*.93),r*.43,.24,dark,Vector3(PI/2,0,0))
			_ring(body,Vector3(0,-.12,r*1.04),r*.45,.14,Color("9e6755"),Vector3(PI/2,0,0))
			_ring(body,Vector3(0,-.12,r*1.075),r*.36,.055,accent,Vector3(PI/2,0,0),.42)
			for side in [-1,1]:
				var p := Vector3(side*r*.60,r*.87,-r*.18)
				_cylinder(body,p,.30,.46,1.80,Color("30282e"),Vector3(0,0,side*.25),7)
				_ring(body,p+Vector3(-side*.22,.84,0),.31,.07,accent,Vector3(0,0,side*.25),.30)
		"exotic_core":
			for i in 2:
				var ring := _ring(body,Vector3.ZERO,r*1.17,0.075,accent,Vector3(0.35+i*1.3,0.6,-0.4+i*0.8),0.16)
				rings.append(ring)
			for i in 8:
				var a := i*TAU/8
				var p := Vector3(cos(a)*r*1.14,sin(a)*r*1.14,0)
				_gem(body,p,Vector3(0.22,0.67,0.26),dark)
				_gem(body,p,Vector3(0.09,0.41,0.12),Color("e7ffe8") if i%2 == 0 else Color("f6cfff"),0.22)

func _build_stage() -> void:
	var r: float = info.radius
	var accent: Color = info.accent
	var floor_color: Color = info.color.darkened(0.32)
	var floor_y := -r*float(info.get("shape",Vector3.ONE).y)-.48
	_cylinder(scenery,Vector3(0,floor_y-.22,-.35),r*1.48,r*1.57,.38,floor_color,Vector3.ZERO,12)
	_ring(scenery,Vector3(0,floor_y,-.35),r*1.26,.045,accent,Vector3.ZERO,.14)
	for side in [-1,1]:
		for i in 3:
			var height := r*(1.35-0.22*i)
			var p := Vector3(side*(r*1.28+i*.43),floor_y+height*.5,-r*.90-i*.42)
			match info.id:
				"regenerator":
					_gem(scenery,p,Vector3(.52,height*.55,.48),floor_color)
					_line(scenery,p+Vector3(0,height*.42,0),p+Vector3(side*.60,height*.57,0),.12,accent.darkened(.38))
				"bastion":
					_box(scenery,p,Vector3(0.70,height,0.90),floor_color)
					_box(scenery,p+Vector3(0,height*.5,0),Vector3(.96,.25,1.1),accent.darkened(.40))
				"wanderer": _gem(scenery,p,Vector3(.40,height*.64,.58),accent.darkened(.36),.04)
				"timebomb":
					_cylinder(scenery,p,.33,.33,height,floor_color,Vector3.ZERO,8)
					for j in 4: _ring(scenery,p+Vector3(0,(j-1.5)*height/4,0),.34,.06,accent.darkened(.24),Vector3.ZERO)
				"thorn":
					_gem(scenery,p,Vector3(.4,height*.57,.4),Color("211c2c"))
					_gem(scenery,p+Vector3(side*.32,height*.20,0),Vector3(.21,height*.45,.20),accent.darkened(.48))
				"artillery":
					_cylinder(scenery,p,.48,.62,height,floor_color,Vector3(0,0,side*.06),6)
					_ring(scenery,p+Vector3(0,height*.5,0),.43,.09,accent,Vector3.ZERO,.30)
				"exotic_core":
					_gem(scenery,p,Vector3(.65,.85,.55),Color("252137"))
					_gem(scenery,p+Vector3(0,.85,0),Vector3(.15,.65,.18),accent,.22)

func mark(chunk: StaticBody3D, role: String, accent: Color) -> void:
	if chunk.has_node("BossRole"):
		var previous := chunk.get_node("BossRole")
		chunk.remove_child(previous)
		previous.queue_free()
	if role.is_empty(): return
	var holder := Node3D.new()
	holder.name = "BossRole"
	chunk.add_child(holder)
	holder.position = chunk.face_center+chunk.direction*0.035
	holder.quaternion = Quaternion(Vector3.UP,chunk.direction)
	var size: float = clampf(chunk.gem_socket_radius*0.85,.13,.32)
	if role == "guard":
		_cylinder(holder,Vector3(0,.03,0),size*1.4,size*1.4,.13,Color("1d3534"),Vector3.ZERO,6)
		_ring(holder,Vector3(0,.11,0),size*1.10,size*.18,accent,Vector3.ZERO,.12)
		_gem(holder,Vector3(0,.12,0),Vector3(size*.4,size*.5,size*.4),accent,.20)
	elif role == "weak":
		_ring(holder,Vector3.ZERO,size*1.40,size*.12,accent,Vector3.ZERO,.38)
		_gem(holder,Vector3(0,size*.45,0),Vector3(size*.62,size*1.15,size*.62),accent,.32)
	elif role == "protected":
		_ring(holder,Vector3.ZERO,size*1.45,size*.045,accent,Vector3.ZERO,.20)

func add_spike(chunk: StaticBody3D) -> void:
	var holder := Node3D.new()
	holder.name = "RetractingSpike"
	chunk.mesh_instance.add_child(holder)
	holder.position = chunk.face_center
	holder.quaternion = Quaternion(Vector3.UP,chunk.direction)
	_cylinder(holder,Vector3(0,0.54,0),0.0,.20,1.10,Color("2a2437"),Vector3.ZERO,5)
	_cylinder(holder,Vector3(0,.87,0),0.0,.095,.42,info.accent,Vector3.ZERO,5,0.1)
	holder.scale = Vector3(.92,.012,.92)
	spikes.append(holder)

func set_spikes(amount: float) -> void:
	for spike in spikes:
		if is_instance_valid(spike): spike.scale.y = maxf(.012,amount)

func add_wires() -> void:
	var colors := [Color("ff897d"),Color("87dcff"),Color("ffe292")]
	var r: float = info.radius
	for index in 3:
		var wire := Wire.new()
		wire.name = "DefusalWire%d" % index
		wire.set_meta("boss_wire",index)
		wire.collision_layer = 1
		wire.collision_mask = 0
		body.add_child(wire)
		var points: Array[Vector3] = []
		# The strand lies under the outer plates. A stone must be mined away
		# before either the visible wire or its collision can be reached.
		var buried_radius := r*.84
		for j in 7:
			var y := lerpf(-r*.58,r*.58,j/6.0)
			var x := (index-1)*r*.40 + sin(j*.8+index)*r*.11
			points.append(Vector3(x,y,sqrt(maxf(.1,buried_radius*buried_radius-x*x-y*y))))
		for j in points.size()-1:
			var a := points[j]
			var b := points[j+1]
			var strand := _line(wire,a,b,.080,colors[index],.10)
			wire.materials.append(strand.material_override)
			var collider := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = .17
			capsule.height = a.distance_to(b)+.20
			collider.shape = capsule
			collider.position = (a+b)*.5
			collider.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
			wire.add_child(collider)
		for p: Vector3 in [points.front(),points.back()]: _gem(wire,p,Vector3(.19,.22,.19),colors[index],.15)
		wires.append(wire)

func animate(delta: float, spikes_out: bool, warning: bool) -> void:
	age += delta
	for i in rings.size(): rings[i].rotate_z(delta*(.16 if i == 0 else -.12))
	set_spikes(1.0 if spikes_out else (.18+.12*sin(age*18) if warning else .012))

func clear() -> void:
	if is_instance_valid(body): body.hide(); body.queue_free()
	for wire in wires:
		if is_instance_valid(wire): wire.collision_layer = 0
	queue_free()

func _material(color: Color, glow: float = 0) -> ShaderMaterial:
	var key := color.to_html()+str(glow)
	if _materials.has(key): return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("tint",color)
	material.set_shader_parameter("glow",glow)
	_materials[key] = material
	return material

func _mesh(parent: Node3D, mesh: Mesh, point: Vector3, color: Color, glow: float = 0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color,glow)
	node.position = point
	parent.add_child(node)
	return node

func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent,mesh,point,color)

func _gem(parent: Node3D, point: Vector3, size: Vector3, color: Color, glow: float = 0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 5
	mesh.rings = 2
	var node := _mesh(parent,mesh,point,color,glow)
	node.scale = size*2.0
	return node

func _cylinder(parent: Node3D, point: Vector3, top: float, bottom: float, height: float, color: Color, angles: Vector3 = Vector3.ZERO, sides: int = 10, glow: float = 0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	var node := _mesh(parent,mesh,point,color,glow)
	node.rotation = angles
	return node

func _line(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, glow: float = 0) -> MeshInstance3D:
	var node := _cylinder(parent,(a+b)*.5,radius,radius,a.distance_to(b),color,Vector3.ZERO,6,glow)
	node.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return node

func _ring(parent: Node3D, point: Vector3, radius: float, width: float, color: Color, angles: Vector3, glow: float = 0) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-width
	mesh.outer_radius = radius+width
	mesh.rings = 32
	mesh.ring_segments = 5
	var node := _mesh(parent,mesh,point,color,glow)
	node.rotation = angles
	return node
