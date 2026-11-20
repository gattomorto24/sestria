extends Node3D

const Rules = preload("res://scripts/rules.gd")
const AI = preload("res://scripts/ai.gd")
const Die = preload("res://scenes/die.tscn")
const DieScript = preload("res://scripts/die.gd")
const UI = preload("res://scripts/interface.gd")
const CombatFX = preload("res://scripts/combat_fx.gd")
const MENU_CAMERA := Vector3(4.23,3.65,4.77)
const GAME_CAMERA := Vector3(0,8.16,4.73)
const MATCH_TARGET := Vector3(0,0,.02)
const AI_SETS = [["impact","renew","breach"],["impact","reroll","renew"],["impact","attrition","resonance"]]

@onready var table: Node3D = $Table
@onready var camera: Camera3D = $Camera
@onready var animation: AnimationPlayer = $AnimationPlayer
var ui: Control
var rules = Rules.new()
var opponent = AI.new()
var samples := RandomNumberGenerator.new()
var equipped := ["impact","renew","breach"]
var cubes: Array = [[],[]]
var phase := "menu"
var current := 0
var attempts := [0,0]
var pending: Array = []
var config := ConfigFile.new()
var difficulty := 1
var reduced := false
var music_volume := .51
var effects_volume := .74
var camera_goal := MENU_CAMERA
var look_goal := Vector3(.10,-.03,-.52)
var look_at_point := look_goal
var preferred := {}
var target_limit := 0
var targets: Array = []
var particles: GPUParticles3D
var combat_fx: Node3D
var visual_board: Array = [[],[]]
var visual_hp := [15,15]
var visual_gold := [0,0]
var combat_uses := {}
var dice_shattered := 0
var sorted_rounds := 0
var strikes_animated := 0
var blocks_animated := 0
var players: Array[AudioStreamPlayer3D] = []
var streams := {}
var music: AudioStreamPlayer
var pool_index := 0
var integration := false
var generation := 0
var physics_rolls := 0
var physics_hits := 0
var dice_contact_count := 0
var narrowest_gap := INF
var frame_checks := 0
var integration_seed := 571
var raycast_hits := 0
var portrait := false

func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	portrait = OS.has_feature("android") or "--portrait" in arguments
	if portrait:
		get_window().content_scale_size = Vector2i(720,1280)
		if not OS.has_feature("android") and not DisplayServer.get_name() == "headless":
			get_window().size = Vector2i(405,720)
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		reduced = true
		Engine.max_fps = 60
	integration = "--sestria-test" in arguments
	for i in 3:
		if "--difficulty-%d" % i in arguments:
			difficulty = i
	samples.randomize()
	rules.rng.randomize()
	opponent.rng.randomize()
	if integration:
		samples.seed = integration_seed
		rules.rng.seed = integration_seed+1
		opponent.rng.seed = integration_seed+2
	else:
		read_settings()
	camera.position = MENU_CAMERA
	camera.look_at(look_goal)
	setup_audio()
	setup_effect()
	combat_fx = CombatFX.new()
	add_child(combat_fx)
	combat_fx.setup(table)
	for side in 2:
		for id in 6:
			make_die(side,id)
		rack(side,true)
	table.quality(reduced)
	combat_fx.reduced = reduced
	ui = UI.new()
	$Interface.add_child(ui)
	ui.setup(self)
	ui.show_menu()
	if integration:
		call_deferred("run_integration")

func _process(delta: float) -> void:
	var destination := camera_goal
	if portrait:
		destination = Vector3(0,10.9,6.32) if phase != "menu" else Vector3(4.23,7.0,9.3)
	camera.position = camera.position.lerp(destination,1.0-exp(-5.0*delta))
	look_at_point = look_at_point.lerp(look_goal,1.0-exp(-5.4*delta))
	camera.look_at(look_at_point)
	var t := Time.get_ticks_msec()*.001
	for flame in table.candle_flames:
		flame.scale.y = 1.47+.17*sin(t*10.0)+.082*sin(t*19.0)
	table.key.light_energy = 3.52+.16*sin(t*3.7)+.08*sin(t*7.8)
	if portrait and is_instance_valid(ui):
		ui.update_touch_dice()

func read_settings() -> void:
	if preload("res://scripts/compatibility.gd").load_settings(config) != OK:
		return
	difficulty = clampi(config.get_value("game","difficulty",1),0,2)
	reduced = config.get_value("video","low",portrait)
	music_volume = config.get_value("sound","music",.51)
	effects_volume = config.get_value("sound","effects",.74)
	var saved: Array = config.get_value("game","favors",equipped)
	saved = saved.map(func(id):return preload("res://scripts/compatibility.gd").tactic(str(id)))
	if saved.size() == 3 and saved.all(func(id):return Rules.FAVOR.has(id)):
		equipped.assign(saved)

func save_settings() -> void:
	if integration:
		return
	config.set_value("game","difficulty",difficulty)
	config.set_value("game","favors",equipped)
	config.set_value("video","low",reduced)
	config.set_value("sound","music",music_volume)
	config.set_value("sound","effects",effects_volume)
	config.save("user://sestria.cfg")

func change_quality(value: bool) -> void:
	reduced = value
	table.quality(value)
	combat_fx.reduced = value
	save_settings()

func change_music(value: float) -> void:
	music_volume = value
	music.volume_db = linear_to_db(maxf(.0001,value*.66))
	save_settings()

func setup_audio() -> void:
	for n in 9:
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = 9.0
		voice.max_distance = 17.0
		add_child(voice)
		players.append(voice)
	music = AudioStreamPlayer.new()
	var song: AudioStreamWAV = load("res://assets/audio/ambience.wav")
	song.loop_mode = AudioStreamWAV.LOOP_FORWARD
	song.loop_end = 22050*24-1
	music.stream = song
	music.volume_db = linear_to_db(maxf(.0001,music_volume*.66))
	add_child(music)
	if not integration:
		music.play()

func sound(id: String, place := Vector3.ZERO, loudness := 1.0) -> void:
	if integration or effects_volume <= 0.0:
		return
	if not streams.has(id):
		streams[id] = load("res://assets/audio/%s.wav" % id)
	var voice := players[pool_index]
	pool_index = (pool_index+1)%players.size()
	voice.stop()
	voice.position = place
	voice.stream = streams[id]
	voice.pitch_scale = randf_range(.91,1.10) if id == "clack" else 1.0
	voice.volume_db = linear_to_db(maxf(.0001,effects_volume*loudness))
	voice.play()

func setup_effect() -> void:
	particles = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.lifetime = .63
	particles.amount = 34
	particles.explosiveness = .92
	var behavior := ParticleProcessMaterial.new()
	behavior.direction = Vector3.UP
	behavior.spread = 67
	behavior.gravity = Vector3(0,-.48,0)
	behavior.initial_velocity_min = .4
	behavior.initial_velocity_max = 1.66
	behavior.scale_min = .48
	behavior.scale_max = 1.0
	particles.process_material = behavior
	var fleck := SphereMesh.new()
	fleck.radius = .017
	fleck.height = .034
	fleck.radial_segments = 6
	fleck.rings = 3
	fleck.material = table.hover_emission
	particles.draw_pass_1 = fleck
	add_child(particles)
	var library := AnimationLibrary.new()
	var pulse := Animation.new()
	pulse.length = .65
	var track := pulse.add_track(Animation.TYPE_VALUE)
	pulse.track_set_path(track,NodePath("Camera:fov"))
	pulse.track_insert_key(track,0,42.0)
	pulse.track_insert_key(track,.22,40.6)
	pulse.track_insert_key(track,.65,42.0)
	library.add_animation("attivateon",pulse)
	animation.add_animation_library("",library)

func impact(place: Vector3) -> void:
	physics_hits += 1
	sound("clack",place,.48)

func count_die_contact() -> void:
	dice_contact_count += 1

func make_die(side: int, id: int) -> Node3D:
	var cube := Die.instantiate()
	add_child(cube)
	cube.setup(table,id,side)
	cube.clack.connect(impact)
	cube.dice_touched.connect(count_die_contact)
	cubes[side].append(cube)
	return cube

func rack(side: int, immediate := false) -> void:
	for cube in cubes[side]:
		if cube.die_id >= 6:
			cube.hide()
			continue
		cube.show()
		cube.committed = false
		cube.select(false)
		var mirror := 1 if side == 0 else -1
		var x: float = mirror*(1.38 + cube.die_id*.33)
		var z: float = mirror*3.13
		cube.arrange(Vector3(x,.152,z),(cube.die_id+side)%6,0.0 if immediate else .34)

func prepare() -> void:
	generation += 1
	opponent.level = difficulty
	camera_goal = GAME_CAMERA
	look_goal = MATCH_TARGET
	phase = "coin"
	table.set_figures([equipped, AI_SETS[difficulty]])
	table.update_counters([15,15],[0,0],0)
	for side in 2:
		rack(side)
	ui.match_layout()
	ui.stats([15,15],[0,0], 1, 0)
	ui.coin_prompt()

func toss(guess: int) -> void:
	if phase != "coin":
		return
	var ticket := generation
	phase = "busy"
	var winner := 0 if samples.randi_range(0,1) == guess else 1
	rules.reset(winner)
	table.update_counters(rules.hp,rules.gold,winner)
	var flip := create_tween()
	flip.tween_property(table.coin,"rotation:x",TAU*2.0,.50).from(0.0)
	sound("coin",table.coin.position)
	ui.status("Hai l’iniziativa" if winner == 0 else "L’avversario ha l’iniziativa")
	await pause(.57)
	if ticket == generation:
		begin_round()

func begin_round() -> void:
	table.lanes.hide()
	attempts = [0,0]
	pending = []
	preferred = {}
	targets = []
	target_limit = 0
	for side in 2:
		rack(side)
	ui.stats(rules.hp,rules.gold,rules.round_no,rules.first)
	table.update_counters(rules.hp,rules.gold,rules.first)
	offer_roll(rules.first)

func offer_roll(side: int) -> void:
	current = side
	ui.set_stage(0)
	camera_goal = GAME_CAMERA
	look_goal = MATCH_TARGET
	if side == 0:
		phase = "roll"
		ui.action("Lancia i dadi", "Lancia", roll)
	else:
		phase = "ai"
		ui.status("L’avversario prepara il lancio")
		var ticket := generation
		await pause(.44)
		if ticket == generation and phase == "ai":
			roll()

func roll() -> void:
	if phase not in ["roll","ai"]:
		return
	var ticket := generation
	phase = "busy"
	var side := current
	attempts[side] += 1
	camera_goal = GAME_CAMERA * .965
	look_goal = MATCH_TARGET.lerp(Vector3(0,0,table.BOWL_Z[side]),.09)
	ui.status("Lancio %d di 3" % attempts[side] if side == 0 else "Lancio avversario")
	var center := Vector3(0,table.FLOOR_Y,table.BOWL_Z[side])
	sound("roll",center,.75)
	pending = []
	var active: Array = []
	active = cubes[side].filter(func(cube): return cube.die_id < 6 and not cube.committed)
	var start_angle := samples.randf_range(0.0,TAU)
	for index in active.size():
		active[index].launch(center,start_angle+TAU*index/active.size(),samples)
	physics_rolls += 1
	var elapsed := 0.0
	var stable := 0
	var next_nudge := 1.85
	while elapsed < 4.5:
		await get_tree().physics_frame
		if ticket != generation:
			return
		elapsed += 1.0 / Engine.physics_ticks_per_second
		if integration:
			measure_spacing(active)
		if elapsed > .68 and active.all(func(c): return c.has_settled(center.y)):
			stable += 1
			if stable >= 12:
				break
		else:
			stable = 0
		if elapsed >= next_nudge:
			next_nudge += .82
			for cube in active:
				cube.nudge(center,samples)
	for cube in active:
		cube.stop_roll()
		pending.append(Rules.die(cube.die_id,cube.face))
	await pause(.19)
	if ticket != generation:
		return
	if integration:
		for cube in active:
			if DieScript.top_face(cube.basis) != cube.face:
				fail("Discordanza tra faccia fisica e risultato")
				return
			frame_checks += 1
	if side == 1 or attempts[side] == 3:
		var keep := opponent.keep(rules,side,pending,attempts[side]==3)
		commit(keep)
	else:
		phase = "select"
		ui.action("Seleziona i dadi da tenere", "Conferma", confirm_selection)

func measure_spacing(active: Array) -> void:
	for a in active.size():
		for b in range(a+1,active.size()):
			var distance: float = active[a].position.distance_to(active[b].position)
			narrowest_gap = minf(narrowest_gap,distance)

func confirm_selection() -> void:
	if phase != "select":
		return
	var kept := pending.filter(func(d):return cubes[0][d.id].selected)
	commit(kept.map(func(d):return d.id))

func commit(keep: Array) -> void:
	var ticket := generation
	phase = "busy"
	var side := current
	for d in pending:
		if d.id in keep:
			rules.board[side].append(d)
			var cube: Node3D = cubes[side][d.id]
			cube.committed = true
			cube.select(false)
			cube.arrange(row_position(side,rules.board[side].size()-1),d.face,.31,.31)
	ui.status("Dadi confermati" if side == 0 else "Dadi avversari confermati")
	await pause(.34)
	if ticket != generation:
		return
	var other := 1-side
	var own_open: bool = attempts[side]<3 and rules.board[side].size()<6
	var other_open: bool = attempts[other]<3 and rules.board[other].size()<6
	if other_open:
		offer_roll(other)
	elif own_open:
		offer_roll(side)
	else:
		await sorting_stage(ticket)

func sorting_stage(ticket: int) -> void:
	phase = "sorting"
	camera_goal = GAME_CAMERA*.96
	look_goal = MATCH_TARGET
	ui.set_stage(1)
	ui.status("Ordinamento dei dadi")
	table.lanes.show()
	visual_board = rules.board.duplicate(true)
	sort_groups()
	sorted_rounds += 1
	await pause(.97)
	if ticket != generation:
		return
	phase = "favor"
	ui.set_stage(2)
	ui.favor_stage()

func sort_groups() -> void:
	for side in 2:
		var group_counts := [0,0,0,0,0]
		var group_sizes := [0,0,0,0,0]
		for entry in visual_board[side]:
			group_sizes[entry.kind] += 1
		var mirror := 1.0 if side == 0 else -1.0
		for entry in visual_board[side]:
			var count: int = group_counts[entry.kind]
			group_counts[entry.kind] += 1
			var slot := count % 3
			var row := count / 3
			var row_width := mini(3,group_sizes[entry.kind]-row*3)
			var x: float = table.lane_x(entry.kind)+(slot-(row_width-1)*.5)*.345
			var pos := Vector3(x,.152,mirror*(.44+row*.345))
			var cube: Node3D = cubes[side][entry.id]
			cube.arrange(pos,entry.face,.43+float(entry.kind)*.067,.26+float(entry.id)*.045)

func row_position(side: int, index: int) -> Vector3:
	var sign_side := 1.0 if side == 0 else -1.0
	return Vector3((index-2.5)*.40,.155,sign_side*.66)

func inspect_favor(side: int, id: String) -> void:
	if phase in ["favor","select","roll","target"]:
		ui.favor_popup(id,side == 0 and phase == "favor")

func pick_favor(id: String, level: int, sacrifice: int) -> void:
	if phase != "favor":
		return
	preferred = {"id":id,"level":level,"sacrifice":sacrifice}
	if id == "reroll":
		phase = "target"
		target_limit = Rules.FAVOR.reroll[3][level]
		targets = []
		ui.action("Seconda occasione · seleziona fino a %d dadi sul campo" % target_limit,
			"Attiva",confirm_targets)
	else:
		resolve(preferred)

func confirm_targets() -> void:
	if phase != "target":
		return
	preferred.targets = targets.duplicate()
	for pair in targets:
		cubes[pair[0]][pair[1]].select(false)
	resolve(preferred)

func resolve(plan: Dictionary) -> void:
	if phase not in ["favor","target"]:
		return
	combat_uses.clear()
	var ticket := generation
	phase = "busy"
	visual_hp = rules.hp.duplicate()
	visual_gold = rules.gold.duplicate()
	var enemy := opponent.favor(rules,1,AI_SETS[difficulty])
	var events: Array = rules.resolve([plan,enemy])
	camera_goal = GAME_CAMERA*.95
	look_goal = MATCH_TARGET
	ui.set_stage(3)
	ui.status("Risoluzione della manche")
	await pause(.28)
	if ticket != generation:
		return
	var playback := {}
	for event_index in events.size():
		var event: Dictionary = events[event_index]
		ui.describe_event(event)
		if event.extra.has("attacker"):
			if playback.is_empty():
				playback = prepare_combat(events)
			await animate_combat(event,playback[event_index])
		elif event.kind == "token" and event.extra.get("hand",false):
			await animate_theft(event)
		else:
			play_event(event)
		if ticket != generation:
			return
		visual_hp = event.hp.duplicate()
		visual_gold = event.gold.duplicate()
		ui.stats(visual_hp,visual_gold,rules.round_no,rules.first)
		table.update_counters(visual_hp,visual_gold,rules.first)
		if event.kind not in ["block","hit"] or not event.extra.has("attacker"):
			await pause(.72 if event.kind == "favor" else .43)
		if ticket != generation:
			return
	if integration and combat_uses.values().any(func(uses): return uses != 0):
		fail("Un colpo non ha completato la distruzione del dado")
		return
	look_goal = MATCH_TARGET
	camera_goal = GAME_CAMERA
	table.update_counters(rules.hp,rules.gold,rules.first)
	if rules.winner >= 0:
		phase = "end"
		camera_goal = GAME_CAMERA*.93
		ui.finish(rules.winner==0)
		sound("win" if rules.winner==0 else "lose")
		return
	phase = "between"
	ui.action("Fine della manche", "Prossima manche", next_round)

func next_round() -> void:
	if phase != "between":
		return
	rules.next_round()
	begin_round()

func group_cubes(side: int, symbol: int) -> Array:
	var group: Array = []
	for entry in visual_board[side]:
		if entry.kind == symbol:
			group.append(cubes[side][entry.id])
	return group

func attack_batches(event: Dictionary) -> Array:
	if event.kind == "block":
		var batches: Array = []
		if event.extra.asce > 0:
			batches.append({"symbol":Rules.AXE,"count":event.extra.asce,"offset":0})
		if event.extra.frecce > 0:
			batches.append({"symbol":Rules.ARROW,"count":event.extra.frecce,"offset":event.extra.ignora})
		return batches
	return [{"symbol":event.extra.symbol,"count":event.amount,"offset":event.extra.blocked}]

func prepare_combat(events: Array) -> Dictionary:
	combat_uses.clear()
	var playback := {}
	for index in events.size():
		var event: Dictionary = events[index]
		if not event.extra.has("attacker"):
			continue
		var clips: Array = []
		for batch in attack_batches(event):
			clips.append(plan_strikes(event,batch))
		playback[index] = clips
	return playback

func plan_strikes(event: Dictionary,batch: Dictionary) -> Dictionary:
	var attacker: int = event.extra.attacker
	var defender: int = event.side
	var symbol: int = batch.symbol
	var blocked: bool = event.kind == "block"
	var attacks := group_cubes(attacker,symbol)
	var defense := Rules.HELMET if symbol == Rules.AXE else Rules.SHIELD
	var shields := group_cubes(defender,defense) if blocked else []
	var strikes: Array = []
	for i in int(batch.count):
		var attack_index := i
		if blocked or i >= event.extra.get("ignora",0):
			attack_index += batch.offset
		var source: Node3D = attacks[attack_index%attacks.size()] if not attacks.is_empty() else null
		var target: Node3D = shields[i%shields.size()] if not shields.is_empty() else null
		for cube in [source,target]:
			if cube:
				combat_uses[cube] = combat_uses.get(cube,0)+1
		var stone_index: int = -1 if blocked else event.hp[defender]+event.amount-i-1
		strikes.append({"source":source,"target":target,"stone":stone_index})
	return {"symbol":symbol,"blocked":blocked,"strikes":strikes}

func animate_combat(event: Dictionary,clips: Array) -> void:
	var side: int = event.side
	var speed := .04 if integration else 1.0
	for clip in clips:
		var kind: int = clip.symbol
		var defense_kind := Rules.HELMET if kind == Rules.AXE else Rules.SHIELD
		var blocked: bool = clip.blocked
		var title: String
		if blocked:
			title = "Asce contro elmi" if kind == Rules.AXE else "Frecce contro scudi"
		else:
			title = "Assalto delle asce" if kind == Rules.AXE else "Raffica di frecce"
		ui.combat_detail(title,clip.strikes.size(),not blocked)
		var duration := 0.0
		for i in clip.strikes.size():
			var strike: Dictionary = clip.strikes[i]
			var source := Vector3(table.lane_x(kind),.36,.44 if side == 1 else -.44)
			if strike.source:
				source = strike.source.position+Vector3.UP*.18
			var target := Vector3(table.lane_x(defense_kind),.32,.45 if side == 0 else -.45)
			var stone: MeshInstance3D
			if blocked:
				if strike.target:
					target = strike.target.position+Vector3.UP*.20
				blocks_animated += 1
			else:
				stone = table.stones[side][strike.stone]
				target = stone.global_position+Vector3.UP*.07
				strikes_animated += 1
			var impact_cb := combat_impact.bind(strike.source,strike.target,stone,side,target,blocked,speed)
			duration = combat_fx.projectile(kind,source,target,blocked,i*.135,speed,impact_cb)
		await get_tree().create_timer(duration+.51*speed,false).timeout

func animate_theft(event: Dictionary) -> void:
	var thief: int = event.side
	var victim := 1-thief
	var speed := .04 if integration else 1.0
	var hands := group_cubes(thief,Rules.HAND)
	var victim_tokens: Array = table.tokens[victim]
	var thief_tokens: Array = table.tokens[thief]
	var victim_top := mini(visual_gold[victim],victim_tokens.size())-1
	var thief_next: int = visual_gold[thief]
	var duration := 0.0
	for i in int(event.amount):
		var from_index := victim_top-i
		if from_index < 0:
			break
		var to_index := mini(thief_next+i,thief_tokens.size()-1)
		var taken: Node3D = victim_tokens[from_index]
		var placed: Node3D = thief_tokens[to_index]
		var hand_die: Node3D = hands[i] if i < hands.size() else null
		var source := Vector3(table.lane_x(Rules.HAND),.36,.44 if thief == 0 else -.44)
		if hand_die:
			source = hand_die.position+Vector3.UP*.18
		var grab := func():
			taken.hide()
			visual_gold[victim] = maxi(0,visual_gold[victim]-1)
			ui.stats(visual_hp,visual_gold,rules.round_no,rules.first)
			sound("token",taken.global_position,.8)
			if hand_die:
				combat_fx.shatter_die(hand_die,false,speed)
				dice_shattered += 1
		var drop := func():
			placed.show()
			visual_gold[thief] += 1
			ui.stats(visual_hp,visual_gold,rules.round_no,rules.first)
			sound("token",placed.global_position,1.0)
		duration = maxf(duration,combat_fx.steal_token(source,taken.global_position,placed.global_position,
			taken,i*.22,speed,grab,drop))
	await get_tree().create_timer(duration+.2*speed,false).timeout

func combat_impact(source: Node3D, defender: Node3D, stone: MeshInstance3D, side: int,
		at: Vector3, blocked: bool, speed: float) -> void:
	spend_die(source,false,speed)
	look_goal = MATCH_TARGET.lerp(at,.08)
	if blocked:
		if defender and not spend_die(defender,true,speed):
			defender.parry(speed)
		sound("block",at,.73)
	elif stone:
		sound("hit",at,.77)
		combat_fx.knock_stone(stone,speed)
		visual_hp[side] = maxi(0,visual_hp[side]-1)
		ui.stats(visual_hp,visual_gold,rules.round_no,rules.first)

func spend_die(cube: Node3D, defense: bool, speed: float) -> bool:
	if not cube:
		return false
	var uses: int = combat_uses[cube]-1
	combat_uses[cube] = uses
	if uses > 0:
		return false
	dice_shattered += 1
	combat_fx.shatter_die(cube,defense,speed)
	return true

func play_event(event: Dictionary) -> void:
	var side: int = event.side
	var sign_side := 1.0 if side == 0 else -1.0
	var place := Vector3(0,.22,sign_side*.62)
	match event.kind:
		"favor":
			animation.play("attivateon")
			var index := Rules.FAVOR.keys().find(event.extra.id)
			var sets: Array = equipped if side == 0 else AI_SETS[difficulty]
			var slot := sets.find(event.extra.id)
			place = table.figures[side][slot].position
			place.y += .16
			if not reduced:
				particles.position = place
				particles.restart()
				particles.emitting = true
			sound("favor_%02d" % index,place)
		"extra":
			var d: Dictionary = event.extra
			var cube: Node3D = cubes[side][d.id] if d.id < cubes[side].size() else make_die(side,d.id)
			cube.show()
			cube.arrange(Vector3(0,.7,table.BOWL_Z[side]),d.face,0)
			visual_board[side].append(d)
			sort_groups()
			sound("clack",place)
		"reroll":
			var d: Dictionary = event.extra
			for i in visual_board[side].size():
				if visual_board[side][i].id == d.id:
					visual_board[side][i] = d
					break
			sort_groups()
			sound("roll",place)
		"ban":
			cubes[side][event.extra.id].hide()
			visual_board[side] = visual_board[side].filter(func(d): return d.id != event.extra.id)
			sort_groups()
		"hit","block":
			sound(event.kind,place)
		"clash":
			sound("block",place,.73)
			for hand_side in 2:
				var hands := group_cubes(hand_side,Rules.HAND)
				for index in mini(hands.size(),event.amount):
					combat_fx.shatter_die(hands[index],true,.04 if integration else 1.0)
					dice_shattered += 1
		"heal","token":
			sound("token",place)

func interact_at(screen: Vector2, inspect: bool) -> void:
	if phase not in ["select","favor","roll","target"]:
		return
	var origin := camera.project_ray_origin(screen)
	var past := origin+camera.project_ray_normal(screen)*40
	var query := PhysicsRayQueryParameters3D.create(origin,past,6)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var obj: Node3D = result.collider
	interact_die_or_favor(obj,inspect)

func interact_die_or_favor(obj: Node3D, inspect: bool) -> void:
	if phase not in ["select","favor","roll","target"]:
		return
	if not obj.visible:
		return
	if obj.has_meta("favor"):
		inspect_favor(obj.get_meta("side"),obj.get_meta("favor"))
		return
	if inspect or (portrait and ui.inspect_mode and phase != "target"):
		ui.inspect_die(obj.die_id,obj.face)
	elif phase == "select" and obj.side == 0 and not obj.committed and pending.any(func(d):return d.id == obj.die_id):
		obj.select(not obj.selected)
		raycast_hits += 1
		sound("select",obj.position)
	elif phase == "target" and obj.committed:
		var pair := [obj.side,obj.die_id]
		if pair in targets:
			targets.erase(pair)
			obj.select(false)
		elif targets.size()<target_limit:
			targets.append(pair)
			obj.select(true)
		ui.selection_count(targets.size(),target_limit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			interact_at(event.position,event.button_index==MOUSE_BUTTON_RIGHT)
	elif event is InputEventKey and event.pressed and not event.echo:
		if is_instance_valid(ui.dialog):
			if event.keycode == KEY_ESCAPE and phase not in ["coin","end"]:
				ui.close_dialog()
			return
		if event.keycode == KEY_ESCAPE:
			go_back()
		if event.keycode in [KEY_SPACE, KEY_ENTER]:
			match phase:
				"roll": roll()
				"select": confirm_selection()
				"between": next_round()

func go_back() -> void:
	if is_instance_valid(ui.context_popup):
		ui.close_context()
	elif is_instance_valid(ui.dialog):
		if phase not in ["coin","end"]:
			ui.close_dialog()
	elif phase == "menu":
		ui.show_menu()
	else:
		ui.ask_leave()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(ui):
		go_back()

func menu() -> void:
	table.lanes.hide()
	generation += 1
	phase = "menu"
	camera_goal = MENU_CAMERA
	look_goal = Vector3(.10,-.03,-.52)
	for side in 2:
		rack(side)
	table.update_counters([15,15],[0,0],0)
	ui.show_menu()

func pause(seconds: float) -> void:
	if integration:
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		await get_tree().create_timer(seconds,false).timeout

func fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)

func run_integration() -> void:
	prepare()
	toss(0)
	while phase != "end":
		await get_tree().process_frame
		match phase:
			"roll": roll()
			"select":
				var pick := opponent.keep(rules,0,pending,false)
				await get_tree().physics_frame
				for id in pick:
					var cube: Node3D = cubes[0][id]
					interact_at(camera.unproject_position(cube.global_position),false)
				confirm_selection()
			"favor": resolve(opponent.favor(rules,0,equipped))
			"between": next_round()
		if rules.round_no > 48:
			fail("Partita oltre 48 manche")
			return
	if dice_contact_count == 0 or narrowest_gap < .283:
		fail("Collisioni dado-dado: %d; distanza minima tra i centri: %.4f" % [dice_contact_count,narrowest_gap])
		return
	print("COLLISIONI | %d contatti dado-dado | distanza minima tra i centri %.4f" % [dice_contact_count,narrowest_gap])
	if physics_rolls == 0 or physics_hits == 0 or frame_checks == 0 or raycast_hits == 0:
		fail("La partita non ha attraversato la fisica")
		return
	if sorted_rounds != rules.round_no or strikes_animated == 0 or blocks_animated == 0 or dice_shattered == 0:
		fail("La partita non ha verificato ordinamento, attacchi e parate")
		return
	print("PARTITA COMPLETA | difficoltà %d | vincitore %d | manche %d | lanci %d | impatti %d | facce %d | raycast %d | ordinamenti %d | colpi %d | parate %d | dadi frantumati %d" %
		[difficulty,rules.winner,rules.round_no,physics_rolls,physics_hits,frame_checks,raycast_hits,
		sorted_rounds,strikes_animated,blocks_animated,dice_shattered])
	get_tree().quit()
