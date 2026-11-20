extends SceneTree

const TableScene = preload("res://scenes/table.tscn")
const Die = preload("res://scripts/die.gd")
const HALF_WIDTH := .148
const MAX_DEPTH := .014
var largest_overlap := 0.0
var pair_samples := 0

func _initialize() -> void:
	call_deferred("run")

func projection(box: Basis, axis: Vector3) -> float:
	return HALF_WIDTH * (absf(box.x.dot(axis)) + absf(box.y.dot(axis)) + absf(box.z.dot(axis)))

func overlap(a: RigidBody3D, b: RigidBody3D) -> float:
	var delta := b.position-a.position
	if delta.length_squared() > .264:
		return 0.0
	var basis_a := a.basis.orthonormalized()
	var basis_b := b.basis.orthonormalized()
	var axes: Array[Vector3] = [basis_a.x,basis_a.y,basis_a.z,basis_b.x,basis_b.y,basis_b.z]
	for i in 3:
		for j in range(3,6):
			var cross_axis := axes[i].cross(axes[j])
			if cross_axis.length_squared() > .000001:
				axes.append(cross_axis.normalized())
	var depth := INF
	for axis in axes:
		var separation := projection(basis_a,axis) + projection(basis_b,axis) - absf(delta.dot(axis))
		if separation <= 0.0:
			return 0.0
		depth = minf(depth,separation)
	return depth

func run() -> void:
	var game := TableScene.instantiate()
	root.add_child(game)
	var random := RandomNumberGenerator.new()
	var rolls := 30
	for round_index in rolls:
		random.seed = 401 + round_index
		var side := round_index%2
		var dice: Array = game.cubes[side]
		var center := Vector3(0,game.table.FLOOR_Y,game.table.BOWL_Z[side])
		var angle := random.randf_range(0.0,TAU)
		for i in dice.size():
			dice[i].launch(center,angle+TAU*i/dice.size(),random)
		for frame in 540:
			await physics_frame
			for i in dice.size():
				for j in range(i+1,dice.size()):
					largest_overlap = maxf(largest_overlap,overlap(dice[i],dice[j]))
					pair_samples += 1
			if frame in [224,321,419]:
				for cube in dice:
					cube.nudge(center,random)
		for cube in dice:
			var before: Transform3D = cube.transform
			cube.stop_roll()
			var offset: Vector3 = cube.position-center
			if cube.transform != before or cube.face != Die.top_face(before.basis) or Vector2(offset.x,offset.z).length() > .98:
				push_error("Dado fuori dalla ciotola o alterato durante l’arresto")
				quit(1)
				return
		game.rack(side,true)
	if game.dice_contact_count == 0 or largest_overlap > MAX_DEPTH:
		push_error("Contatti insufficienti o compenetrazione eccessiva %.5f" % largest_overlap)
		quit(1)
		return
	print("FISICA | %d lanci da sei dadi | %d eventi di contatto | %d coppie controllate | penetrazione massima %.4f" %
		[rolls,game.dice_contact_count,pair_samples,largest_overlap])
	quit()
