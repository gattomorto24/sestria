extends Node3D

const Platform = preload("res://scripts/platform.gd")
const Surface = preload("res://assets/materials/surface.gdshader")
const BOWL_Z := [2.22,-2.22]
const LANE_ORDER := [0,2,1,3,4]
const LANE_NAMES := ["ASCE","ELMI","FRECCE","SCUDI","MANI"]
const LANE_SPACING := 1.37
var lanes: Node3D
const FLOOR_Y := 0.104
const RADIUS := 1.0
var rng := RandomNumberGenerator.new()
var wood: ShaderMaterial
var dark_wood: ShaderMaterial
var rim_wood: ShaderMaterial
var linen: ShaderMaterial
var shale: ShaderMaterial
var bronze: ShaderMaterial
var gold: ShaderMaterial
var env: Environment
var key: OmniLight3D
var fill: DirectionalLight3D
var low := false
var stones := [[],[]]
var tokens := [[],[]]
var figures := [[],[]]
var coin: Node3D
var candle_flames: Array[Node3D] = []
var hover_emission: StandardMaterial3D
var mark_materials := {}
var figure_mesh: Mesh
var face_shape: PlaneMesh

func _ready() -> void:
	rng.seed = 1467
	wood = preload("res://assets/materials/wood.tres")
	dark_wood = preload("res://assets/materials/dark_wood.tres")
	rim_wood = preload("res://assets/materials/rim_wood.tres")
	linen = preload("res://assets/materials/linen.tres")
	shale = preload("res://assets/materials/shale.tres")
	bronze = preload("res://assets/materials/bronze.tres")
	gold = preload("res://assets/materials/gold.tres")
	hover_emission = plain("#ffe5a0",.32)
	hover_emission.emission_enabled = true
	hover_emission.emission = Color("#f4cc71")
	hover_emission.emission_energy_multiplier = 1.1
	face_shape = PlaneMesh.new()
	face_shape.size = Vector2.ONE * .284
	figure_mesh = rounded_cube(1,.09)
	make_environment()
	make_room()
	make_table()
	make_lanes()
	for side in 2:
		make_bowl(side)
		make_counters(side)
	coin = Node3D.new()
	add_child(coin)
	var disk := cylinder(coin,Vector3(0,.027,0),.133,.04,bronze,32)
	disk.rotation.y = .3
	make_rosette(coin,Vector3(0,.049,0),.097, gold)
	update_counters([15,15],[0,0],0)

func surface(a: String,b: String,kind: int,roughness: float, frequency := 1.0, metallic := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Surface
	m.set_shader_parameter("low",Color(a))
	m.set_shader_parameter("high",Color(b))
	m.set_shader_parameter("material_kind",kind)
	m.set_shader_parameter("rough",roughness)
	m.set_shader_parameter("metal",metallic)
	m.set_shader_parameter("scale_factor",frequency)
	return m

func plain(color: String, roughness := .72) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = roughness
	return m

func mesh(parent: Node3D, shape: Mesh, p: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	parent.add_child(node)
	node.position = p
	return node

func box(parent: Node3D, p: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent,shape,p,material)

func cylinder(parent: Node3D,p: Vector3,r: float,h: float,m: Material,segments := 32,r_top := -1.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.radial_segments = segments
	shape.rings = 0
	shape.top_radius = r if r_top < 0 else r_top
	shape.bottom_radius = r
	shape.height = h
	return mesh(parent,shape,p,m)

func sphere(parent: Node3D,p:Vector3,r:float,m:Material,s:Vector3) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = r
	shape.height = r*2
	shape.radial_segments = 20
	shape.rings = 10
	var node := mesh(parent,shape,p,m)
	node.scale = s
	return node

func collision(parent: Node3D,p: Vector3,s: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var material := PhysicsMaterial.new()
	material.friction = .67
	material.bounce = .12
	body.physics_material_override = material
	parent.add_child(body)
	body.position = p
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = s
	add_collider(body,shape,Vector3.ZERO)
	return body

func add_collider(body: StaticBody3D, shape: Shape3D, at: Vector3, yaw := 0.0) -> void:
	var hull := CollisionShape3D.new()
	hull.shape = shape
	body.add_child(hull)
	hull.position = at
	hull.rotation.y = yaw

func make_environment() -> void:
	var world := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#100d10")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#acc7cc")
	env.ambient_light_energy = .52
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.ssao_enabled = not OS.has_feature("android")
	env.ssao_radius = .29
	env.ssao_intensity = 1.05
	env.ssil_enabled = false
	env.glow_enabled = not OS.has_feature("android")
	env.glow_intensity = .34
	env.fog_enabled = true
	env.fog_light_color = Color("#594637")
	env.fog_density = .004
	# Compatibility (web) applicherebbe la nebbia anche al fondo, che deve restare scuro come sul desktop.
	if Platform.is_web():
		env.fog_sky_affect = 0.0
	world.environment = env
	add_child(world)
	fill = DirectionalLight3D.new()
	fill.light_energy = .74
	fill.light_color = Color("#c0d7ff")
	fill.rotation_degrees = Vector3(-56,-25,0)
	fill.shadow_enabled = true
	fill.directional_shadow_max_distance = 19.0
	fill.light_angular_distance = 1.8
	add_child(fill)
	key = lamp(Vector3(3.1,3.25,-.7),"#ffbd79",3.52,9.4,true)
	lamp(Vector3(-3.4,2.2,2.7),"#87adc8",1.3,7.0,false)
	lamp(Vector3(.1,2.7,-4.1),"#e69a52",2.2,7.0,false)

func lamp(pos:Vector3, tint:String, energy:float, reach:float, shadow:bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color(tint)
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.24
	light.shadow_enabled = shadow
	light.light_size = .22
	add_child(light)
	return light

func quality(reduced: bool) -> void:
	low = reduced
	var advanced: bool = not OS.has_feature("android") and ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method") != "gl_compatibility"
	env.ssao_enabled = not low and advanced
	env.glow_enabled = not low and advanced
	env.fog_enabled = not low
	key.shadow_enabled = not low
	fill.light_angular_distance = 0.0 if low else 1.8
	get_viewport().msaa_3d = Viewport.MSAA_2X if low else Viewport.MSAA_4X
	get_viewport().scaling_3d_scale = .89 if low else 1.0

func make_room() -> void:
	for i in 16:
		box(self,Vector3((i-7.5)*.82,-1.04,0),Vector3(.805,.14,14),dark_wood)
	for i in 12:
		var beam := box(self,Vector3((i-5.5)*1.05,.8,-5.27),Vector3(1.032,4.0,.28),dark_wood)
		beam.rotate_z(rng.randf_range(-.015,.015))
	for x in [-4.2,-.65,2.9,5.2]:
		box(self,Vector3(x,.95,-5.02),Vector3(.28,4.7,.35),wood)
	box(self,Vector3(0,1.8,-4.97),Vector3(12,.2,.28),wood)
	for z in [-4.20,4.20]:
		box(self,Vector3(0,-.51,z),Vector3(3.95,.16,.47),wood)
		for x in [-1.42,1.42]:
			box(self,Vector3(x,-.8,z),Vector3(.27,.56,.38),dark_wood)
	var clay := surface("#402117","#976244",2,.84,1.8)
	for p in [Vector3(3.7,-.88,-4.46),Vector3(4.44,-.88,-4.49),Vector3(-3.7,-.88,-4.51)]:
		var pot := lathe([[.02,0],[.22,0],[.35,.18],[.37,.40],[.29,.62],[.19,.67],[.20,.73],
			[.22,.76],[.16,.77],[.142,.67],[.235,.48],[.245,.24],[.02,.15]],32)
		var obj := mesh(self,pot,p,clay)
		obj.scale *= rng.randf_range(.8,1.2)

func make_table() -> void:
	for i in 11:
		var plank_mat: ShaderMaterial = wood.duplicate()
		plank_mat.set_shader_parameter("grain_offset", Vector2(.13*i,.37*i))
		plank_mat.set_shader_parameter("tint", Color("#ffebcf").darkened(rng.randf_range(0,.18)))
		box(self,Vector3((i-5)*.82,-.127,0),Vector3(.814,.20,7.80),plank_mat)
	for x in [-4.24,4.24]:
		for z in [-3.40,3.40]:
			var leg := box(self,Vector3(x,-.56,z),Vector3(.28,.89,.35),dark_wood)
			leg.rotate_z(signf(x)*.035)
	box(self,Vector3(0,-.018,0),Vector3(8.12,.04,7.13),linen)
	collision(self,Vector3(0,-.065,0),Vector3(9.02,.13,7.79))
	var red := surface("#562e23","#9a4a32",1,.95)
	var ochre := surface("#9a6134","#be9b5d",1,.91)
	for z in [-3.49,3.49]:
		box(self,Vector3(0,.005,z),Vector3(8.14,.009,.142),red)
		for edge in [-.068,.068]:
			box(self,Vector3(0,.011,z+edge),Vector3(8.15,.005,.011),ochre)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 49:
			var x := (i-24)*.166
			for half_side in [-1,1]:
				var a := Vector3(x-.072,.017,z)
				var b := Vector3(x,.017,z+.047*half_side)
				var c := Vector3(x+.072,.017,z)
				var d := Vector3(x,.017,z+.024*half_side)
				tri(st,a,b,d,Vector3.UP)
				tri(st,b,c,d,Vector3.UP)
		mesh(self,st.commit(),Vector3.ZERO,ochre)
	for x in [-4.06,4.06]:
		box(self,Vector3(x,-.042,0),Vector3(.035,.135,7.13),linen)
	var iron := plain("#342618",.47)
	iron.metallic = .69
	for x in [-4.38,4.38]:
		for z in [-3.69,3.69]:
			cylinder(self,Vector3(x,-.02,z),.04,.017,iron,10)
	make_mug(Vector3(-3.40,0,-3.11))
	make_candle(Vector3(3.37,0,-3.06),.84)
	make_candle(Vector3(3.56,0,2.41),.29)

func lane_x(symbol: int) -> float:
	return (LANE_ORDER.find(symbol)-2)*LANE_SPACING

func make_lanes() -> void:
	lanes = Node3D.new()
	lanes.name = "Categorie"
	add_child(lanes)
	var ink := plain("#31585b")
	var brass := plain("#9d7d51",.66)
	var dark := plain("#1e393a",.76)
	var badge := PlaneMesh.new()
	badge.size = Vector2(.31,.31)
	for index in LANE_ORDER.size():
		var symbol: int = LANE_ORDER[index]
		var x := lane_x(symbol)
		box(lanes,Vector3(x,.008,0),Vector3(1.14,.008,.39),dark)
		box(lanes,Vector3(x,.014,-.19),Vector3(1.14,.006,.013),brass)
		box(lanes,Vector3(x,.014,.19),Vector3(1.14,.006,.013),brass)
		box(lanes,Vector3(x-.39,.017,0),Vector3(.34,.006,.32),brass)
		mesh(lanes,badge,Vector3(x-.39,.022,0),mark("res://assets/icons/face_%d.svg" % symbol))
		var title := Label3D.new()
		title.text = LANE_NAMES[index]
		title.font_size = 38
		title.pixel_size = .0031
		title.outline_size = 0
		title.modulate = Color("#f0c98f")
		title.rotation.x = -PI*.5
		lanes.add_child(title)
		title.position = Vector3(x+.16,.022,0)
		if index < LANE_ORDER.size()-1:
			for sign_side in [-1,1]:
				box(lanes,Vector3(x+LANE_SPACING*.5,.01,sign_side*.79),Vector3(.014,.005,.92),ink)
	lanes.hide()

func make_mug(p: Vector3) -> void:
	for i in 12:
		var a := TAU*i/12.0
		var stave := box(self,p+Vector3(.208*sin(a),.263,.208*cos(a)),Vector3(.106,.52,.043),wood)
		stave.rotation.y = a
		stave.rotation.x = .045
	cylinder(self,p+Vector3.UP*.028,.199,.055,dark_wood)
	for y in [.126,.373]:
		mesh(self,lathe([[.229,y-.021],[.234,y-.018],[.234,y+.018],[.229,y+.02]],32),p,bronze)
	var handle := torus(self,p+Vector3(-.235,.275,0),.12,.17,dark_wood)
	handle.rotate_z(PI*.5)

func make_candle(p: Vector3,stand: float) -> void:
	var wax := surface("#8e5728","#f3c77d",2,.71,2.5)
	cylinder(self,p+Vector3.UP*.033,.16,.064,bronze)
	if stand>.5:
		cylinder(self,p+Vector3.UP*.24,.13,.42,dark_wood,9,.073)
	var y := .46 if stand>.5 else .05
	cylinder(self,p+Vector3.UP*y,.124,.04,bronze)
	cylinder(self,p+Vector3.UP*(y+.10),.072,.205,wax,24,.067)
	for i in 4:
		var a := i*1.77
		sphere(self,p+Vector3(.065*sin(a),y+.15,.065*cos(a)),.021,wax,Vector3(.48,2.2,.48))
	cylinder(self,p+Vector3.UP*(y+.211),.012,.035,dark_wood,8)
	var flame := plain("#ffaf42",.6)
	flame.emission_enabled = true
	flame.emission = Color("#ffb539")
	flame.emission_energy_multiplier = 3.3
	candle_flames.append(sphere(self,p+Vector3.UP*(y+.274),.052,flame,Vector3(.51,1.53,.47)))
	lamp(p+Vector3.UP*(y+.42),"#ff9d47",.37,2.25,false)

func make_bowl(side: int) -> void:
	var p := Vector3(0,0,BOWL_Z[side])
	mesh(self,preload("res://assets/models/bowl.res"),p,rim_wood)
	var bowl_grain := wood.duplicate() as ShaderMaterial
	bowl_grain.set_shader_parameter("tiling",Vector2(.68,.43))
	bowl_grain.set_shader_parameter("grain_offset",Vector2(.23+side*.39,.64))
	var bottom := cylinder(self,p+Vector3.UP*(FLOOR_Y-.0085),.758,.018,bowl_grain,64)
	bottom.name = "Fondo"
	bottom.rotation.y = .34 + side*.41
	var boundary := StaticBody3D.new()
	boundary.name = "CiotolaFisica"
	add_child(boundary)
	boundary.position = p
	var material := PhysicsMaterial.new()
	material.friction = .67
	material.bounce = .11
	boundary.physics_material_override = material
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = .975
	floor_shape.height = .09
	add_collider(boundary,floor_shape,Vector3.UP*(FLOOR_Y-.045))
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(.225,.46,.16)
	for i in 32:
		var a := TAU*i/32.0
		add_collider(boundary,wall_shape,Vector3(sin(a)*1.04,.317,cos(a)*1.04),a)
	var trim := surface("#673417","#ba8144",2,.57,7.0)
	for y in [.088,.259]:
		mesh(self,lathe([[.968,y-.013],[1.012,y],[.97,y+.014]],64),p,trim)
	var pattern := SurfaceTool.new()
	pattern.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		for i in 256:
			var a := TAU*i/256.0
			var b := TAU*(i+1)/256.0
			var offset := k*PI
			var ay := .174 + .043*sin(a*20.0+offset)
			var by := .174 + .043*sin(b*20.0+offset)
			var n := Vector3(sin(a),0,cos(a))
			var start := p+n*1.009+Vector3.UP*ay
			var end := p+Vector3(sin(b)*1.009,by,cos(b)*1.009)
			tri(pattern,start,end,end+Vector3.UP*.009,n)
			tri(pattern,start,end+Vector3.UP*.009,start+Vector3.UP*.009,n)
	mesh(self,pattern.commit(),Vector3.ZERO,trim)

func make_counters(side: int) -> void:
	var sign_side := 1.0 if side == 0 else -1.0
	for i in 15:
		var p := Vector3(-sign_side*(1.62+(i%5)*.205),.046,
			BOWL_Z[side]+sign_side*(.24+(i/5)*.162))
		var stone := sphere(self,p,.103,shale,
			Vector3(rng.randf_range(.60,.83),rng.randf_range(.35,.52),rng.randf_range(.69,.98)))
		stone.rotate_y(rng.randf_range(-PI,PI))
		stone.rotate_z(rng.randf_range(-.32,.32))
		stones[side].append(stone)
	for i in 40:
		var p := Vector3(sign_side*(1.43+(i/8)%4*.245),.012+.020*(i%8),
			BOWL_Z[side]-sign_side*(.57+(i/32)*.235))
		var token := Node3D.new()
		add_child(token)
		token.position = p
		token.rotation.y = rng.randf_range(-.055,.055)
		box(token,Vector3.ZERO,Vector3(.196,.018,.196),bronze)
		box(token,Vector3.UP*.009,Vector3(.173,.009,.173),gold)
		make_rosette(token,Vector3.UP*.015,.049,bronze)
		tokens[side].append(token)
	for i in 3:
		var p := Vector3(sign_side*(1.48+i*.44),.024,BOWL_Z[side]+sign_side*.43)
		var root := StaticBody3D.new()
		root.collision_layer = 4
		root.collision_mask = 0
		root.set_meta("slot",i)
		root.set_meta("side",side)
		add_child(root)
		root.position = p
		root.rotation.y = sign_side * (.10 + .085*i) + (0 if side == 0 else PI)
		var shape := BoxShape3D.new()
		shape.size = Vector3(.32,.14,.51)
		var col := CollisionShape3D.new()
		col.shape = shape
		root.add_child(col)
		mesh(root,figure_mesh,Vector3.ZERO,rim_wood).scale = Vector3(.27,.043,.445)
		var plate := PlaneMesh.new()
		plate.size = Vector2(.305,.46)
		mesh(root,plate,Vector3.UP*.029,mark("res://assets/icons/favor_00.svg"))
		figures[side].append(root)

func set_figures(sets: Array) -> void:
	for side in 2:
		for i in 3:
			var root: StaticBody3D = figures[side][i]
			var id: String = sets[side][i]
			var index := preload("res://scripts/rules.gd").FAVOR.keys().find(id)
			root.get_child(2).material_override = mark("res://assets/icons/favor_%02d.svg" % index)
			root.set_meta("favor",id)

func update_counters(hp: Array,gold_count: Array,initiative: int) -> void:
	for side in 2:
		for i in stones[side].size():
			stones[side][i].visible = i < hp[side]
		for i in tokens[side].size():
			tokens[side][i].visible = i < gold_count[side]
	coin.position = Vector3(-2.82 if initiative == 0 else 2.78,.006,
		BOWL_Z[initiative]+(.72 if initiative == 0 else -.51))

func make_rosette(parent: Node3D,p: Vector3,r: float,mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 40:
		var a := TAU*i/40.0
		var b := TAU*(i+1)/40.0
		var outer_a := r*(.81+.19*cos(a*4.0))
		var outer_b := r*(.81+.19*cos(b*4.0))
		var va := Vector3(sin(a),0,cos(a))
		var vb := Vector3(sin(b),0,cos(b))
		tri(st,va*outer_a,vb*outer_b,vb*(outer_b-r*.16),Vector3.UP)
		tri(st,va*outer_a,vb*(outer_b-r*.16),va*(outer_a-r*.16),Vector3.UP)
	mesh(parent,st.commit(),p,mat)

func torus(parent: Node3D,p: Vector3,inner:float,outer:float,mat:Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	shape.rings = 24
	shape.ring_segments = 10
	return mesh(parent,shape,p,mat)

func mark(path: String) -> StandardMaterial3D:
	if not mark_materials.has(path):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(path)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = .46
		m.roughness = .87
		mark_materials[path] = m
	return mark_materials[path]

func tri(st: SurfaceTool,a:Vector3,b:Vector3,c:Vector3,n:Vector3) -> void:
	if (b-a).cross(c-a).dot(n) > 0:
		var swap := b
		b = c
		c = swap
	for v in [a,b,c]:
		st.set_normal(n)
		st.add_vertex(v)

func lathe(profile: Array, steps: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in profile.size()-1:
		var low_point: Array = profile[j]
		var high_point: Array = profile[j+1]
		for i in steps:
			var a := TAU*i/steps
			var b := TAU*(i+1)/steps
			var u := Vector3(sin(a),0,cos(a))
			var v := Vector3(sin(b),0,cos(b))
			var radial := (u+v).normalized()
			var n: Vector3 = (radial*(high_point[1]-low_point[1])
				+Vector3.UP*(low_point[0]-high_point[0])).normalized()
			var l := u*float(low_point[0])+Vector3.UP*float(low_point[1])
			var r := v*float(low_point[0])+Vector3.UP*float(low_point[1])
			var t := u*float(high_point[0])+Vector3.UP*float(high_point[1])
			var q := v*float(high_point[0])+Vector3.UP*float(high_point[1])
			tri(st,l,r,q,n)
			tri(st,l,q,t,n)
	return st.commit()

func rounded_cube(size: float, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size*.5
	var core := half-bevel
	var coords := [-half,-core-bevel*.55,-core,core,core+bevel*.55,half]
	for n: Vector3 in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
		var u := Vector3.RIGHT if absf(n.x)<.5 else Vector3.FORWARD
		var v := n.cross(u)
		for i in coords.size()-1:
			for j in coords.size()-1:
				for k: Vector2i in [Vector2i(i,j),Vector2i(i+1,j+1),Vector2i(i+1,j),
					Vector2i(i,j),Vector2i(i,j+1),Vector2i(i+1,j+1)]:
					var p := n*half+u*float(coords[k.x])+v*float(coords[k.y])
					var inner := p.clamp(Vector3.ONE*-core,Vector3.ONE*core)
					var normal := (p-inner).normalized()
					st.set_normal(normal)
					st.add_vertex(inner+normal*bevel)
	return st.commit()
