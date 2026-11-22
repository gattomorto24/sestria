extends RefCounted
# Impostazioni per i computer (Windows e Mac): una finestra larga con le pagine Schermo, Grafica, Audio,
# Comandi e Sistema. Disegna con gli stessi componenti dell'interfaccia (ui) e salva tramite game.change_pc().
const PCVideo = preload("res://scripts/pc_video.gd")
const Platform = preload("res://scripts/platform.gd")
const PAGES := ["schermo","grafica","audio","comandi","sistema"]
const PAGE_NAMES := {"schermo":"SCHERMO","grafica":"GRAFICA","audio":"AUDIO","comandi":"COMANDI","sistema":"SISTEMA"}
const CONFIRM_SECONDS := 12

var ui: Control
var game: Node3D
var page := "schermo"
var countdown := 0

static func open(interface: Control, owner_game: Node3D, wanted := "schermo") -> RefCounted:
	var screen := new()
	screen.ui = interface
	screen.game = owner_game
	screen.show_page(wanted if PAGES.has(wanted) else "schermo")
	return screen

func show_page(wanted: String) -> void:
	page = wanted
	var body: VBoxContainer = ui.modal("Impostazioni",980)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",22)
	body.add_child(columns)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation",8)
	nav.custom_minimum_size.x = 190
	columns.add_child(nav)
	for entry in PAGES:
		ui.button(nav,PAGE_NAMES[entry],show_page.bind(entry),0,entry == page)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",11)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(content)
	match page:
		"schermo": build_screen(content)
		"grafica": build_graphics(content)
		"audio": build_audio(content)
		"comandi": build_controls(content)
		"sistema": build_system(content)
	ui.button(body,"Indietro",ui.close_dialog)

# ---- Componenti ----

func heading(parent: Node, text: String) -> void:
	ui.label(parent,text,15,ui.GOLD,true)

func note(parent: Node, text: String) -> void:
	ui.paragraph(parent,text,560)

# Riga "titolo ‹ valore ›": ogni pressione passa al valore precedente o successivo.
func stepper(parent: Node, title: String, names: Array, index: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	var caption: Label = ui.label(row,title,16,ui.IVORY,true)
	caption.custom_minimum_size.x = 210
	arrow(row,"‹",func():callback.call((index-1+names.size())%names.size()))
	var value: Label = ui.label(row,str(names[clampi(index,0,names.size()-1)]),16,ui.GOLD)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrow(row,"›",func():callback.call((index+1)%names.size()))

# Pulsante freccia compatto, con stile semplice per mostrare bene il simbolo.
func arrow(parent: Node, symbol: String, callback: Callable) -> void:
	var item := Button.new()
	item.text = symbol
	item.focus_mode = Control.FOCUS_NONE
	item.custom_minimum_size = Vector2(46,40)
	item.add_theme_font_size_override("font_size",24)
	item.add_theme_color_override("font_color",ui.GOLD)
	item.add_theme_color_override("font_hover_color",ui.IVORY)
	item.add_theme_stylebox_override("normal",ui.skin(Color("#10252b"),ui.GOLD,4))
	item.add_theme_stylebox_override("hover",ui.skin(Color("#1c3d44"),ui.IVORY,4))
	item.add_theme_stylebox_override("pressed",ui.skin(Color("#244f57"),ui.MINT,4))
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.pressed.connect(callback)
	parent.add_child(item)

func toggle(parent: Node, title: String, value: bool, callback: Callable) -> void:
	stepper(parent,title,["Disattivato","Attivo"],1 if value else 0,func(i):callback.call(i == 1))

func range_slider(parent: Node, title: String, low: float, high: float, step: float, value: float, show: Callable, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	var caption: Label = ui.label(row,title,16,ui.IVORY,true)
	caption.custom_minimum_size.x = 210
	var control := HSlider.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.value = value
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 26
	row.add_child(control)
	var current: Label = ui.label(row,show.call(value),16,ui.GOLD,true)
	current.custom_minimum_size.x = 70
	control.value_changed.connect(func(next):
		current.text = show.call(next)
		callback.call(next))

func edit(key: String, value: Variant, redisplay := true) -> void:
	var next: Dictionary = game.pc.duplicate()
	next[key] = value
	apply(next,redisplay)

# Modifica di grafica: ricalcola il livello (Bassa/Media/Alta/Ultra/Personalizzata) e applica subito.
func apply(next: Dictionary, redisplay := true) -> void:
	if next.preset != "custom" and PCVideo.detect_preset(next) != next.preset:
		next.preset = PCVideo.detect_preset(next)
	game.change_pc(next,false)
	if redisplay:
		show_page(page)

# Modifica di finestra, risoluzione o monitor: si applica e si chiede conferma, con ripristino automatico.
func edit_display(key: String, value: Variant) -> void:
	var previous: Dictionary = game.pc.duplicate()
	var next: Dictionary = game.pc.duplicate()
	next[key] = value
	game.change_pc(next,true)
	confirm_display(previous)

func confirm_display(previous: Dictionary) -> void:
	var body: VBoxContainer = ui.modal("Mantenere queste impostazioni?",560)
	countdown = CONFIRM_SECONDS
	var message: Label = ui.paragraph(body,"",500)
	message.text = "Se non confermi, le impostazioni precedenti tornano tra %d secondi." % countdown
	var timer := Timer.new()
	timer.wait_time = 1.0
	body.add_child(timer)
	timer.timeout.connect(func():
		countdown -= 1
		if countdown <= 0:
			timer.stop()
			revert_display(previous)
		else:
			message.text = "Se non confermi, le impostazioni precedenti tornano tra %d secondi." % countdown)
	timer.start()
	ui.button(body,"MANTIENI",func():
		timer.stop()
		show_page(page),0,true)
	ui.button(body,"Ripristina",func():
		timer.stop()
		revert_display(previous))

func revert_display(previous: Dictionary) -> void:
	game.change_pc(previous,true)
	show_page(page)

# ---- Pagina Schermo ----

func build_screen(parent: Node) -> void:
	var s: Dictionary = game.pc
	var screens := DisplayServer.get_screen_count()
	var monitor := clampi(s.monitor,0,screens-1)
	heading(parent,"FINESTRA")
	if screens > 1:
		var names: Array = []
		for i in screens:
			var size := DisplayServer.screen_get_size(i)
			names.append("Monitor %d · %dx%d" % [i+1,size.x,size.y])
		stepper(parent,"Monitor",names,monitor,func(i):edit_display("monitor",i))
	var modes := PCVideo.WINDOW_MODES
	stepper(parent,"Modalità",modes.map(func(m):return PCVideo.WINDOW_NAMES[m]),modes.find(s.window_mode),func(i):edit_display("window_mode",modes[i]))
	if s.window_mode == "window":
		var options := PCVideo.resolution_options(DisplayServer.screen_get_size(monitor))
		var current := PCVideo.parse_resolution(s.resolution)
		var index := options.find(current)
		if index < 0:
			options.append(current)
			index = options.size()-1
		stepper(parent,"Risoluzione",options.map(PCVideo.resolution_text),index,func(i):edit_display("resolution",PCVideo.resolution_text(options[i])))
	else:
		note(parent,"In schermo intero il gioco usa la risoluzione del monitor. Per alleggerire la scheda grafica abbassa la scala di rendering o attiva FSR dalla pagina Grafica.")
	range_slider(parent,"Scala interfaccia",.75,1.5,.05,s.ui_scale,func(v):return "%d%%" % roundi(v*100),func(v):edit("ui_scale",v,false))
	heading(parent,"FLUIDITÀ")
	stepper(parent,"V-Sync",PCVideo.VSYNC_MODES.map(func(m):return PCVideo.VSYNC_NAMES[m]),PCVideo.VSYNC_MODES.find(s.vsync),func(i):edit("vsync",PCVideo.VSYNC_MODES[i]))
	stepper(parent,"Limite FPS",PCVideo.FPS_CAPS.map(func(v):return "Illimitato" if v == 0 else "%d" % v),PCVideo.FPS_CAPS.find(s.fps_cap),func(i):edit("fps_cap",PCVideo.FPS_CAPS[i]))
	toggle(parent,"Contatore FPS",s.fps_counter,func(v):edit("fps_counter",v))
	note(parent,"F11 o Alt+Invio cambiano rapidamente tra finestra e schermo intero.")

# ---- Pagina Grafica ----

func build_graphics(parent: Node) -> void:
	var s: Dictionary = game.pc
	var forward := PCVideo.upscaling_available()
	heading(parent,"QUALITÀ")
	var names: Array = PCVideo.PRESETS.map(func(p):return PCVideo.PRESET_NAMES[p])
	names.append(PCVideo.PRESET_NAMES.custom)
	var preset_index: int = PCVideo.PRESETS.find(s.preset) if PCVideo.PRESETS.has(s.preset) else PCVideo.PRESETS.size()
	stepper(parent,"Livello",names,preset_index,func(i):
		if i < PCVideo.PRESETS.size():
			apply(PCVideo.with_preset(game.pc,PCVideo.PRESETS[i])))
	heading(parent,"UPSCALING E ANTI-ALIASING")
	var modes := PCVideo.SCALING_MODES.filter(func(m):return forward or not m in ["fsr1","fsr2"])
	stepper(parent,"Upscaling",modes.map(func(m):return PCVideo.SCALING_NAMES[m]),modes.find(s.scaling),func(i):edit("scaling",modes[i]))
	if s.scaling in ["fsr1","fsr2"]:
		var qualities := PCVideo.FSR_QUALITY.keys()
		stepper(parent,"Qualità FSR",qualities.map(func(q):return "%s · %d%%" % [PCVideo.FSR_NAMES[q],roundi(PCVideo.FSR_QUALITY[q]*100)]),qualities.find(s.fsr_quality),func(i):edit("fsr_quality",qualities[i]))
		range_slider(parent,"Nitidezza",0.0,1.0,.05,(2.0-s.sharpness)/2.0,func(v):return "%d%%" % roundi(v*100),func(v):edit("sharpness",2.0-v*2.0,false))
	elif s.scaling == "bilinear":
		range_slider(parent,"Scala di rendering",.5,1.0,.01,s.render_scale,func(v):return "%d%%" % roundi(v*100),func(v):edit("render_scale",v,false))
	stepper(parent,"Anti-aliasing",PCVideo.AA_MODES.map(func(m):return PCVideo.AA_NAMES[m]),PCVideo.AA_MODES.find(s.aa),func(i):edit("aa",PCVideo.AA_MODES[i]))
	var msaa_names: Array = PCVideo.MSAA_LEVELS.map(func(v):return "Disattivato" if v == 0 else "%dx" % v)
	stepper(parent,"MSAA",msaa_names,PCVideo.MSAA_LEVELS.find(PCVideo.normalized(s).msaa),func(i):edit("msaa",PCVideo.MSAA_LEVELS[i]))
	if s.scaling == "fsr2" or s.aa == "taa":
		note(parent,"Con FSR 2.2 e TAA l'MSAA resta disattivato: i due metodi non possono convivere. FSR 2.2 include già il proprio anti-aliasing.")
	heading(parent,"EFFETTI")
	var level_names := PCVideo.SSAO_LEVELS.map(func(l):return PCVideo.LEVEL_NAMES[l])
	if forward:
		stepper(parent,"Occlusione ambientale",level_names,PCVideo.SSAO_LEVELS.find(s.ssao),func(i):edit("ssao",PCVideo.SSAO_LEVELS[i]))
		toggle(parent,"Glow",s.glow,func(v):edit("glow",v))
	stepper(parent,"Ombre",PCVideo.SHADOW_LEVELS.map(func(l):return PCVideo.LEVEL_NAMES[l]),PCVideo.SHADOW_LEVELS.find(s.shadows),func(i):edit("shadows",PCVideo.SHADOW_LEVELS[i]))
	toggle(parent,"Ombre morbide",s.soft_shadows,func(v):edit("soft_shadows",v))
	toggle(parent,"Nebbia",s.fog,func(v):edit("fog",v))
	stepper(parent,"Filtro anisotropico",PCVideo.ANISO_LEVELS.map(func(v):return "Disattivato" if v == 0 else "%dx" % v),PCVideo.ANISO_LEVELS.find(s.aniso),func(i):edit("aniso",PCVideo.ANISO_LEVELS[i]))
	stepper(parent,"Particelle",["Ridotte","Complete"],1 if s.particles == "high" else 0,func(i):edit("particles","high" if i == 1 else "low"))
	heading(parent,"SCHEDA GRAFICA")
	note(parent,PCVideo.gpu_text())
	if PCVideo.is_nvidia():
		note(parent,"DLSS non è supportato da questa versione del motore di gioco (Godot 4.7). FSR 2.2 offre lo stesso tipo di miglioramento su qualsiasi scheda, NVIDIA compresa.")
	elif not forward:
		note(parent,"Questo dispositivo usa il renderer compatibile: FSR e occlusione ambientale non sono disponibili.")

# ---- Pagina Audio ----

func build_audio(parent: Node) -> void:
	heading(parent,"VOLUME")
	ui.slider(parent,"Musica",game.music_volume,game.change_music)
	ui.slider(parent,"Effetti sonori",game.effects_volume,ui.change_effects)

# ---- Pagina Comandi (rimappatura in input_bindings.gd) ----

func build_controls(parent: Node) -> void:
	var Bindings = load("res://scripts/input_bindings.gd")
	Bindings.build_page(self,parent)

# ---- Pagina Sistema ----

func build_system(parent: Node) -> void:
	heading(parent,"SESTRIA")
	ui.label(parent,"VERSIONE "+str(ProjectSettings.get_setting("application/config/version","")),17,ui.GOLD,true)
	if game.updater:
		note(parent,"Gli aggiornamenti provengono dalle release pubbliche di GitHub e si applicano dall’app: firma e SHA-256 vengono verificate prima del riavvio.")
		ui.button(parent,"AGGIORNAMENTI",ui.show_updates,0,true)
	if Platform.is_windows() or OS.get_environment("SESTRIA_FAKE_WINDOWS") != "":
		var Installer = load("res://scripts/windows_installer.gd")
		Installer.build_section(self,parent)
	if game.updater:
		ui.button(parent,"Apri le release su GitHub",func():OS.shell_open(game.updater.RELEASES))
