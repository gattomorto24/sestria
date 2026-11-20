extends RigidBody3D

const Rules = preload("res://scripts/rules.gd")
const NORMALS := [Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK,Vector3.RIGHT,Vector3.LEFT]
const HEIGHT := .23
var die_id: int
var side: int
var face := 0
var selected := false
var committed := false
var frame: Node3D
var motion: Tween
var last_clack := 0
var rest := Vector3.ZERO
signal clack(place: Vector3)
signal dice_touched

func setup(table: Node3D, i: int, who: int) -> void:
	die_id = i
	side = who
	var faces := SurfaceTool.new()
	faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 6:
		var data := Rules.die(i,j)
		var cell: int = data.kind + (5 if data.gold else 0)
		var basis_face := Basis(Quaternion(Vector3.UP,NORMALS[j]))
		var corners := [Vector3(-.22,.231,-.22),Vector3(.22,.231,-.22),Vector3(.22,.231,.22),Vector3(-.22,.231,.22)]
		var uvs := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
		for k in [0,1,2,0,2,3]:
			faces.set_normal(NORMALS[j])
			faces.set_uv(Vector2((cell+uvs[k].x)/10.,uvs[k].y))
			faces.add_vertex(basis_face*corners[k])
	var marks := MeshInstance3D.new()
	marks.mesh = faces.commit()
	marks.material_override = preload("res://assets/materials/dice_marks.tres")
	add_child(marks)
	frame = Node3D.new()
	add_child(frame)
	# One draw call for the selection halo instead of twelve edge meshes.
	var halo := TorusMesh.new()
	halo.inner_radius = .34
	halo.outer_radius = .37
	halo.rings = 24
	halo.ring_segments = 4
	table.mesh(frame,halo,Vector3(0,-.205,0),table.hover_emission)
	frame.hide()
	body_entered.connect(_impact)

func _impact(other: Node) -> void:
	if not freeze and other is RigidBody3D:
		dice_touched.emit()
	var tick := Time.get_ticks_msec()
	if not freeze and linear_velocity.length() > .39 and tick - last_clack > 75:
		clack.emit(global_position)
		last_clack = tick

static func top_face(b: Basis) -> int:
	var best := -2.0
	var index := 0
	for j in NORMALS.size():
		var score: float = (b*NORMALS[j]).dot(Vector3.UP)
		if score > best:
			best = score
			index = j
	return index

func launch(center: Vector3, start_angle: float, random: RandomNumberGenerator) -> void:
	if motion:
		motion.kill()
	var radial := Vector3(cos(start_angle),0,sin(start_angle))
	var tangent := Vector3(-radial.z,0,radial.x)
	rotation = Vector3(random.randf_range(-PI,PI),random.randf_range(-PI,PI),random.randf_range(-PI,PI))
	position = center + radial*.72 + Vector3.UP*random.randf_range(.82,.98)
	reset_physics_interpolation()
	freeze = false
	sleeping = false
	linear_velocity = -radial*random.randf_range(.83,1.39) + tangent*random.randf_range(-.54,.54)
	angular_velocity = Vector3(random.randf_range(-12,12),random.randf_range(-14,14),random.randf_range(-13,13))
	frame.hide()

func has_settled(floor_y: float) -> bool:
	return position.y <= floor_y + HEIGHT + .031 and resting() and top_alignment() >= .985

func resting() -> bool:
	return sleeping or (linear_velocity.length_squared() < .018 and angular_velocity.length_squared() < .10)

func top_alignment() -> float:
	return (basis*NORMALS[top_face(basis)]).y

func nudge(center: Vector3, random: RandomNumberGenerator) -> void:
	if not resting() or has_settled(center.y):
		return
	var radial := Vector3(center.x-position.x,0,center.z-position.z)
	var sideways := Vector3(-radial.z,0,radial.x)
	sleeping = false
	apply_central_impulse(radial.normalized()*.064 + sideways.normalized()*random.randf_range(-.05,.05)
		+Vector3.UP*.079)
	apply_torque_impulse(Vector3(random.randf_range(-.015,.015),0,random.randf_range(-.015,.015)))

func stop_roll() -> void:
	# Keep the transform resolved by the physics solver, including its yaw.
	face = top_face(basis)
	rest = position
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func arrange(target: Vector3, face_index: int, duration := .28, lift := 0.0) -> void:
	if motion:
		motion.kill()
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	face = face_index
	var start := position
	rest = target
	var normal: Vector3 = NORMALS[face]
	var desired := Quaternion(Vector3.UP,.08 if side == 0 else PI-.08)*Quaternion(normal,Vector3.UP)
	if duration <= 0:
		position = target
		quaternion = desired
		reset_physics_interpolation()
	else:
		motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		if lift > 0.0:
			motion.tween_method(func(t: float):
				position = start.lerp(target,t)+Vector3.UP*sin(PI*t)*lift
			,0.0,1.0,duration)
		else:
			motion.tween_property(self,"position",target,duration)
		motion.tween_property(self,"quaternion",desired,duration)

func select(value: bool) -> void:
	selected = value
	frame.visible = value
	frame.top_level = true
	frame.global_position = global_position
	frame.global_rotation = Vector3.ZERO
	if motion:
		motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.tween_property(self,"position",rest+Vector3.UP*(.13 if value else 0.0),.17)

func parry(speed: float) -> void:
	if motion:
		motion.kill()
	frame.show()
	motion = create_tween().set_trans(Tween.TRANS_QUAD)
	var recoil := Vector3(0,.075,.095 if side == 0 else -.095)
	motion.tween_property(self,"position",rest+recoil,.075*speed).set_ease(Tween.EASE_OUT)
	motion.tween_property(self,"position",rest,.19*speed).set_ease(Tween.EASE_OUT)
	motion.tween_callback(frame.hide)
