extends Node3D

const Rules = preload("res://scripts/rules.gd")
const AI = preload("res://scripts/ai.gd")
const Die = preload("res://scenes/die.tscn")
const DieScript = preload("res://scripts/die.gd")
const UI = preload("res://scripts/interface.gd")
const UILegacy = preload("res://scripts/interface_legacy.gd")
const Platform = preload("res://scripts/platform.gd")
const PCVideo = preload("res://scripts/pc_video.gd")
const Bindings = preload("res://scripts/input_bindings.gd")
const Installer = preload("res://scripts/windows_installer.gd")
const ProfileStore = preload("res://scripts/hub/profile_store.gd")
const CampaignStore = preload("res://scripts/hub/campaign_store.gd")
const CombatFX = preload("res://scripts/combat_fx.gd")
const MENU_CAMERA := Vector3(4.23,3.65,4.77)
const GAME_CAMERA := Vector3(0,11.0,.5)
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
var pc := {}                      # impostazioni video dei computer (pc_video.gd)
var pc_touched := false           # true se l'utente le ha già salvate
var fps_label: Label
var profile: RefCounted             # profilo del giocatore (nome, icona, codice amico)
var campaigns: RefCounted           # campagne salvate
var drive: Node                   # salvataggio su Google Drive (4.8.1)
var settings_updated := 0           # ora dell'ultima modifica delle preferenze (per la sincronizzazione)
var friends: Node                 # amici (4.8)
var active_campaign := ""           # id della campagna in corso ("" = partita al volo)
var match_setup := {}               # parametri della partita di campagna in corso
var max_throws := 3                 # lanci per manche (campagna: 2 o 3)
var speed_factor := 1.0             # velocità delle animazioni (campagna: veloce)
var log_detail := true              # cronaca dettagliata dei colpi
var bot_loadout: Array = []         # tattiche del bot nella partita in corso
var forced_first := -1              # chi inizia se non si tira la moneta (0 tu, 1 bot)
var hints_on := false               # suggerimenti: pre-seleziona i dadi consigliati
var hotseat := false                # «Passa e gioca»: due persone sullo stesso dispositivo
var acting := 0                     # lato controllato dalla persona che sta giocando adesso
var hotseat_plan := {}              # tattica già scelta dal primo giocatore
var hotseat_has_plan := false
var player_names := ["Tu","Avversario"]
var legacy_ui := false              # interfaccia classica (4.7) al posto della nuova
var start_page := "campaign"        # scheda del menu aperta all'avvio
var quick_settings := CampaignStore.default_settings()   # impostazioni della partita al volo
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
var stats_store: RefCounted
var progression: RefCounted
var saga_run := {}
var saga_notice := ""
var saga_difficulty := 1
var updater: Node
var account: Node
var lan: Node
var network_enemy_plan := {}
var network_resolving := false
var network_advancing := false

func _ready() -> void:
	# Opzioni di disinstallazione del launcher Windows (il processo si ferma qui).
	if Platform.is_windows() and await Installer.handle_command_line(get_tree()):
		return
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
	if Platform.pc_available() and not portrait:
		setup_pc_video()
	ui = (UILegacy if legacy_ui else UI).new()
	$Interface.add_child(ui)
	ui.setup(self)
	profile=ProfileStore.new()
	campaigns=CampaignStore.new()
	stats_store=preload("res://scripts/statistics.gd").new()
	progression=preload("res://scripts/progression.gd").new()
	if Platform.lan_available() or Platform.online_available():
		lan=preload("res://scripts/lan_session.gd").new()
		add_child(lan)
		lan.setup(self)
		lan.changed.connect(ui.refresh_lan)
		lan.problem.connect(ui.lan_problem)
	if Platform.online_available() and lan != null and preload("res://scripts/hub/friends_service.gd").supported():
		friends = preload("res://scripts/hub/friends_service.gd").new()
		add_child(friends)
		friends.setup(self)
		friends.changed.connect(ui.refresh_friends)
		friends.invited.connect(ui.friend_invited)
	drive = preload("res://scripts/hub/drive_sync.gd").new()
	add_child(drive)
	drive.setup(self)
	drive.changed.connect(ui.refresh_drive)
	if Platform.updater_available():
		updater=preload("res://scripts/desktop_updater.gd").new()
		add_child(updater)
		updater.changed.connect(ui.refresh_updates)
	ui.show_menu()
	if integration:
		call_deferred("run_integration")

func _process(delta: float) -> void:
	if is_instance_valid(fps_label) and fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if stats_store and not integration:
		stats_store.tick(delta)
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
	Bindings.load_from(config)
	legacy_ui = bool(config.get_value("ui","legacy",false))
	settings_updated = int(config.get_value("meta","updated",0))
	start_page = str(config.get_value("game","start_page","campaign"))
	if not start_page in ["campaign","multiplayer","friends","progress"]:
		start_page = "campaign"
	var stored_quick := {}
	if config.has_section("quick"):
		for key in config.get_section_keys("quick"):
			stored_quick[key] = config.get_value("quick",key)
	quick_settings = CampaignStore.clean_settings(stored_quick)
	difficulty = clampi(config.get_value("game","difficulty",1),0,2)
	reduced = config.get_value("video","low",portrait)
	music_volume = config.get_value("sound","music",.51)
	effects_volume = config.get_value("sound","effects",.74)
	var saved: Array = config.get_value("game","favors",equipped)
	saved = saved.map(func(id):return preload("res://scripts/compatibility.gd").tactic(str(id)))
	if saved.size() == 3 and saved.all(func(id):return Rules.FAVOR.has(id)):
		equipped.assign(saved)

func save_settings(stamp := true) -> void:
	if integration:
		return
	if stamp:
		settings_updated = int(Time.get_unix_time_from_system())
	config.set_value("meta","updated",settings_updated)
	config.set_value("game","difficulty",difficulty)
	config.set_value("game","favors",equipped)
	config.set_value("game","start_page",start_page)
	config.set_value("ui","legacy",legacy_ui)
	for key in quick_settings:
		config.set_value("quick",key,quick_settings[key])
	config.set_value("video","low",reduced)
	if pc_touched:
		PCVideo.save_to(config,pc)
	Bindings.save_to(config)
	config.set_value("sound","music",music_volume)
	config.set_value("sound","effects",effects_volume)
	config.save("user://sestria.cfg")

# Carica le impostazioni dei computer. Se mancano, derivano dalla vecchia scelta Alta/Ridotta e non toccano la finestra.
func setup_pc_video() -> void:
	pc_touched = config.has_section(PCVideo.SECTION)
	if pc_touched:
		pc = PCVideo.load_from(config)
	else:
		pc = PCVideo.with_preset(PCVideo.defaults(),"bassa" if reduced else "alta")
	apply_pc(pc_touched)
	fps_label = Label.new()
	fps_label.position = Vector2(14,10)
	fps_label.add_theme_font_size_override("font_size",15)
	fps_label.add_theme_color_override("font_color",Color("#85e7cb"))
	fps_label.visible = bool(pc.fps_counter)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(fps_label)
	add_child(layer)

func apply_pc(with_display := true) -> void:
	reduced = pc.preset == "bassa"
	combat_fx.reduced = pc.particles == "low"
	if with_display:
		PCVideo.apply_display(pc,get_window())
	PCVideo.apply_graphics(pc,get_viewport(),table)

func change_pc(settings: Dictionary, with_display := true) -> void:
	pc = PCVideo.clean(settings)
	pc_touched = true
	apply_pc(with_display)
	if is_instance_valid(fps_label):
		fps_label.visible = bool(pc.fps_counter)
	save_settings()

func change_quality(value: bool) -> void:
	reduced = value
	table.quality(value)
	combat_fx.reduced = value
	save_settings()

# Passa dall'interfaccia nuova a quella classica (e viceversa). Si può fare solo dal menu.
func switch_ui(legacy: bool) -> void:
	if phase != "menu" or legacy == legacy_ui:
		return
	legacy_ui = legacy
	save_settings()
	var old := ui
	ui = (UILegacy if legacy_ui else UI).new()
	$Interface.add_child(ui)
	ui.setup(self)
	if is_instance_valid(old):
		old.queue_free()
	if lan:
		if not lan.changed.is_connected(ui.refresh_lan):
			lan.changed.connect(ui.refresh_lan)
		if not lan.problem.is_connected(ui.lan_problem):
			lan.problem.connect(ui.lan_problem)
	if updater and not updater.changed.is_connected(ui.refresh_updates):
		updater.changed.connect(ui.refresh_updates)
	if friends:
		friends.changed.connect(ui.refresh_friends)
		friends.invited.connect(ui.friend_invited)
	if drive and not drive.changed.is_connected(ui.refresh_drive):
		drive.changed.connect(ui.refresh_drive)
	if "account" in self and account != null and account.has_signal("changed"):
		account.changed.connect(ui.refresh_profile)
	if friends:
		friends.activate(false)
	if music and not integration and not music.playing:
		music.play()
	ui.show_menu()

# Preferenze arrivate da Google Drive (più recenti di quelle di questo dispositivo).
func apply_synced_settings(s: Dictionary) -> void:
	difficulty = clampi(int(s.get("difficulty",difficulty)),0,2)
	var saved: Array = s.get("favors",equipped)
	if saved.size() == 3 and saved.all(func(id):return Rules.FAVOR.has(str(id))):
		equipped.assign(saved)
	if str(s.get("start_page","")) in ["campaign","multiplayer","friends","progress"]:
		start_page = str(s.start_page)
	if s.get("quick") is Dictionary:
		quick_settings = CampaignStore.clean_settings(s.quick)
	settings_updated = int(s.get("updated",settings_updated))
	save_settings(false)

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

# Avvia la partita successiva di una campagna salvata.
func start_campaign(id: String) -> void:
	var index: int = campaigns.find(id)
	if index < 0:
		return
	hotseat = false
	player_names = ["Tu","Avversario"]
	active_campaign = id
	match_setup = CampaignStore.match_setup(campaigns.campaigns[index])
	difficulty = int(match_setup.difficulty)
	prepare()

# Partita al volo: impostazioni predefinite, premio XP della saga.
# Passa e gioca: due persone, un solo dispositivo. Nessun bot, nessun XP; le tattiche si scelgono in segreto.
func start_hotseat(first_name: String, second_name: String) -> void:
	active_campaign = ""
	match_setup = {}
	hotseat = true
	player_names = [ProfileStore.clean_name(first_name),ProfileStore.clean_name(second_name)]
	prepare()

func loadout(side: int) -> Array:
	return equipped if side == 0 else bot_loadout

func start_quick() -> void:
	hotseat = false
	player_names = ["Tu","Avversario"]
	active_campaign = ""
	match_setup = CampaignStore.quick_setup(quick_settings,difficulty)
	prepare()

# Applica le impostazioni della campagna (o i valori predefiniti) alla partita che sta per iniziare.
func apply_match_setup() -> void:
	max_throws = 3
	speed_factor = 1.0
	log_detail = true
	forced_first = -1
	hints_on = false
	opponent.aggression_bias = 1.0
	opponent.pressure_bias = 1.0
	if match_setup.is_empty() or integration or (lan and lan.started) or hotseat:
		return
	if match_setup.has("ai_level"):
		saga_run.ai_level = int(match_setup.ai_level)
		saga_run.trials_extra = int(match_setup.trials_extra)
		saga_run.difficulty = int(match_setup.difficulty)
		saga_run.tier = int(match_setup.tier)
	if int(match_setup.get("bot_tokens",-1)) >= 0 or match_setup.has("enemy_gold"):
		saga_run.enemy_gold = int(match_setup.get("enemy_gold",match_setup.get("bot_tokens",0)))
	saga_run.player_gold = int(match_setup.player_gold)
	saga_run.xp_multiplier = float(match_setup.get("xp_multiplier",1.0))
	max_throws = int(match_setup.throws)
	speed_factor = .6 if match_setup.speed == "fast" else 1.0
	log_detail = match_setup.log != "brief"
	hints_on = bool(match_setup.hints)
	forced_first = {"player":0,"bot":1}.get(str(match_setup.first),-1)
	match str(match_setup.style):
		"aggressive":
			opponent.aggression_bias = 1.25
			opponent.pressure_bias = .85
		"cautious":
			opponent.aggression_bias = .8
			opponent.pressure_bias = 1.25
	if int(match_setup.seed) > 0:
		samples.seed = int(match_setup.seed)
		rules.rng.seed = int(match_setup.seed)+1
		opponent.rng.seed = int(match_setup.seed)+2

func pick_bot_loadout() -> Array:
	var mode: String = str(match_setup.get("tactics","tier")) if not match_setup.is_empty() and not integration else "tier"
	if mode == "mirror":
		return equipped.duplicate()
	if mode == "random":
		var ids: Array = Rules.FAVOR.keys()
		var picked: Array = []
		var chooser := RandomNumberGenerator.new()
		chooser.seed = int(match_setup.get("seed",0)) if int(match_setup.get("seed",0)) > 0 else randi()
		while picked.size() < 3:
			var id: String = ids[chooser.randi_range(0,ids.size()-1)]
			if not picked.has(id):
				picked.append(id)
		return picked
	return AI_SETS[saga_difficulty].duplicate()

func prepare() -> void:
	if lan and lan.is_guest():
		return
	if lan and lan.active and not lan.started:
		lan.start_match()
		return
	if not integration:
		stats_store.start("lan" if lan and lan.started else ("hotseat" if hotseat else "solo"),difficulty)
	generation += 1
	acting = 0
	hotseat_has_plan = false
	rules.reset(0)
	progression.last_reward = {}
	saga_run = progression.create_run(difficulty,not (lan and lan.started) and not hotseat)
	# Existing automated matches keep a reproducible, unmodified baseline.
	if integration and not (lan and lan.started):
		saga_run = {"enabled":false,"ai_level":difficulty,"trials_extra":0}
	apply_match_setup()
	saga_notice = ""
	saga_difficulty = int(saga_run.ai_level)
	opponent.level = saga_difficulty
	opponent.trials_extra = int(saga_run.trials_extra)
	bot_loadout = equipped.duplicate() if hotseat else pick_bot_loadout()
	camera_goal = GAME_CAMERA
	look_goal = MATCH_TARGET
	phase = "coin"
	table.set_figures([equipped,lan.peer_loadout if lan and lan.started else bot_loadout])
	table.update_counters([15,15],[0,0],0)
	for side in 2:
		rack(side)
	ui.match_layout()
	ui.stats([15,15],[0,0], 1, 0)
	if forced_first >= 0:
		toss.call_deferred(0)
	else:
		ui.coin_prompt()

func toss(guess: int) -> void:
	if phase != "coin":
		return
	var ticket := generation
	phase = "busy"
	var winner := 0 if samples.randi_range(0,1) == guess else 1
	if forced_first >= 0:
		winner = forced_first
	rules.reset(winner)
	table.update_counters(rules.hp,rules.gold,winner)
	var flip := create_tween()
	flip.tween_property(table.coin,"rotation:x",TAU*2.0,.50).from(0.0)
	sound("coin",table.coin.position)
	if hotseat:
		ui.status("Inizia %s" % player_names[winner])
	else:
		ui.status("Hai l’iniziativa" if winner == 0 else "L’avversario ha l’iniziativa")
	await pause(.57)
	if ticket == generation:
		begin_round()

func begin_round() -> void:
	if lan and lan.started:
		lan.trace_stage("round_%d_start" % rules.round_no)
	var bonuses: Array = progression.round_bonuses(rules,saga_run)
	saga_notice = " · ".join(bonuses)
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
	if lan and lan.active and side==1:
		current=side
		phase="remote_roll"
		ui.set_stage(0)
		ui.status("Il rivale deve lanciare")
		return
	current = side
	ui.set_stage(0)
	camera_goal = GAME_CAMERA
	look_goal = MATCH_TARGET
	if side == 0 or hotseat:
		phase = "roll"
		acting = side
		var turn_note := ("Turno di %s\n" % player_names[side]) if hotseat else ""
		ui.action(turn_note+(saga_notice+"\nLancia i dadi" if not saga_notice.is_empty() and attempts[0]==0 else "Lancia i dadi"), "Lancia", roll)
	else:
		phase = "ai"
		ui.status(saga_notice+"\nL’avversario prepara il lancio" if not saga_notice.is_empty() and attempts==[0,0] else "L’avversario prepara il lancio")
		var ticket := generation
		await pause(.44)
		if ticket == generation and phase == "ai":
			roll()

func roll() -> void:
	if lan and lan.is_guest():
		if phase=="roll":
			lan.command("roll")
			phase="busy"
			ui.status("Lancio dei dadi…")
			if not integration:stats_store.rolled()
		return
	if phase not in ["roll","ai"]:
		return
	var ticket := generation
	phase = "busy"
	var side := current
	attempts[side] += 1
	camera_goal = GAME_CAMERA * .965
	look_goal = MATCH_TARGET.lerp(Vector3(0,0,table.BOWL_Z[side]),.09)
	ui.status(("Lancio %d di %d" % [attempts[side],max_throws]) if (side == 0 or hotseat) else "Lancio avversario")
	var center := Vector3(0,table.FLOOR_Y,table.BOWL_Z[side])
	sound("roll",center,.75)
	pending = []
	var active: Array = []
	active = cubes[side].filter(func(cube): return cube.die_id < 6 and not cube.committed)
	var start_angle := samples.randf_range(0.0,TAU)
	for index in active.size():
		active[index].launch(center,start_angle+TAU*index/active.size(),samples)
	physics_rolls += 1
	if side==0 and not integration:stats_store.rolled()
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
	if lan and lan.active and side==1 and attempts[side]<max_throws:
		phase="remote_select"
		ui.status("Il rivale sceglie i dadi")
	elif (side == 1 and not hotseat) or attempts[side] == max_throws:
		var keep := opponent.keep(rules,side,pending,attempts[side]==max_throws)
		commit(keep)
	else:
		phase = "select"
		acting = side
		ui.action(("%s: seleziona i dadi da tenere" % player_names[side]) if hotseat else "Seleziona i dadi da tenere", "Conferma", confirm_selection)
		if hints_on and not hotseat:
			suggest_keep()

# Suggerimento: pre-seleziona i dadi che il bot sceglierebbe al tuo posto. Puoi cambiarli prima di confermare.
func suggest_keep() -> void:
	var advice: Array = opponent.keep(rules,0,pending,false)
	for id in advice:
		if cubes[0][id] and not cubes[0][id].selected:
			cubes[0][id].select(true)
	ui.status("Suggerimento: ho evidenziato i dadi consigliati")

func measure_spacing(active: Array) -> void:
	for a in active.size():
		for b in range(a+1,active.size()):
			var distance: float = active[a].position.distance_to(active[b].position)
			narrowest_gap = minf(narrowest_gap,distance)

func confirm_selection() -> void:
	if phase != "select":
		return
	var kept := pending.filter(func(d):return cubes[acting][d.id].selected)
	if lan and lan.is_guest():
		lan.command("keep",{"ids":kept.map(func(d):return d.id)})
		if not integration:
			stats_store.kept(kept.size())
		phase="busy"
		ui.status("Dadi confermati")
		return
	commit(kept.map(func(d):return d.id))

func commit(keep: Array) -> void:
	if current==0 and not integration:
		stats_store.kept(keep.size())
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
	var own_open: bool = attempts[side]<max_throws and rules.board[side].size()<6
	var other_open: bool = attempts[other]<max_throws and rules.board[other].size()<6
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
	acting = 0
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
		ui.favor_popup(id,side == acting and phase == "favor")

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
	if lan and lan.active and not network_resolving:
		if phase in ["favor","target"]:
			lan.submit_favor(plan)
		return
	if phase not in ["favor","target"]:
		return
	var rival_plan := {}
	if hotseat:
		if not hotseat_has_plan:
			# Il primo giocatore ha scelto: si passa il dispositivo, senza mostrare la scelta.
			hotseat_plan = plan.duplicate(true)
			hotseat_has_plan = true
			phase = "handoff"
			ui.handoff(player_names[1],func():
				acting = 1
				phase = "favor"
				ui.favor_stage())
			return
		rival_plan = plan
		plan = hotseat_plan
		hotseat_has_plan = false
		acting = 0
	combat_uses.clear()
	var ticket := generation
	phase = "busy"
	visual_hp = rules.hp.duplicate()
	visual_gold = rules.gold.duplicate()
	var enemy: Dictionary = rival_plan if hotseat else (network_enemy_plan if network_resolving else opponent.favor(rules,1,bot_loadout))
	var events: Array = rules.resolve([plan,enemy])
	if not integration:
		stats_store.events(rules.round_no,events)
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
		if log_detail:
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
		network_resolving=false
		if lan:
			lan.replaying=false
		record_match_result()
		phase = "end"
		camera_goal = GAME_CAMERA*.93
		ui.finish(rules.winner==0)
		sound("win" if rules.winner==0 else "lose")
		return
	network_resolving=false
	if lan:
		lan.replaying=false
	phase = "between"
	ui.action("Fine della manche", "Prossima manche", next_round)

func next_round() -> void:
	if lan and lan.active and not network_advancing:
		if phase=="between":
			lan.next_round()
		return
	network_advancing=false
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
	var speed := .04 if integration else speed_factor
	for clip in clips:
		var kind: int = clip.symbol
		var defense_kind := Rules.HELMET if kind == Rules.AXE else Rules.SHIELD
		var blocked: bool = clip.blocked
		var title: String
		if blocked:
			title = "Asce contro elmi" if kind == Rules.AXE else "Frecce contro scudi"
		else:
			title = "Assalto delle asce" if kind == Rules.AXE else "Raffica di frecce"
		if log_detail:
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
	var speed := .04 if integration else speed_factor
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
			var sets: Array = equipped if side == 0 else (lan.peer_loadout if lan and lan.active else bot_loadout)
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
	elif phase == "select" and obj.side == acting and not obj.committed and pending.any(func(d):return d.id == obj.die_id):
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
		var action := Bindings.action_for(event)
		if action == "back" and ui.hub != null and ui.hub.visible and ui.hub.page_state.get("overlay",false):
			ui.hub.close_overlay()
			return
		if action == "fullscreen":
			toggle_fullscreen()
			return
		if action == "fps" and is_instance_valid(fps_label):
			change_pc(pc.merged({"fps_counter":not bool(pc.fps_counter)},true),false)
			return
		if is_instance_valid(ui.dialog):
			if action == "back" and phase not in ["coin","end"]:
				ui.close_dialog()
			return
		match action:
			"back":
				go_back()
			"confirm":
				match phase:
					"roll": roll()
					"select": confirm_selection()
					"between": next_round()
			"die1","die2","die3","die4","die5","die6":
				toggle_die_key(int(action.substr(3))-1)
			"tactic1","tactic2","tactic3":
				open_tactic_key(int(action.substr(6))-1)

# Tiene o lascia il dado con quel numero (tasti 1-6), come un clic sul dado.
func toggle_die_key(die_id: int) -> void:
	if phase != "select":
		return
	for obj in pending:
		if obj.die_id == die_id and obj.side == acting:
			interact_die_or_favor(obj,false)
			return

# Apre la tattica del totem indicato (tasti Q W E), come un clic sul totem.
func open_tactic_key(slot: int) -> void:
	if table.figures.size() > acting and slot < table.figures[acting].size():
		interact_die_or_favor(table.figures[acting][slot],false)

func toggle_fullscreen() -> void:
	if Platform.pc_available() and not pc.is_empty():
		var next: Dictionary = pc.duplicate()
		next.window_mode = "window" if pc.window_mode != "window" else "borderless"
		change_pc(next,true)
	elif Platform.fullscreen_available():
		Platform.toggle_fullscreen()

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
	if stats_store and not integration:stats_store.interrupt()
	if lan and lan.role!="":lan.close()
	hotseat = false
	acting = 0
	player_names = ["Tu","Avversario"]
	network_resolving=false
	network_advancing=false
	saga_run.clear()
	saga_notice=""
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
		await get_tree().create_timer(seconds*speed_factor,false).timeout

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

func record_match_result() -> void:
	if integration or stats_store.active.is_empty() or rules.winner < 0:
		return
	progression.complete_match(str(stats_store.active.id),str(stats_store.active.mode),rules.winner==0,saga_run)
	if active_campaign != "" and str(stats_store.active.mode) == "solo":
		var gained := int(progression.last_reward.get("xp",0))
		var outcome: Dictionary = campaigns.record(active_campaign,rules.winner==0,gained)
		if not outcome.is_empty():
			progression.last_reward["campaign"] = {"chapter":int(outcome.chapter),"promoted":bool(outcome.promoted)}
	stats_store.finish(rules.winner==0,rules.hp)


func prepare_lan_guest() -> void:
	max_throws = 3
	speed_factor = 1.0
	log_detail = true
	hints_on = false
	forced_first = -1
	saga_run = progression.create_run(difficulty,false)
	saga_notice = ""
	generation+=1
	rules.reset(0)
	phase="ai"
	for side in 2:
		rack(side,true)
	table.set_figures([equipped,lan.peer_loadout])
	table.update_counters([15,15],[0,0],0)
	ui.match_layout()
	ui.stats([15,15],[0,0],1,0)
	ui.status("Il rivale sceglie la moneta")
	if not integration:
		stats_store.start("lan",difficulty)


func rematch_lan() -> void:
	if lan and lan.role=="host" and lan.active:
		lan.started=false
		lan.plans=[null,null]
		lan.next_ready=[false,false]
		lan.start_match()


func player_name() -> String:
	if account and not account.profile.is_empty():
		return str(account.profile.get("name","Giocatore")).split(" ")[0].left(24)
	return "Giocatore"

