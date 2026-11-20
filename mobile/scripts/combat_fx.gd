extends Node3D

const Rules = preload("res://scripts/rules.gd")
const BLADE := Color("#ffbe70")
const SHAFT := Color("#e8dca0")
const PARRY := Color("#91e2ef")
const DAMAGE := Color("#f69468")
const SKIN := Color("#ffd7a1")
const CUFF := Color("#c88a45")
const GOLD := Color("#ffd35c")

var table: Node3D
var axe_blade: ArrayMesh
var hand_open: ArrayMesh
var hand_fist: ArrayMesh
var cuff_mesh: BoxMesh
var handle: CylinderMesh
var arrowhead: CylinderMesh
var spark_mesh: SphereMesh
var materials := {}
var random := RandomNumberGenerator.new()
var reduced := false

func setup(board: Node3D) -> void:
	table = board
	axe_blade = blade_mesh()
	hand_open = extrude(PackedVector2Array([
		Vector2(.07,.20),Vector2(.105,.06),Vector2(.12,-.04),
		Vector2(.12,-.14),Vector2(.108,-.17),Vector2(.085,-.17),Vector2(.0675,-.055),
		Vector2(.063,-.22),Vector2(.043,-.25),Vector2(.023,-.22),Vector2(.0125,-.055),
		Vector2(.008,-.25),Vector2(-.012,-.28),Vector2(-.032,-.25),Vector2(-.0425,-.055),
		Vector2(-.047,-.21),Vector2(-.067,-.24),Vector2(-.087,-.21),Vector2(-.095,-.04),
		Vector2(-.15,-.09),Vector2(-.19,-.12),Vector2(-.215,-.11),Vector2(-.22,-.08),
		Vector2(-.19,-.03),Vector2(-.12,.06),Vector2(-.09,.14),Vector2(-.07,.20)]),.022)
	hand_fist = extrude(PackedVector2Array([
		Vector2(.07,.20),Vector2(.11,.06),Vector2(.125,-.04),Vector2(.12,-.11),
		Vector2(.09,-.15),Vector2(.05,-.17),Vector2(0,-.18),Vector2(-.05,-.17),
		Vector2(-.09,-.14),Vector2(-.12,-.08),Vector2(-.16,-.10),Vector2(-.17,-.05),
		Vector2(-.125,-.03),Vector2(-.12,.05),Vector2(-.09,.14),Vector2(-.07,.20)]),.03)
	cuff_mesh = BoxMesh.new()
	cuff_mesh.size = Vector3(.17,.05,.06)
	handle = CylinderMesh.new()
	handle.top_radius = .025
	handle.bottom_radius = .025
	handle.height = .55
	handle.radial_segments = 8
	arrowhead = CylinderMesh.new()
	arrowhead.top_radius = 0.0
	arrowhead.bottom_radius = .063
	arrowhead.height = .17
	arrowhead.radial_segments = 6
	spark_mesh = SphereMesh.new()
	spark_mesh.radius = .025
	spark_mesh.height = .05
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3

func luminous(tint: Color) -> StandardMaterial3D:
	if materials.has(tint):
		return materials[tint]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = .65
	materials[tint] = material
	return material

func visual(parent: Node3D, shape: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func blade_mesh() -> ArrayMesh:
	return extrude(PackedVector2Array([
		Vector2(-.065,-.19),Vector2(.16,-.25),Vector2(.29,-.19),
		Vector2(.35,-.09),Vector2(.31,.005),Vector2(.20,.025),
		Vector2(.11,-.05),Vector2(-.06,-.055)]),.022)

func extrude(outline: PackedVector2Array, half: float) -> ArrayMesh:
	var geometry := SurfaceTool.new()
	geometry.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for i in range(0,triangles.size(),3):
		for face in [-1,1]:
			var a := outline[triangles[i]]
			var b := outline[triangles[i+1]]
			var c := outline[triangles[i+2]]
			table.tri(geometry,Vector3(a.x,half*face,a.y),Vector3(b.x,half*face,b.y),
				Vector3(c.x,half*face,c.y),Vector3.UP*face)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var n := Vector3(b.y-a.y,0,a.x-b.x).normalized()
		var top_a := Vector3(a.x,half,a.y)
		var top_b := Vector3(b.x,half,b.y)
		var bottom_a := Vector3(a.x,-half,a.y)
		var bottom_b := Vector3(b.x,-half,b.y)
		table.tri(geometry,top_a,top_b,bottom_b,n)
		table.tri(geometry,top_a,bottom_b,bottom_a,n)
	return geometry.commit()

func projectile(kind: int, source: Vector3, target: Vector3, blocked: bool, delay: float, speed: float, on_impact: Callable) -> float:
	var root := Node3D.new()
	root.name = "Ascia" if kind == Rules.AXE else "Freccia"
	add_child(root)
	var tint := BLADE if kind == Rules.AXE else SHAFT
	var weapon := Node3D.new()
	root.add_child(weapon)
	var grip := visual(weapon,handle,luminous(tint.darkened(.23)))
	grip.rotation.x = -PI*.5
	if kind == Rules.AXE:
		visual(weapon,axe_blade,luminous(tint))
	else:
		var tip := visual(weapon,arrowhead,luminous(tint))
		tip.position.z = -.33
		tip.rotation.x = -PI*.5
		var fletching := BoxMesh.new()
		fletching.size = Vector3(.11,.035,.125)
		visual(weapon,fletching,luminous(tint)).position.z = .22
	var tracer := BoxMesh.new()
	tracer.size = Vector3(.048,.025,.53 if kind == Rules.ARROW else .39)
	var trail := visual(root,tracer,luminous(tint))
	trail.position = Vector3(0,-.065,.27)
	trail.transparency = .52
	var facing := Vector3(target.x-source.x,0,target.z-source.z).normalized()
	var heading := atan2(-facing.x,-facing.z)
	root.hide()
	var flight := (.46 if kind == Rules.AXE else .33)*speed
	var tween := create_tween().bind_node(root)
	tween.tween_interval(delay*speed)
	tween.tween_callback(root.show)
	tween.tween_method(func(value: float):
		root.position = source.lerp(target,value)
		root.position.y += sin(PI*value)*(.81 if kind == Rules.AXE else .35)
		root.rotation.y = heading
		weapon.rotation.y = TAU*value if kind == Rules.AXE else 0.0
		trail.scale.z = .65 + .65*sin(PI*value)
	,0.0,1.0,flight).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		burst(target,blocked,speed)
		if on_impact.is_valid():
			on_impact.call())
	tween.tween_callback(root.queue_free)
	return delay*speed+flight

func steal_token(source: Vector3, pickup: Vector3, deposit: Vector3, token: Node3D, delay: float,
		speed: float, on_grab: Callable, on_drop: Callable) -> float:
	var root := Node3D.new()
	root.name = "Mano"
	add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	var open := visual(body,hand_open,luminous(SKIN))
	var fist := visual(body,hand_fist,luminous(SKIN))
	fist.hide()
	visual(body,cuff_mesh,luminous(CUFF)).position = Vector3(0,0,.215)
	var tracer := BoxMesh.new()
	tracer.size = Vector3(.2,.02,.4)
	var trail := visual(root,tracer,luminous(SKIN))
	trail.position = Vector3(0,-.04,.3)
	trail.transparency = .6
	var carried := MeshInstance3D.new()
	carried.mesh = table.token_batches[0].multimesh.mesh
	body.add_child(carried)
	carried.position = Vector3(0,-.05,-.07)
	carried.rotation = Vector3.ZERO
	carried.hide()
	var hover_from := pickup+Vector3.UP*.10
	var hover_to := deposit+Vector3.UP*.10
	var head_in := heading_to(source,pickup)
	var head_out := heading_to(pickup,deposit)
	root.hide()
	root.position = source
	root.rotation.y = head_in
	var tween := create_tween().bind_node(root)
	tween.tween_interval(delay*speed)
	tween.tween_callback(root.show)
	tween.tween_method(func(v: float):
		root.position = source.lerp(hover_from,v)
		root.position.y += sin(PI*v)*.55
		root.rotation.y = head_in
		body.rotation.z = sin(TAU*v)*.28
		trail.scale.z = .5+sin(PI*v)
	,0.0,1.0,.42*speed).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		open.hide()
		fist.show()
		carried.show()
		body.rotation.z = 0.0
		burst(pickup,false,speed,GOLD)
		if on_grab.is_valid():
			on_grab.call())
	tween.tween_interval(.12*speed)
	tween.tween_method(func(v: float):
		root.position = hover_from.lerp(hover_to,v)
		root.position.y += sin(PI*v)*.62
		root.rotation.y = lerp_angle(head_in,head_out,smoothstep(0.0,.35,v))
		trail.scale.z = .5+sin(PI*v)
	,0.0,1.0,.52*speed).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		carried.queue_free()
		fist.hide()
		open.show()
		burst(deposit,false,speed,GOLD)
		if on_drop.is_valid():
			on_drop.call())
	tween.tween_interval(.1*speed)
	tween.tween_method(func(v: float):
		root.position = hover_to+Vector3.UP*.45*v
		root.scale = Vector3.ONE*maxf(.01,1.0-v)
	,0.0,1.0,.28*speed).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(root.queue_free)
	return (delay+.42+.12+.52+.1+.28)*speed

func heading_to(from: Vector3, to: Vector3) -> float:
	var facing := Vector3(to.x-from.x,0,to.z-from.z)
	if facing.length() < .001:
		return 0.0
	facing = facing.normalized()
	return atan2(-facing.x,-facing.z)

func burst(point: Vector3, blocked: bool, speed: float, custom := Color.TRANSPARENT) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = point
	var tint := PARRY if blocked else DAMAGE
	if custom.a > 0.0:
		tint = custom
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = .145
	ring_mesh.outer_radius = .167
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 6
	var ring := visual(root,ring_mesh,luminous(tint))
	ring.rotation.x = .66 if blocked else 0.0
	var tween := create_tween().bind_node(root).set_parallel()
	tween.tween_property(ring,"scale",Vector3.ONE*(2.8 if blocked else 2.0),.33*speed)
	tween.tween_property(ring,"transparency",1.0,.33*speed)
	for i in (4 if reduced else 9):
		var mote := visual(root,spark_mesh,luminous(tint))
		var angle := TAU*i/(4.0 if reduced else 9.0)
		var vector := Vector3(cos(angle),random.randf_range(.3,.9),sin(angle))
		tween.tween_property(mote,"position",vector*random.randf_range(.23,.59),.28*speed)
		tween.tween_property(mote,"scale",Vector3.ONE*.01,.29*speed)
	tween.chain().tween_callback(root.queue_free)

func knock_stone(stone: Node3D, speed: float) -> void:
	var shard := MeshInstance3D.new()
	shard.mesh = table.stone_batches[0].multimesh.mesh
	shard.material_override = table.shale
	add_child(shard)
	shard.global_transform = stone.global_transform
	stone.hide()
	var direction := signf(shard.position.x)
	var start := shard.position
	var size_before := shard.scale
	var tween := create_tween().bind_node(shard)
	tween.tween_method(func(progress: float):
		shard.position = start+Vector3(direction*.63*progress,sin(PI*progress)*.33,.22*progress)
		shard.rotation.y += .19
		shard.scale = size_before*(1.0-progress*.93)
		,0.0,1.0,.36*speed)
	tween.tween_callback(shard.queue_free)

func shatter_die(die: Node3D, defense: bool, speed: float) -> void:
	var tint := PARRY if defense else BLADE
	var root := Node3D.new()
	add_child(root)
	root.global_position = die.global_position
	die.hide()
	burst(root.position,defense,speed)
	var fracture := table.plain("#debf86",.63) as StandardMaterial3D
	fracture.emission_enabled = true
	fracture.emission = tint
	fracture.emission_energy_multiplier = .39
	var fragment_mesh := BoxMesh.new()
	fragment_mesh.size = Vector3(.125,.113,.129)
	var flash := visual(root,spark_mesh,luminous(tint))
	flash.scale = Vector3.ONE*6.8
	var tween := create_tween().bind_node(root).set_parallel()
	tween.tween_property(flash,"transparency",1.0,.19*speed)
	tween.tween_property(flash,"scale",Vector3.ONE*.01,.19*speed)
	for i in (5 if reduced else 8):
		var piece := visual(root,fragment_mesh,fracture)
		var octant := Vector3(1 if i & 1 else -1,1 if i & 2 else -1,1 if i & 4 else -1)
		var start := octant*.065
		var travel := Vector3(octant.x*random.randf_range(.28,.65),random.randf_range(.06,.23),
			octant.z*random.randf_range(.28,.65))
		piece.position = start
		piece.rotation = Vector3(random.randf(), random.randf(),random.randf())*.7
		tween.tween_method(func(progress: float):
			piece.position = start + travel*progress
			piece.position.y += sin(PI*progress)*.39
			piece.scale = Vector3.ONE*(1.0-pow(progress,2.0)*.99)
			,0.0,1.0,.47*speed).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(piece,"rotation",octant*(TAU*.56),.48*speed)
		tween.tween_property(piece,"transparency",1.0,.29*speed).set_delay(.17*speed)
	tween.chain().tween_callback(root.queue_free)
