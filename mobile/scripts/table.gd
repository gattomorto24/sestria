extends Node3D

const Surface = preload("res://assets/materials/surface.gdshader")
const BOWL_Z := [2.35,-2.35]
const LANE_ORDER := [0,2,1,3,4]
const LANE_NAMES := ["ASCE","ELMI","FRECCE","SCUDI","MANI"]
const LANE_SPACING := 1.04
var lanes: Node3D
const FLOOR_Y := 0.104
const RADIUS := 1.0
var rng := RandomNumberGenerator.new()
var wood: Material
var dark_wood: Material
var rim_wood: Material
var linen: Material
var shale: Material
var bronze: Material
var gold: Material
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
var primitive_cache := {}
var stone_batches: Array[MultiMeshInstance3D] = []
var token_batches: Array[MultiMeshInstance3D] = []
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
	hover_emission = plain("#6af0cc")
	hover_emission.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_emission.emission_enabled = true
	hover_emission.emission = Color("#6af0cc")
	face_shape = PlaneMesh.new()
	face_shape.size = Vector2.ONE * .46
	figure_mesh = rounded_cube(1,.08)
	make_environment()
	make_room()
	make_table()
	make_lanes()
	for side in 2:
		make_bowl(side)
		make_counters(side)
	coin = Node3D.new()
	add_child(coin)
	cylinder(coin,Vector3.ZERO,.16,.04,gold,16)
	update_counters([15,15],[0,0],0)
	batch_static.call_deferred()

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
	var cache_key := "box:"+str(size)
	if not primitive_cache.has(cache_key):
		var shape := BoxMesh.new()
		shape.size = size
		primitive_cache[cache_key] = shape
	return mesh(parent,primitive_cache[cache_key],p,material)

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
	env.ssao_enabled = false
	env.ssao_radius = .29
	env.ssao_intensity = 1.05
	env.ssil_enabled = false
	env.glow_enabled = false
	env.glow_intensity = .34
	env.fog_enabled = true
	env.fog_light_color = Color("#594637")
	env.fog_density = .004
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
	fill.shadow_enabled = not low
	key.shadow_enabled = false
	key.visible = true
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = .75 if low else .9

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
	for i in 8:
		var plank: ShaderMaterial = wood.duplicate()
		plank.set_shader_parameter("grain_offset",Vector2(.13*i,.37*i))
		plank.set_shader_parameter("tint",Color("#ffebcf").darkened(rng.randf_range(0,.14)))
		box(self,Vector3((i-3.5)*.82,-.127,0),Vector3(.814,.20,8.02),plank)
	box(self,Vector3(0,-.018,0),Vector3(5.74,.04,7.35),linen)
	collision(self,Vector3(0,-.065,0),Vector3(6.6,.13,8.02))
	var red := surface("#562e23","#9a4a32",1,.95)
	var ochre := surface("#9a6134","#be9b5d",1,.91)
	for z in [-3.58,3.58]:
		box(self,Vector3(0,.005,z),Vector3(5.76,.009,.142),red)
		for edge in [-.068,.068]:
			box(self,Vector3(0,.011,z+edge),Vector3(5.77,.005,.011),ochre)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 35:
			var x := (i-17)*.166
			for half_side in [-1,1]:
				var a := Vector3(x-.072,.017,z)
				var b := Vector3(x,.017,z+.047*half_side)
				var c := Vector3(x+.072,.017,z)
				var d := Vector3(x,.017,z+.024*half_side)
				tri(st,a,b,d,Vector3.UP)
				tri(st,b,c,d,Vector3.UP)
		mesh(self,st.commit(),Vector3.ZERO,ochre)
	for x in [-2.86,2.86]:
		box(self,Vector3(x,-.042,0),Vector3(.035,.135,7.35),linen)
	make_candle(Vector3(2.9,0,-3.3),.84)
	make_candle(Vector3(-2.9,0,3.3),.29)

func lane_x(symbol: int) -> float:
	return (LANE_ORDER.find(symbol)-2)*LANE_SPACING

func make_lanes() -> void:
	lanes = Node3D.new()
	add_child(lanes)
	var badge := PlaneMesh.new()
	badge.size = Vector2(.42,.42)
	for symbol in LANE_ORDER:
		var x := lane_x(symbol)
		cylinder(lanes,Vector3(x,.025,0),.29,.025,gold,16)
		mesh(lanes,badge,Vector3(x,.043,0),mark("res://assets/icons/face_%d.svg" % symbol))
		if symbol != LANE_ORDER[-1]:
			for z in [-.66,.66]:
				box(lanes,Vector3(x+.52,.006,z),Vector3(.008,.005,.8),bronze)
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
	var carving := Node3D.new()
	add_child(carving)
	carving.position = p
	carving.scale = Vector3(1.2,1,1.2)
	mesh(carving,preload("res://assets/models/bowl.res"),Vector3.ZERO,rim_wood)
	var bowl_grain := wood.duplicate() as ShaderMaterial
	bowl_grain.set_shader_parameter("tiling",Vector2(.68,.43))
	bowl_grain.set_shader_parameter("grain_offset",Vector2(.23+side*.39,.64))
	var bottom := cylinder(self,p+Vector3.UP*(FLOOR_Y-.0085),1.13,.018,bowl_grain,64)
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
	floor_shape.radius = 1.2
	floor_shape.height = .09
	add_collider(boundary,floor_shape,Vector3.UP*(FLOOR_Y-.045))
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(.26,.65,.16)
	for i in 32:
		var a := TAU*i/32.0
		add_collider(boundary,wall_shape,Vector3(sin(a)*1.27,.40,cos(a)*1.27),a)
	var trim := surface("#673417","#ba8144",2,.57,7.0)
	for y in [.088,.259]:
		mesh(carving,lathe([[.968,y-.013],[1.012,y],[.97,y+.014]],64),Vector3.ZERO,trim)
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
			var start := n*1.009+Vector3.UP*ay
			var end := Vector3(sin(b)*1.009,by,cos(b)*1.009)
			tri(pattern,start,end,end+Vector3.UP*.009,n)
			tri(pattern,start,end+Vector3.UP*.009,start+Vector3.UP*.009,n)
	mesh(carving,pattern.commit(),Vector3.ZERO,trim)

func make_counters(side: int) -> void:
	var mirror := 1.0 if side == 0 else -1.0
	var shared_stone := SphereMesh.new()
	shared_stone.radius = .11
	shared_stone.height = .16
	shared_stone.radial_segments = 8
	shared_stone.rings = 3
	for i in 15:
		var stone := Node3D.new()
		add_child(stone)
		stone.position = Vector3(-2.32+(i%3)*.25,.12,BOWL_Z[side]-.48+(i/3)*.25)
		stone.scale = Vector3(.78,.55,.92)
		stone.rotation.y = rng.randf_range(-PI,PI)
		stones[side].append(stone)
	var shared_token := CylinderMesh.new()
	shared_token.top_radius = .13
	shared_token.bottom_radius = .13
	shared_token.height = .04
	shared_token.radial_segments = 8
	for i in 40:
		var token := Node3D.new()
		add_child(token)
		token.position = Vector3(1.78+(i/10)*.25,.07+(i%10)*.023,BOWL_Z[side])
		tokens[side].append(token)
	stone_batches.append(make_batch(shared_stone,shale,stones[side]))
	var token_mesh := ArrayMesh.new()
	var base := BoxMesh.new()
	base.size = Vector3(.196,.018,.196)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(base,0,Transform3D.IDENTITY)
	st.set_material(bronze)
	st.commit(token_mesh)
	var token_plate := BoxMesh.new()
	token_plate.size = Vector3(.173,.009,.173)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(token_plate,0,Transform3D(Basis.IDENTITY,Vector3(0,.012,0)))
	st.set_material(gold)
	st.commit(token_mesh)
	token_batches.append(make_batch(token_mesh,null,tokens[side]))
	for i in 3:
		var root := StaticBody3D.new()
		root.collision_layer = 4
		root.collision_mask = 0
		root.set_meta("slot",i)
		root.set_meta("side",side)
		add_child(root)
		root.position = Vector3(mirror*(1.62+i*.5),.09,BOWL_Z[side]+mirror*.6)
		var shape := BoxShape3D.new()
		shape.size = Vector3(.43,.2,.64)
		var col := CollisionShape3D.new()
		col.shape = shape
		root.add_child(col)
		mesh(root,figure_mesh,Vector3.ZERO,rim_wood).scale = Vector3(.39,.06,.60)
		var plate := PlaneMesh.new()
		plate.size = Vector2(.40,.62)
		mesh(root,plate,Vector3.UP*.045,mark("res://assets/icons/favor_00.svg"))
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
		if stone_batches.size() == 2:
			stone_batches[side].multimesh.visible_instance_count = clampi(hp[side],0,15)
			token_batches[side].multimesh.visible_instance_count = clampi(gold_count[side],0,40)
		for i in stones[side].size():
			stones[side][i].visible = i < hp[side]
		for i in tokens[side].size():
			tokens[side][i].visible = i < gold_count[side]
	coin.position = Vector3(-2.62 if initiative == 0 else 2.62,.12,
		BOWL_Z[initiative]+(.83 if initiative == 0 else -.83))

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

func make_batch(shape: Mesh, material: Material, anchors: Array) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = MultiMesh.new()
	instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instance.multimesh.mesh = shape
	instance.multimesh.instance_count = anchors.size()
	for i in anchors.size():
		instance.multimesh.set_instance_transform(i,anchors[i].transform)
	instance.material_override = material
	add_child(instance)
	return instance

func batch_static() -> void:
	var groups := {}
	var protected: Array = [coin,lanes]
	protected.append_array(candle_flames)
	for side in 2:
		protected.append_array(figures[side])
		protected.append_array(stones[side])
		protected.append_array(tokens[side])
	for node: MeshInstance3D in find_children("*","MeshInstance3D",true,false):
		var parent: Node = node
		var movable := false
		while parent != self:
			if parent in protected:
				movable = true
				break
			parent = parent.get_parent()
		if movable or node.mesh == null:
			continue
		var key_name := str(node.mesh.get_rid())+str(node.material_override.get_rid() if node.material_override else RID())
		if not groups.has(key_name):
			groups[key_name]=[]
		groups[key_name].append(node)
	for group: Array in groups.values():
		if group.size() < 2:
			continue
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = MultiMesh.new()
		instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		instance.multimesh.mesh = group[0].mesh
		instance.multimesh.instance_count = group.size()
		instance.material_override = group[0].material_override
		add_child(instance)
		for i in group.size():
			instance.multimesh.set_instance_transform(i,global_transform.affine_inverse()*group[i].global_transform)
			group[i].queue_free()
