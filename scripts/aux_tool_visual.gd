extends "res://scripts/tool_visual.gd"
## Hand-authored solid cartoon equipment, shared by shop, HUD and world.
var muzzle: Marker3D
var moving_parts: Array[Node3D] = []
var plunger: Node3D

func build(id: String) -> void:
	tool_id = id
	name = "ToolModel"
	match id:
		"laser": _laser()
		"beer": _beer()
		"detector": _detector()
		"crusher": _crusher()
		"xray": _xray()
		"pin": _pin()
		"detonator": _detonator()

func animate(delta: float, working: bool) -> void:
	for i in moving_parts.size():
		moving_parts[i].rotation.z += delta*(9.0 if i%2 == 0 else -9.0) if working else 0.0

func _rod(label: String, a: Vector3, b: Vector3, radius: float, material: Material, segments: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = (a+b)*0.5
	node.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	add_child(node)
	return node

func _ball(label: String, point: Vector3, radius: float, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*1.7
	mesh.radial_segments = 8
	mesh.rings = 3
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = point
	add_child(node)

func _lit(color: String) -> StandardMaterial3D:
	var material := _material(Color(color),0.52,0.10)
	material.emission_enabled = true
	material.emission = Color(color)*0.35
	return material

func _laser() -> void:
	var dark := _material(Color("24353e"),0.73,0.3)
	var steel := _material(Color("78909c"),0.45,0.45)
	var edge := _material(Color("c4d9da"),0.45,0.3)
	var teal := _material(Color("357b88"),0.62,0.3)
	_lathe("SwivelBase",[Vector2(0.67,-0.92),Vector2(0.69,-0.75),Vector2(0.46,-0.64)],dark,12)
	_rod("TurretStem",Vector3(0,-0.68,0),Vector3(0,0.03,0),0.18,steel)
	for i in 3:
		var end := Vector3(cos(i*TAU/3.0)*0.91,-1.08,sin(i*TAU/3.0)*0.70)
		_rod("TripodLeg",Vector3(0,-0.75,0),end,0.11,dark)
	_block("LaserHousing",Vector2(-0.19,0.23),Vector2(1.36,0.78),0.35,teal,edge,dark)
	_rod("Barrel",Vector3(0.40,0.24,0),Vector3(1.04,0.24,0),0.235,steel,10)
	_rod("MuzzleCollar",Vector3(0.94,0.24,0),Vector3(1.12,0.24,0),0.29,dark,10)
	_rod("CyanLens",Vector3(1.125,0.24,0),Vector3(1.145,0.24,0),0.20,_lit("81eff4"),10)
	for i in 4:
		_block("CoolingFin",Vector2(-0.65+i*0.17,0.73),Vector2(0.08,0.20),0.32,dark,steel,dark)
	for i in 3:
		_block("PowerCell",Vector2(-0.52+i*0.23,0.25),Vector2(0.12,0.24),0.36,_lit("78dbe0"),edge,teal)
	_disc("SwivelBolt",Vector2(-0.05,-0.15),0.12,0.37,steel)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(1.15,0.24,0)
	add_child(muzzle)

func _beer() -> void:
	var amber := _material(Color("b9772e"),0.53,0.08)
	var gold := _material(Color("edb855"),0.52,0.12)
	var rim := _material(Color("c3b797"),0.47,0.35)
	var foam := _material(Color("fff0d2"),0.96)
	_lathe("AmberTankard",[Vector2(0.48,-0.92),Vector2(0.58,-0.77),Vector2(0.58,0.62),Vector2(0.62,0.72)],amber,12)
	_lathe("HeavyMugFoot",[Vector2(0.60,-0.94),Vector2(0.65,-0.83),Vector2(0.58,-0.72)],rim,12)
	_lathe("UpperMugRim",[Vector2(0.61,0.59),Vector2(0.65,0.65),Vector2(0.63,0.75)],rim,12)
	_prism("TankardHandle",PackedVector2Array([Vector2(0.48,0.52),Vector2(1.06,0.51),Vector2(1.25,0.25),Vector2(1.24,-0.30),Vector2(1.06,-0.57),Vector2(0.50,-0.59),Vector2(0.50,-0.33),Vector2(0.97,-0.32),Vector2(1.02,-0.15),Vector2(1.02,0.15),Vector2(0.91,0.28),Vector2(0.48,0.28)]),0.14,0.035,rim,gold,amber)
	for i in 7:
		var angle := PI*float(i)/6.0
		_rod("FacetedGlassRib",Vector3(cos(angle)*0.57,-0.63,sin(angle)*0.57),Vector3(cos(angle)*0.57,0.47,sin(angle)*0.57),0.027,gold,5)
	_lathe("FoamTop",[Vector2(0.60,0.73),Vector2(0.56,0.90),Vector2(0.35,0.96)],foam,12)
	for i in 8:
		var angle := i*TAU/8.0
		_ball("FoamBubble",Vector3(cos(angle)*0.40,0.91+0.025*(i%3),sin(angle)*0.40),0.21,foam)
	_ball("FoamDrip",Vector3(-0.26,0.63,0.55),0.14,foam)
	_ball("FoamDripTip",Vector3(-0.26,0.42,0.56),0.09,foam)

func _wifi(center: Vector2, depth: float, material: Material) -> void:
	for ring in 3:
		var radius := 0.16+ring*0.18
		var polygon := PackedVector2Array()
		for i in 9:
			polygon.append(center+Vector2.from_angle(PI*0.23+i*PI*0.54/8.0)*radius)
		for i in range(8,-1,-1):
			polygon.append(center+Vector2.from_angle(PI*0.23+i*PI*0.54/8.0)*(radius-0.055))
		_flat_shape("SignalArc",polygon,depth,material)
	_disc("SignalDot",center,0.066,depth,material)

func _detector() -> void:
	var dark := _material(Color("243932"),0.89)
	var green := _material(Color("64775d"),0.77,0.15)
	var edge := _material(Color("abb697"),0.59,0.24)
	_block("ReceiverBody",Vector2(0,0.02),Vector2(1.30,1.78),0.28,green,edge,dark)
	_block("RecessedSignalScreen",Vector2(0,0.36),Vector2(1.01,0.99),0.287,dark,edge,dark)
	_wifi(Vector2(0,0.02),0.295,_lit("a6ebaa"))
	_disc("TuningKnob",Vector2(-0.26,-0.57),0.15,0.35,dark)
	_disc("AmberButton",Vector2(0.30,-0.56),0.09,0.305,_material(Color("e7a65c"),0.62))
	_rod("TelescopicAntenna",Vector3(-0.40,0.84,0),Vector3(-0.49,1.73,0),0.055,edge)
	_ball("AntennaTip",Vector3(-0.49,1.75,0),0.07,dark)
	_block("ReceiverGrip",Vector2(0,-1.04),Vector2(0.76,0.35),0.23,dark,green,dark)
	for i in 3:
		_block("GripGroove",Vector2(0,-0.94-i*0.1),Vector2(0.65,0.035),0.235,edge,edge,dark)

func _crusher() -> void:
	var orange := _material(Color("b76d39"),0.78,0.15)
	var edge := _material(Color("ecc08a"),0.63,0.24)
	var dark := _material(Color("27343c"),0.86,0.22)
	var steel := _material(Color("92a3ab"),0.52,0.40)
	_block("CrusherHousing",Vector2(0,-0.40),Vector2(2.10,1.15),0.48,orange,edge,dark)
	_block("GrindingChamber",Vector2(0,0.23),Vector2(1.74,0.83),0.489,dark,steel,dark)
	for side: float in [-1.0,1.0]:
		_block("IronFoot",Vector2(side*0.84,-1.09),Vector2(0.35,0.36),0.53,dark,steel,dark)
		_prism("HopperSide",PackedVector2Array([Vector2(side*0.85,0.30),Vector2(side*1.20,1.08),Vector2(side*1.08,1.15),Vector2(side*0.61,0.30)]),0.51,0.035,orange,edge,dark)
	for i in 2:
		var gear_root := Node3D.new()
		gear_root.name = "GrindingRoller%d" % i
		gear_root.position = Vector3(-0.45+i*0.90,0.22,0.52)
		add_child(gear_root)
		var polygon := PackedVector2Array()
		for j in 40:
			polygon.append(Vector2.from_angle(j*TAU/40.0)*(0.46 if j%4 in [0,1] else 0.33))
		var gear := _prism("SteelTeeth",polygon,0.17,0.018,steel,edge,dark)
		gear.reparent(gear_root,false)
		moving_parts.append(gear_root)
	_block("DischargeSlot",Vector2(0,-0.53),Vector2(1.22,0.22),0.493,dark,steel,dark)
	for i in 3:
		_flat_shape("HazardStripe",PackedVector2Array([Vector2(-0.35+i*0.30,-0.88),Vector2(-0.18+i*0.30,-0.88),Vector2(-0.30+i*0.30,-0.69),Vector2(-0.47+i*0.30,-0.69)]),0.489,edge)
	_disc("MotorBolt",Vector2(0.83,-0.40),0.07,0.50,steel)

func _xray() -> void:
	var blue := _material(Color("4e808e"),0.65,0.24)
	var white := _material(Color("c9d5ce"),0.59,0.17)
	var dark := _material(Color("1d333d"),0.86)
	var cyan := _lit("88e0e6")
	_block("ScannerMonitor",Vector2(0,0),Vector2(1.80,1.54),0.34,white,blue,dark)
	_block("XrayGlass",Vector2(-0.06,0.13),Vector2(1.41,0.98),0.352,dark,blue,dark)
	for i in 3:
		var x := -0.50+i*0.44
		_prism("CrystalScan",PackedVector2Array([Vector2(x,0.43),Vector2(x+0.16,0.16),Vector2(x,-0.10),Vector2(x-0.14,0.14)]),0.357,0.025,cyan,white,blue)
	for i in 4:
		_flat_shape("ScanLine",_rectangle(Vector2(-0.67,-0.25+i*0.19),Vector2(0.55,-0.24+i*0.19)),0.391,_material(Color("315762"),0.83))
	_block("ScannerStand",Vector2(0,-0.99),Vector2(0.35,0.44),0.26,blue,white,dark)
	_block("ScannerFoot",Vector2(0,-1.19),Vector2(1.34,0.18),0.47,dark,blue,dark)
	_prism("CarryHandle",PackedVector2Array([Vector2(-0.62,0.76),Vector2(-0.62,1.13),Vector2(0.60,1.13),Vector2(0.60,0.76),Vector2(0.40,0.76),Vector2(0.40,0.94),Vector2(-0.42,0.94),Vector2(-0.42,0.76)]),0.13,0.025,blue,white,dark)
	_disc("ScanControl",Vector2(0.57,-0.56),0.08,0.36,cyan)

func _pin() -> void:
	var steel := _material(Color("697c88"),0.53,0.45)
	var light := _material(Color("d0d9d3"),0.43,0.4)
	var dark := _material(Color("293c49"),0.72,0.3)
	var brass := _material(Color("c9a65e"),0.61,0.3)
	_prism("ForgedSplittingWedge",PackedVector2Array([Vector2(-0.23,0.58),Vector2(0.23,0.58),Vector2(0.17,-0.66),Vector2(0,-1.28),Vector2(-0.17,-0.66)]),0.20,0.035,steel,light,dark)
	_lathe("StrikingCap",[Vector2(0.26,0.48),Vector2(0.43,0.57),Vector2(0.44,0.79),Vector2(0.34,0.90)],brass,8)
	for i in 3:
		_block("DepthNotch",Vector2(0,0.32-i*0.25),Vector2(0.37,0.038),0.204,dark,light,dark)
	_flat_shape("ForgedBevel",PackedVector2Array([Vector2(-0.16,0.4),Vector2(-0.12,-0.64),Vector2(0,-1.17),Vector2(-0.01,-0.58),Vector2(-0.07,0.4)]),0.206,light)

func _detonator() -> void:
	var red := _material(Color("9d493b"),0.85)
	var edge := _material(Color("d88c69"),0.66)
	var dark := _material(Color("24333a"),0.84,0.2)
	var brass := _material(Color("d0a655"),0.58,0.3)
	var iron := _material(Color("91a8ad"),0.44,0.45)
	_block("BlastingBox",Vector2(0,-0.32),Vector2(1.54,1.28),0.47,red,edge,dark)
	for side: float in [-1.0,1.0]:
		_block("CornerBand",Vector2(side*0.68,-0.32),Vector2(0.14,1.35),0.49,dark,iron,dark)
		_disc("CornerBolt",Vector2(side*0.68,-0.78),0.06,0.505,iron)
	_block("MetalLid",Vector2(0,0.35),Vector2(1.66,0.16),0.51,dark,iron,dark)
	_rod("PlungerSleeve",Vector3(0,0.36,0),Vector3(0,0.68,0),0.16,brass)
	plunger = Node3D.new()
	plunger.name = "BlastingPlunger"
	add_child(plunger)
	var shaft := _rod("PlungerShaft",Vector3(0,0.46,0),Vector3(0,1.32,0),0.085,iron)
	shaft.reparent(plunger,false)
	var handle := _rod("THandle",Vector3(-0.63,1.32,0),Vector3(0.63,1.32,0),0.13,dark)
	handle.reparent(plunger,false)
	_prism("WarningPlate",PackedVector2Array([Vector2(0,0.02),Vector2(0.37,-0.59),Vector2(-0.37,-0.59)]),0.485,0.018,brass,edge,dark)
	_flat_shape("LightningMark",PackedVector2Array([Vector2(0.02,-0.16),Vector2(-0.12,-0.35),Vector2(-0.01,-0.34),Vector2(-0.04,-0.48),Vector2(0.13,-0.28),Vector2(0.025,-0.29)]),0.49,dark)
	var cord := _material(Color("bf823c"),0.93)
	for i in 16:
		var a := Vector3(0.82+sin(i*TAU/16.0)*0.20,-0.58+cos(i*TAU/16.0)*0.27,0.28)
		var b := Vector3(0.82+sin((i+1)*TAU/16.0)*0.20,-0.58+cos((i+1)*TAU/16.0)*0.27,0.28)
		_rod("FuseCable",a,b,0.036,cord,5)
