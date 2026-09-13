extends Node3D
## Original beveled geometry. The shop and cursor share these same models.
var tool_id := "pickaxe"
var rotor: Node3D
var piston: Node3D

func build(id: String) -> void:
	tool_id = id
	name = "ToolModel"
	match id:
		"axe": _build_axe()
		"hammer": _build_hammer()
		"jackhammer": _build_jackhammer()
		"drill": _build_drill()
		_: _build_pickaxe(id == "gold_pickaxe")

func animate(delta: float, working: bool) -> void:
	if is_instance_valid(rotor):
		rotor.rotation.y = fposmod(rotor.rotation.y + delta * (46.0 if working else 2.0), TAU)

func _build_axe() -> void:
	var steel := _material(Color("475966"), 0.50, 0.40)
	var edge := _material(Color("d1e2e6"), 0.36, 0.50)
	var dark := _material(Color("25323d"), 0.77, 0.25)
	_handle(Color("a86843"), Color("603733"))
	_prism("BroadAxeBlade", PackedVector2Array([Vector2(0.13,0.30), Vector2(-0.39,0.40), Vector2(-0.84,0.66), Vector2(-1.09,0.58), Vector2(-1.31,0.15), Vector2(-1.31,-0.36), Vector2(-1.14,-0.66), Vector2(-0.79,-0.61), Vector2(-0.47,-0.25), Vector2(0.14,-0.16)]), 0.21, 0.065, steel, edge, dark)
	_flat_shape("HonedAxeEdge", PackedVector2Array([Vector2(-1.08,0.53), Vector2(-1.27,0.12), Vector2(-1.27,-0.33), Vector2(-1.12,-0.60), Vector2(-0.96,-0.50), Vector2(-1.08,-0.18), Vector2(-1.09,0.14), Vector2(-0.94,0.41)]), 0.214, edge)
	_block("AxePoll", Vector2(0.25,0.09), Vector2(0.44,0.46), 0.23, steel, edge, dark)
	_block("ForgedSocket", Vector2.ZERO, Vector2(0.35,0.62), 0.27, dark, steel, dark)
	_disc("CopperPin", Vector2(0,0.08), 0.082, 0.287, _material(Color("e7b575"), 0.45, 0.4))
	_flat_shape("BladeFacet", PackedVector2Array([Vector2(-0.80,0.47), Vector2(-0.42,0.30), Vector2(-0.21,0.22), Vector2(-0.55,0.02)]), 0.213, _material(Color("6d8995"), 0.54))

func _build_hammer() -> void:
	var metal := _material(Color("48515e"), 0.65, 0.32)
	var edge := _material(Color("93aab8"), 0.46, 0.45)
	var dark := _material(Color("202d37"), 0.79, 0.25)
	var brass := _material(Color("d1a04f"), 0.50, 0.42)
	_handle(Color("7c533a"), Color("24323d"))
	_block("HeavyForgedHead", Vector2(-0.10,0.03), Vector2(1.76,0.80), 0.40, metal, edge, dark)
	_block("LeftStrikingFace", Vector2(-1.04,0.03), Vector2(0.30,0.88), 0.45, dark, edge, metal)
	_block("RightStrikingFace", Vector2(0.84,0.03), Vector2(0.28,0.88), 0.45, dark, edge, metal)
	_block("HammerBand", Vector2(0,0.03), Vector2(0.36,0.90), 0.438, brass, _material(Color("f3d28b"),0.45,0.4), dark)
	_disc("SocketBolt", Vector2(0,0.06), 0.092, 0.461, dark)
	for x: float in [-0.72,-0.53,0.46,0.65]:
		_flat_shape("HeadRecess", _rectangle(Vector2(x,-0.21), Vector2(x+0.035,0.25)), 0.405, dark)

func _build_jackhammer() -> void:
	var orange := _material(Color("cf823d"), 0.76, 0.18)
	var bright := _material(Color("efbb64"), 0.57, 0.20)
	var iron := _material(Color("45545f"), 0.52, 0.46)
	var steel := _material(Color("b1cbd1"), 0.39, 0.53)
	var rubber := _material(Color("23333c"), 0.95)
	_lathe("PneumaticHousing", [Vector2(0.26,-0.99),Vector2(0.38,-0.80),Vector2(0.40,0.15),Vector2(0.31,0.43)], orange, 10)
	_lathe("TopPressureCap", [Vector2(0.32,0.37),Vector2(0.36,0.45),Vector2(0.30,0.58)], iron, 10)
	_lathe("LowerPressureCollar", [Vector2(0.22,-1.15),Vector2(0.32,-1.03),Vector2(0.32,-0.86)], iron, 10)
	for side in [-1,1]:
		var s := float(side)
		_prism("HandleYoke", PackedVector2Array([Vector2(s*0.22,0.31),Vector2(s*0.78,0.45),Vector2(s*0.99,0.26),Vector2(s*0.99,-0.02),Vector2(s*0.79,-0.02),Vector2(s*0.78,0.20),Vector2(s*0.24,0.11)]), 0.14,0.035,iron,steel,rubber)
		_block("RubberSideGrip", Vector2(s*0.90,0.13), Vector2(0.24,0.50), 0.18,rubber,iron,rubber)
		for j in 4:
			_block("GripGroove",Vector2(s*0.9,-0.05+j*0.10),Vector2(0.25,0.025),0.186,iron,iron,rubber)
		_block("HousingBrace",Vector2(s*0.30,-0.38),Vector2(0.075,0.95),0.32,bright,steel,iron)
	for i in 4:
		_block("PressureVent",Vector2(0,-0.18-i*0.13),Vector2(0.28,0.048),0.399,rubber,iron,rubber)
	_disc("HousingBolt",Vector2(0,0.16),0.08,0.405,steel)
	piston = Node3D.new()
	piston.name = "Piston"
	add_child(piston)
	var shaft := _lathe("PistonChisel",[Vector2(0,-2.30),Vector2(0.105,-2.06),Vector2(0.105,-1.17),Vector2(0.17,-1.13)],steel,8)
	shaft.reparent(piston,false)
	_lathe("ChiselRetainer",[Vector2(0.13,-1.50),Vector2(0.20,-1.43),Vector2(0.20,-1.24),Vector2(0.14,-1.18)],rubber,8)

func _build_drill() -> void:
	var blue := _material(Color("387a9f"),0.65,0.22)
	var edge := _material(Color("91cbdc"),0.48,0.38)
	var dark := _material(Color("1c323e"),0.91,0.12)
	var steel := _material(Color("9eafb7"),0.37,0.58)
	_lathe("MotorHousing",[Vector2(0.29,-0.79),Vector2(0.39,-0.57),Vector2(0.38,0.17),Vector2(0.27,0.38)],blue,12)
	_lathe("MotorBackCap",[Vector2(0.30,0.25),Vector2(0.34,0.36),Vector2(0.24,0.45)],dark,12)
	_prism("PistolGrip",PackedVector2Array([Vector2(0.24,-0.19),Vector2(0.68,-0.21),Vector2(0.82,-1.05),Vector2(0.52,-1.11),Vector2(0.40,-0.53),Vector2(0.26,-0.50)]),0.21,0.04,blue,edge,dark)
	_block("BatteryPack",Vector2(0.69,-1.14),Vector2(0.69,0.36),0.29,dark,edge,dark)
	_block("Trigger",Vector2(0.45,-0.49),Vector2(0.13,0.24),0.24,_material(Color("e5a55b"),0.68),edge,dark)
	for i in 4:
		_block("CoolingSlot",Vector2(0,-0.03-i*0.12),Vector2(0.28,0.036),0.388,dark,dark,dark)
	for i in 3:
		_block("BatteryChargeLight",Vector2(0.52+i*0.12,-1.10),Vector2(0.07,0.048),0.295,_material(Color("c4e1be"),0.55),edge,dark)
	rotor = Node3D.new()
	rotor.name = "SpinningBit"
	add_child(rotor)
	var chuck := _lathe("KeylessChuck",[Vector2(0.15,-1.15),Vector2(0.30,-0.99),Vector2(0.31,-0.78),Vector2(0.27,-0.70)],dark,10)
	chuck.reparent(rotor,false)
	var bit := _lathe("DrillBitCore",[Vector2(0,-2.27),Vector2(0.07,-2.13),Vector2(0.11,-1.07)],steel,10)
	bit.reparent(rotor,false)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(steel)
	for i in 100:
		var t := i / 100.0
		var u := (i+1) / 100.0
		var a := Vector3(cos(t*TAU*3.7)*(0.24-t*0.20),-1.08-t*1.16,sin(t*TAU*3.7)*(0.24-t*0.20))
		var b := Vector3(cos(u*TAU*3.7)*(0.24-u*0.20),-1.08-u*1.16,sin(u*TAU*3.7)*(0.24-u*0.20))
		var ca := Vector3(a.x*0.52,a.y,a.z*0.52)
		var cb := Vector3(b.x*0.52,b.y,b.z*0.52)
		var lip := Vector3.UP*0.045
		_triangle(surface,ca,a,b)
		_triangle(surface,ca,b,cb)
		_triangle(surface,ca-lip,b-lip,a-lip)
		_triangle(surface,ca-lip,cb-lip,b-lip)
		_triangle(surface,a,a-lip,b-lip)
		_triangle(surface,a,b-lip,b)
	var helix := MeshInstance3D.new()
	helix.name = "HelicalCuttingFlutes"
	helix.mesh = surface.commit()
	rotor.add_child(helix)

func _gold_details() -> void:
	var edge := _material(Color("fff0a5"),0.40,0.52)
	var dark := _material(Color("694621"),0.66,0.3)
	var teal := _material(Color("59bba8"),0.43,0.36)
	_prism("CrownedSocket",PackedVector2Array([Vector2(-0.23,0.30),Vector2(-0.21,0.52),Vector2(-0.09,0.42),Vector2(0,0.60),Vector2(0.10,0.42),Vector2(0.22,0.52),Vector2(0.24,0.29)]),0.22,0.025,edge,edge,dark)
	_prism("EmeraldSocketInlay",PackedVector2Array([Vector2(0,0.23),Vector2(0.10,0.05),Vector2(0,-0.15),Vector2(-0.10,0.05)]),0.292,0.025,teal,_material(Color("b7f3d9"),0.32),dark)
	for side in [-1,1]:
		for i in 3:
			var x: float = side*(0.46+i*0.17)
			_flat_shape("BladeEngraving",PackedVector2Array([Vector2(x,0.08),Vector2(x+side*0.06,0.12),Vector2(x+side*0.015,0.025)]),0.198,dark)
	for y: float in [-0.55,-0.80]:
		_flat_shape("HandleGoldInlay",PackedVector2Array([Vector2(-0.06,y+0.075),Vector2(0.012,y),Vector2(-0.06,y-0.075),Vector2(-0.10,y)]),0.156,edge)

func _handle(wood_color: Color, wrap_color: Color) -> void:
	var wood := _material(wood_color,0.89)
	var edge := _material(wood_color.lightened(0.23),0.81)
	var side := _material(wood_color.darkened(0.39),0.93)
	var wrap := _material(wrap_color,0.95)
	var metal := _material(Color("bda37c"),0.51,0.33)
	_prism("ShapedWoodHandle",PackedVector2Array([Vector2(-0.10,0.22),Vector2(0.10,0.22),Vector2(0.15,-1.05),Vector2(0.10,-1.97),Vector2(-0.16,-1.99),Vector2(-0.21,-1.85),Vector2(-0.13,-0.81)]),0.15,0.035,wood,edge,side)
	_flat_shape("HandleGrain",PackedVector2Array([Vector2(-0.04,-0.35),Vector2(0.01,-0.76),Vector2(-0.02,-1.03),Vector2(-0.06,-0.72)]),0.154,side)
	for i in 7:
		var y := -1.19-i*0.10
		_prism("LeatherTurn",PackedVector2Array([Vector2(-0.15,y+0.03),Vector2(0.13,y+0.075),Vector2(0.13,y-0.005),Vector2(-0.16,y-0.05)]),0.172,0.012,wrap,_material(wrap_color.lightened(0.13),0.89),wrap)
	_block("GripFerrule",Vector2(-0.02,-1.08),Vector2(0.33,0.10),0.18,metal,metal,side)
	_block("GripPommel",Vector2(-0.04,-1.96),Vector2(0.35,0.17),0.18,metal,metal,side)

func _block(label: String, center: Vector2, dimensions: Vector2, depth: float, face: Material, edge: Material, side: Material) -> MeshInstance3D:
	return _prism(label,_rectangle(center-dimensions*0.5,center+dimensions*0.5),depth,minf(0.055,minf(dimensions.x,dimensions.y)*0.15),face,edge,side)

func _disc(label: String, center: Vector2, radius: float, depth: float, material: Material) -> void:
	var polygon := PackedVector2Array()
	for i in 8:
		polygon.append(center+Vector2.from_angle(i*TAU/8.0)*radius)
	_prism(label,polygon,depth,0.012,material,material,material)

func _lathe(label: String, profile: Array[Vector2], material: Material, segments: int = 12) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var center := Vector3(0,(profile[0].y+profile[-1].y)*0.5,0)
	for row in profile.size()-1:
		for i in segments:
			var angle := i*TAU/segments
			var next := (i+1)*TAU/segments
			var a := Vector3(cos(angle)*profile[row].x,profile[row].y,sin(angle)*profile[row].x)
			var b := Vector3(cos(next)*profile[row].x,profile[row].y,sin(next)*profile[row].x)
			var c := Vector3(cos(next)*profile[row+1].x,profile[row+1].y,sin(next)*profile[row+1].x)
			var d := Vector3(cos(angle)*profile[row+1].x,profile[row+1].y,sin(angle)*profile[row+1].x)
			_quad_outward(surface,a,b,c,d,center)
	for end in [0,profile.size()-1]:
		if profile[end].x <= 0:
			continue
		for i in segments:
			var a := Vector3(0,profile[end].y,0)
			var b := Vector3(cos(i*TAU/segments)*profile[end].x,a.y,sin(i*TAU/segments)*profile[end].x)
			var c := Vector3(cos((i+1)*TAU/segments)*profile[end].x,a.y,sin((i+1)*TAU/segments)*profile[end].x)
			if end == 0: _triangle(surface,a,b,c)
			else: _triangle(surface,a,c,b)
	var model := MeshInstance3D.new()
	model.name = label
	model.mesh = surface.commit()
	add_child(model)
	return model

func _build_pickaxe(golden: bool = false) -> void:
	var wood := _material(Color("25434b") if golden else Color("a76032"), 0.86)
	var wood_edge := _material(Color("52737a") if golden else Color("e8a15c"), 0.82)
	var wood_side := _material(Color("15262d") if golden else Color("633624"), 0.95)
	var steel := _material(Color("c59030") if golden else Color("344957"), 0.48, 0.34)
	var steel_edge := _material(Color("ffeda5") if golden else Color("b5e0e1"), 0.28, 0.52)
	var steel_side := _material(Color("765126") if golden else Color("172a3b"), 0.62, 0.25)
	var brass := _material(Color("dfa64e"), 0.40, 0.46)
	var brass_light := _material(Color("ffda80"), 0.34, 0.43)
	var brass_dark := _material(Color("84562c"), 0.70, 0.26)
	var leather := _material(Color("2b3037"), 0.94)
	var leather_edge := _material(Color("56616b"), 0.87)
	var head_outline := PackedVector2Array([
		Vector2(-1.44, -0.36), Vector2(-1.26, -0.02), Vector2(-0.98, 0.21),
		Vector2(-0.60, 0.32), Vector2(-0.25, 0.26), Vector2(0.02, 0.21),
		Vector2(0.34, 0.30), Vector2(0.65, 0.30), Vector2(0.96, 0.15),
		Vector2(1.20, -0.10), Vector2(1.36, -0.45), Vector2(1.08, -0.26),
		Vector2(0.79, -0.08), Vector2(0.53, 0.02), Vector2(0.26, -0.01),
		Vector2(0.02, -0.12), Vector2(-0.31, -0.02), Vector2(-0.72, 0.015),
		Vector2(-1.08, -0.14)
	])
	var handle_outline := PackedVector2Array([
		Vector2(-0.13, 0.16), Vector2(0.12, 0.16), Vector2(0.13, -0.43),
		Vector2(0.07, -1.05), Vector2(0.095, -1.43), Vector2(0.16, -1.84),
		Vector2(0.10, -1.96), Vector2(-0.10, -1.98), Vector2(-0.18, -1.85),
		Vector2(-0.23, -1.32), Vector2(-0.17, -0.91), Vector2(-0.12, -0.40)
	])
	_prism("HickoryHandle", handle_outline, 0.15, 0.035, wood, wood_edge, wood_side)
	_prism("ForgedSteelHead", head_outline, 0.19, 0.042, steel, steel_edge, steel_side)
	# Narrow hand-cut highlights and grain are actual geometry, avoiding texture blur.
	_flat_shape("WoodGrain", PackedVector2Array([
		Vector2(-0.065, -0.29), Vector2(-0.035, -0.40), Vector2(-0.055, -0.82),
		Vector2(-0.090, -1.18), Vector2(-0.10, -1.25), Vector2(-0.082, -0.81)
	]), 0.154, wood_side)
	_flat_shape("WoodGlint", PackedVector2Array([
		Vector2(0.035, -0.31), Vector2(0.065, -0.35), Vector2(0.040, -0.82),
		Vector2(0.005, -1.06), Vector2(0.015, -0.68)
	]), 0.155, wood_edge)
	var mount := PackedVector2Array([
		Vector2(-0.19, 0.22), Vector2(-0.11, 0.30), Vector2(0.13, 0.30),
		Vector2(0.21, 0.21), Vector2(0.18, -0.22), Vector2(0.10, -0.28),
		Vector2(-0.12, -0.28), Vector2(-0.19, -0.19)
	])
	_prism("BronzeSocket", mount, 0.225, 0.035, brass, brass_light, brass_dark)
	_prism("SocketInset", _rectangle(Vector2(-0.095, -0.14), Vector2(0.105, 0.19)), 0.253, 0.017, steel_side, brass_dark, brass_dark)
	for y in [-0.08, 0.12]:
		var rivet := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.040
		sphere.height = 0.046
		sphere.radial_segments = 8
		sphere.rings = 3
		rivet.mesh = sphere
		rivet.material_override = brass_light
		rivet.position = Vector3(0.005, y, 0.277)
		rivet.rotation.x = PI * 0.5
		add_child(rivet)
	# Individual slanted leather turns leave a slim gold seam between wraps.
	for i in range(7):
		var y := -1.13 - float(i) * 0.10
		var x := -0.07 + maxf(0.0, -y - 1.25) * 0.15
		var wrap_outline := PackedVector2Array([
			Vector2(x - 0.154, y + 0.04), Vector2(x + 0.153, y + 0.075),
			Vector2(x + 0.163, y - 0.005), Vector2(x - 0.150, y - 0.055)
		])
		_prism("LeatherWrap%d" % i, wrap_outline, 0.173, 0.012, leather, leather_edge, leather)
	_prism("GripUpperFerrule", _rectangle(Vector2(-0.228, -1.11), Vector2(0.084, -1.015)), 0.176, 0.015, brass, brass_light, brass_dark)
	_prism("Pommel", PackedVector2Array([
		Vector2(-0.13, -1.78), Vector2(0.145, -1.79), Vector2(0.175, -1.91),
		Vector2(0.085, -2.02), Vector2(-0.092, -2.02), Vector2(-0.18, -1.90)
	]), 0.18, 0.028, brass, brass_light, brass_dark)
	# Small upper facet makes the forged metal catch the light as it swings.
	_flat_shape("LeftSteelFacet", PackedVector2Array([
		Vector2(-1.17, -0.025), Vector2(-0.94, 0.15), Vector2(-0.59, 0.255),
		Vector2(-0.28, 0.203), Vector2(-0.54, 0.16), Vector2(-0.93, 0.095)
	]), 0.193, _material(Color("ffe17a") if golden else Color("668998"), 0.44, 0.30))
	_flat_shape("RightSteelFacet", PackedVector2Array([
		Vector2(0.31, 0.234), Vector2(0.63, 0.24), Vector2(0.91, 0.10),
		Vector2(1.12, -0.13), Vector2(0.88, 0.015), Vector2(0.59, 0.17)
	]), 0.194, _material(Color("e8b94d") if golden else Color("597b8d"), 0.44, 0.30))


	if golden:
		_gold_details()


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return material


func _rectangle(low: Vector2, high: Vector2) -> PackedVector2Array:
	return PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])


func _prism(mesh_name: String, polygon: PackedVector2Array, depth: float, bevel: float,
		face_material: Material, bevel_material: Material, side_material: Material) -> MeshInstance3D:
	# Each bevel has its own hard normal: highlights remain graphic and readable.
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	center /= float(polygon.size())
	var inner := PackedVector2Array()
	for point in polygon:
		inner.append(point.move_toward(center, bevel))
	var triangles := Geometry2D.triangulate_polygon(inner)
	var mesh := ArrayMesh.new()
	var faces := SurfaceTool.new()
	faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	faces.set_material(face_material)
	for i in range(0, triangles.size(), 3):
		var a := inner[triangles[i]]
		var b := inner[triangles[i + 1]]
		var c := inner[triangles[i + 2]]
		_front_triangle(faces, Vector3(a.x, a.y, depth), Vector3(b.x, b.y, depth), Vector3(c.x, c.y, depth))
		_back_triangle(faces, Vector3(a.x, a.y, -depth), Vector3(b.x, b.y, -depth), Vector3(c.x, c.y, -depth))
	faces.commit(mesh)
	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	edges.set_material(bevel_material)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.set_material(side_material)
	for i in range(polygon.size()):
		var j := (i + 1) % polygon.size()
		var a := Vector3(inner[i].x, inner[i].y, depth)
		var b := Vector3(inner[j].x, inner[j].y, depth)
		var c := Vector3(polygon[j].x, polygon[j].y, depth - bevel)
		var d := Vector3(polygon[i].x, polygon[i].y, depth - bevel)
		_quad_outward(edges, a, b, c, d, Vector3(center.x, center.y, 0.0))
		_quad_outward(edges, Vector3(a.x, a.y, -depth), Vector3(b.x, b.y, -depth), Vector3(c.x, c.y, -depth + bevel), Vector3(d.x, d.y, -depth + bevel), Vector3(center.x, center.y, 0.0))
		_quad_outward(sides, d, c, Vector3(c.x, c.y, -depth + bevel), Vector3(d.x, d.y, -depth + bevel), Vector3(center.x, center.y, 0.0))
	edges.commit(mesh)
	sides.commit(mesh)
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	add_child(instance)
	return instance


func _flat_shape(mesh_name: String, polygon: PackedVector2Array, z: float, material: Material) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for i in range(0, triangles.size(), 3):
		var a := polygon[triangles[i]]
		var b := polygon[triangles[i + 1]]
		var c := polygon[triangles[i + 2]]
		_front_triangle(surface, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z))
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = surface.commit()
	add_child(instance)


func _quad_outward(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3) -> void:
	var normal := (b-a).cross(c-a)
	if normal.length_squared() < 0.00000001:
		normal = (c-a).cross(d-a)
	if normal.dot((a + b + c + d) * 0.25 - center) >= 0.0:
		_triangle(surface, a, b, c)
		_triangle(surface, a, c, d)
	else:
		_triangle(surface, a, c, b)
		_triangle(surface, a, d, c)


func _front_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).z > 0.0:
		_triangle(surface, a, b, c)
	else:
		_triangle(surface, a, c, b)


func _back_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).z < 0.0:
		_triangle(surface, a, b, c)
	else:
		_triangle(surface, a, c, b)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color = Color.WHITE) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < 0.5:
		return
	surface.set_color(color)
	surface.set_normal(normal)
	# Godot uses clockwise front faces, the opposite of the geometric normal.
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
