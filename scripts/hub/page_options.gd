extends RefCounted
# Scheda Opzioni: Gioco (scelte visuali), Schermo, Grafica, Audio, Comandi e Sistema. Su Windows e Mac ci sono tutte le
# pagine; sul web e su Android Schermo e Comandi non servono e la grafica è semplificata.
const Kit = preload("res://scripts/hub/kit.gd")
const Store = preload("res://scripts/hub/campaign_store.gd")
const PCVideo = preload("res://scripts/pc_video.gd")
const Bindings = preload("res://scripts/input_bindings.gd")
const Platform = preload("res://scripts/platform.gd")
const NAMES := {"game":"Gioco","screen":"Schermo","graphics":"Grafica","audio":"Audio","controls":"Comandi","system":"Sistema"}
const DIFFICULTY_TEXT := ["Per imparare il rituale.","Una sfida equilibrata.","Nessuna concessione."]
const DIFFICULTY_COLORS := [Kit.MOSS,Kit.EMBER,Kit.WINE]
const START_PAGES := [["campaign","Campagna","Riprendi o crea una campagna."],["multiplayer","Multigiocatore","Passa e gioca, LAN e online."],["friends","Amici","Gli amici e le richieste."],["progress","Progressi","Livello, potenziamenti e statistiche."]]

static func pages(hub: Control) -> Array:
	if Platform.pc_available() and not hub.portrait and "pc" in hub.game:
		return ["game","screen","graphics","audio","controls","system"]
	return ["game","audio","graphics","system"]

static func build(hub: Control, parent: VBoxContainer) -> void:
	var list := pages(hub)
	var current: String = str(hub.page_state.get("tab","game"))
	if not list.has(current):
		current = "game"
	var layout: BoxContainer = Kit.row(parent,16) if not hub.portrait else Kit.column(parent,10)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nav: BoxContainer
	if hub.portrait:
		nav = Kit.tabs(layout,list.map(func(p):return NAMES[p]),list.find(current),func(i):hub.navigate("options",{"tab":list[i]}))
	else:
		var side := Kit.panel(layout,"wood",12,0)
		side.custom_minimum_size.x = 210
		nav = Kit.column(side,8)
		for entry in list:
			var item := Kit.button(nav,NAMES[entry],func():hub.navigate("options",{"tab":entry}),"primary" if entry == current else "secondary")
			item.custom_minimum_size.y = 52
	var frame := Kit.panel(layout,"wood",24,0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := Kit.scroll(frame,14)
	match current:
		"game": build_game(hub,content)
		"screen": build_screen(hub,content)
		"graphics": build_graphics(hub,content)
		"audio": build_audio(hub,content)
		"controls": build_controls(hub,content)
		"system": build_system(hub,content)

static func section(parent: Node, text: String) -> void:
	Kit.title(parent,text,22)

static func reload(hub: Control, tab: String) -> void:
	hub.navigate("options",{"tab":tab})

# ---- Gioco: scelte visuali ----

static func build_game(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	section(parent,"Come si gioca")
	var help := Kit.row(parent,10)
	Kit.button(help,"Regole del gioco",func():hub.show_rules(),"secondary",220)
	Kit.button(help,"Le tue tattiche",func():hub.show_tactics(),"secondary",220)
	section(parent,"All'avvio apri")
	var start: BoxContainer = Kit.row(parent,10) if not hub.portrait else Kit.column(parent,8)
	for entry in START_PAGES:
		var card := Kit.card(start,entry[1],entry[2],game.start_page == entry[0],func():
			game.start_page = entry[0]
			game.save_settings()
			reload(hub,"game"),Kit.EMBER)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section(parent,"Sfida predefinita")
	var difficulty: BoxContainer = Kit.row(parent,10) if not hub.portrait else Kit.column(parent,8)
	for index in 3:
		var card := Kit.card(difficulty,Store.DIFFICULTIES[index],DIFFICULTY_TEXT[index],game.difficulty == index,func():
			game.difficulty = index
			game.save_settings()
			reload(hub,"game"),DIFFICULTY_COLORS[index],["I","II","III"][index])
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section(parent,"Partita al volo")
	Kit.paragraph(parent,"Queste scelte valgono per la partita al volo. Ogni campagna ha le sue, scelte quando la crei.",0.0,15,Kit.MUTED)
	for entry in Store.SETTINGS:
		var line := Kit.setting_row(parent,str(entry.name),str(entry.hint))
		var labels: Array = []
		var active := 0
		for index in entry.options.size():
			labels.append(entry.options[index][1])
			if typeof(entry.options[index][0]) == typeof(game.quick_settings[entry.id]) and entry.options[index][0] == game.quick_settings[entry.id]:
				active = index
		var holder: Control = line
		if hub.portrait:
			var column := Kit.column(null,6)
			line.get_parent().add_child(column)
			line.get_parent().move_child(column,line.get_index())
			line.get_parent().remove_child(line)
			column.add_child(line)
			holder = column
		Kit.segments(holder,labels,active,func(index):
			game.quick_settings[entry.id] = entry.options[index][0]
			game.save_settings()
			reload(hub,"game"))
		Kit.divider(parent)

# ---- Audio ----

static func slider_row(parent: Node, title: String, value: float, callback: Callable) -> void:
	var line := Kit.row(parent,16)
	var caption := Kit.label(line,title,18,Kit.TEXT,false,600)
	caption.custom_minimum_size.x = Kit.scale(170)
	var current := Kit.label(null,"%d%%" % roundi(value*100),16,Kit.EMBER_LIGHT,false,700)
	Kit.slider(line,0.0,1.0,.01,value,func(v):
		current.text = "%d%%" % roundi(v*100)
		callback.call(v))
	line.add_child(current)
	current.custom_minimum_size.x = Kit.scale(56)

static func build_audio(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	section(parent,"Volume")
	slider_row(parent,"Musica",game.music_volume,func(v):
		game.change_music(v)
		hub.audio.refresh_volume())
	slider_row(parent,"Effetti sonori",game.effects_volume,func(v):
		game.effects_volume = v
		game.save_settings())
	Kit.paragraph(parent,"La musica del menu e i suoni di legno, cuoio e pergamena si regolano qui. Il tema del menu cambia da solo quando inizia una partita.",0.0,15,Kit.MUTED)

# ---- Schermo (Windows e Mac) ----

static func edit(hub: Control, key: String, value: Variant, tab: String, redisplay := true) -> void:
	var next: Dictionary = hub.game.pc.duplicate()
	next[key] = value
	if next.preset != "custom" and PCVideo.detect_preset(next) != next.preset:
		next.preset = PCVideo.detect_preset(next)
	hub.game.change_pc(next,false)
	if redisplay:
		reload(hub,tab)

# Modifica di finestra: si applica e si chiede conferma; senza risposta tornano le impostazioni di prima.
static func edit_display(hub: Control, key: String, value: Variant) -> void:
	var previous: Dictionary = hub.game.pc.duplicate()
	var next: Dictionary = hub.game.pc.duplicate()
	next[key] = value
	hub.game.change_pc(next,true)
	var body: VBoxContainer = hub.modal("Mantenere queste impostazioni?",520)
	var message := Kit.paragraph(body,"",0.0,16,Kit.MUTED)
	var seconds := {"left":12}
	message.text = "Se non confermi, le impostazioni precedenti tornano tra %d secondi." % seconds.left
	var timer := Timer.new()
	timer.wait_time = 1.0
	body.add_child(timer)
	timer.timeout.connect(func():
		seconds.left -= 1
		if seconds.left <= 0:
			timer.stop()
			hub.game.change_pc(previous,true)
			reload(hub,"screen")
		else:
			message.text = "Se non confermi, le impostazioni precedenti tornano tra %d secondi." % seconds.left)
	timer.start()
	var line := Kit.row(body,10)
	Kit.button(line,"Mantieni",func():
		timer.stop()
		hub.close_modal()
		reload(hub,"screen"),"primary")
	Kit.button(line,"Ripristina",func():
		timer.stop()
		hub.game.change_pc(previous,true)
		reload(hub,"screen"),"secondary")

static func option_row(hub: Control, parent: Node, title: String, hint: String) -> Control:
	var line := Kit.setting_row(parent,title,hint)
	return line

static func build_screen(hub: Control, parent: VBoxContainer) -> void:
	var s: Dictionary = hub.game.pc
	var screens := DisplayServer.get_screen_count()
	var monitor := clampi(s.monitor,0,screens-1)
	section(parent,"Finestra")
	if screens > 1:
		var names: Array = []
		for i in screens:
			var size := DisplayServer.screen_get_size(i)
			names.append("Monitor %d · %dx%d" % [i+1,size.x,size.y])
		Kit.stepper(option_row(hub,parent,"Monitor",""),names,monitor,func(i):edit_display(hub,"monitor",i),300)
	var modes := PCVideo.WINDOW_MODES
	var mode_cards: BoxContainer = Kit.row(parent,10)
	for index in modes.size():
		var card := Kit.card(mode_cards,PCVideo.WINDOW_NAMES[modes[index]],["Con bordi, ridimensionabile.","A tutto schermo, senza bordi.","A tutto schermo, esclusivo."][index],s.window_mode == modes[index],func():edit_display(hub,"window_mode",modes[index]),Kit.EMBER)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if s.window_mode == "window":
		var options := PCVideo.resolution_options(DisplayServer.screen_get_size(monitor))
		var current := PCVideo.parse_resolution(s.resolution)
		var index := options.find(current)
		if index < 0:
			options.append(current)
			index = options.size()-1
		Kit.stepper(option_row(hub,parent,"Risoluzione","Dimensione della finestra."),options.map(PCVideo.resolution_text),index,func(i):edit_display(hub,"resolution",PCVideo.resolution_text(options[i])))
	else:
		Kit.paragraph(parent,"A tutto schermo il gioco usa la risoluzione del monitor. Per alleggerire la scheda grafica abbassa la scala di rendering o attiva FSR dalla pagina Grafica.",0.0,15,Kit.MUTED)
	var scale_line := option_row(hub,parent,"Scala dell'interfaccia","")
	var shown := Kit.label(null,"%d%%" % roundi(s.ui_scale*100),16,Kit.EMBER_LIGHT,false,700)
	Kit.slider(scale_line,.75,1.5,.05,s.ui_scale,func(v):
		shown.text = "%d%%" % roundi(v*100)
		edit(hub,"ui_scale",v,"screen",false))
	scale_line.add_child(shown)
	section(parent,"Fluidità")
	Kit.segments(option_row(hub,parent,"V-Sync","Sincronizza i fotogrammi con il monitor."),PCVideo.VSYNC_MODES.map(func(m):return PCVideo.VSYNC_NAMES[m]),PCVideo.VSYNC_MODES.find(s.vsync),func(i):edit(hub,"vsync",PCVideo.VSYNC_MODES[i],"screen"))
	Kit.stepper(option_row(hub,parent,"Limite di fotogrammi",""),PCVideo.FPS_CAPS.map(func(v):return "Illimitato" if v == 0 else "%d FPS" % v),PCVideo.FPS_CAPS.find(s.fps_cap),func(i):edit(hub,"fps_cap",PCVideo.FPS_CAPS[i],"screen"))
	Kit.toggle(option_row(hub,parent,"Contatore FPS","Mostra i fotogrammi al secondo."),s.fps_counter,func(v):edit(hub,"fps_counter",v,"screen"))
	Kit.paragraph(parent,"F11 o Alt+Invio cambiano rapidamente tra finestra e schermo intero.",0.0,15,Kit.DIM)

# ---- Grafica ----

static func level_row(hub: Control, parent: Node, title: String, hint: String, key: String, values: Array, names: Array, current: Variant, tab := "graphics") -> void:
	var line := option_row(hub,parent,title,hint)
	var index := values.find(current)
	if names.size() <= 4:
		Kit.segments(line,names,index,func(i):edit(hub,key,values[i],tab))
	else:
		Kit.stepper(line,names,index,func(i):edit(hub,key,values[i],tab),140)

static func build_graphics(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	if not ("pc" in game) or game.pc.is_empty():
		build_simple_graphics(hub,parent)
		return
	var s: Dictionary = game.pc
	var forward := PCVideo.upscaling_available()
	section(parent,"Qualità")
	var presets: BoxContainer = Kit.row(parent,10) if not hub.portrait else Kit.column(parent,8)
	var descriptions := {"bassa":"Più fluidità, meno effetti.","media":"Un buon equilibrio.","alta":"L'aspetto di sempre.","ultra":"Il massimo per schede potenti."}
	for name in PCVideo.PRESETS:
		var card := Kit.card(presets,PCVideo.PRESET_NAMES[name],descriptions[name],s.preset == name,func():
			game.change_pc(PCVideo.with_preset(game.pc,name),false)
			reload(hub,"graphics"),Kit.EMBER)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if s.preset == "custom":
		Kit.label(parent,"Impostazioni personalizzate: hai modificato alcune voci.",15,Kit.EMBER_LIGHT,false,600)
	section(parent,"Upscaling e anti-aliasing")
	var modes := PCVideo.SCALING_MODES.filter(func(m):return forward or not m in ["fsr1","fsr2"])
	level_row(hub,parent,"Upscaling","FSR rende l'immagine nitida con meno fatica.","scaling",modes,modes.map(func(m):return PCVideo.SCALING_NAMES[m]),s.scaling)
	if s.scaling in ["fsr1","fsr2"]:
		var qualities := PCVideo.FSR_QUALITY.keys()
		level_row(hub,parent,"Qualità FSR","","fsr_quality",qualities,qualities.map(func(q):return "%s · %d%%" % [PCVideo.FSR_NAMES[q],roundi(PCVideo.FSR_QUALITY[q]*100)]),s.fsr_quality)
		var sharp := option_row(hub,parent,"Nitidezza","")
		Kit.slider(sharp,0.0,1.0,.05,(2.0-s.sharpness)/2.0,func(v):edit(hub,"sharpness",2.0-v*2.0,"graphics",false))
	elif s.scaling == "bilinear":
		var scale_line := option_row(hub,parent,"Scala di rendering","")
		Kit.slider(scale_line,.5,1.0,.01,s.render_scale,func(v):edit(hub,"render_scale",v,"graphics",false))
	level_row(hub,parent,"Anti-aliasing","","aa",PCVideo.AA_MODES,PCVideo.AA_MODES.map(func(m):return PCVideo.AA_NAMES[m]),s.aa)
	level_row(hub,parent,"MSAA","","msaa",PCVideo.MSAA_LEVELS,PCVideo.MSAA_LEVELS.map(func(v):return "No" if v == 0 else "%dx" % v),PCVideo.normalized(s).msaa)
	if s.scaling == "fsr2" or s.aa == "taa":
		Kit.paragraph(parent,"Con FSR 2.2 e TAA l'MSAA resta spento: i due metodi non possono convivere. FSR 2.2 ha già il suo anti-aliasing.",0.0,14,Kit.DIM)
	section(parent,"Effetti")
	if forward:
		level_row(hub,parent,"Occlusione ambientale","","ssao",PCVideo.SSAO_LEVELS,PCVideo.SSAO_LEVELS.map(func(l):return PCVideo.LEVEL_NAMES[l]),s.ssao)
		Kit.toggle(option_row(hub,parent,"Glow",""),s.glow,func(v):edit(hub,"glow",v,"graphics"))
	level_row(hub,parent,"Ombre","","shadows",PCVideo.SHADOW_LEVELS,PCVideo.SHADOW_LEVELS.map(func(l):return PCVideo.LEVEL_NAMES[l]),s.shadows)
	Kit.toggle(option_row(hub,parent,"Ombre morbide",""),s.soft_shadows,func(v):edit(hub,"soft_shadows",v,"graphics"))
	Kit.toggle(option_row(hub,parent,"Nebbia",""),s.fog,func(v):edit(hub,"fog",v,"graphics"))
	level_row(hub,parent,"Filtro anisotropico","","aniso",PCVideo.ANISO_LEVELS,PCVideo.ANISO_LEVELS.map(func(v):return "No" if v == 0 else "%dx" % v),s.aniso)
	level_row(hub,parent,"Particelle","","particles",["low","high"],["Ridotte","Complete"],s.particles)
	section(parent,"Scheda grafica")
	Kit.paragraph(parent,PCVideo.gpu_text(),0.0,16,Kit.TEXT)
	if PCVideo.is_nvidia():
		Kit.paragraph(parent,"DLSS non è supportato da questa versione del motore di gioco (Godot 4.7). FSR 2.2 offre lo stesso tipo di miglioramento su qualsiasi scheda, NVIDIA compresa.",0.0,15,Kit.MUTED)
	elif not forward:
		Kit.paragraph(parent,"Questo dispositivo usa il renderer compatibile: FSR e occlusione ambientale non sono disponibili.",0.0,15,Kit.MUTED)

static func build_simple_graphics(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	section(parent,"Qualità")
	if "graphics_mode" in game:
		# Android: tre profili, con limite di fotogrammi
		var cards: BoxContainer = Kit.column(parent,8)
		var names := ["Bilanciata · 60 fps","Risparmio · 30 fps","Qualità · 60 fps"]
		var texts := ["Il consiglio per la maggior parte dei telefoni.","Meno calore e meno consumi.","Tutti gli effetti, per telefoni potenti."]
		for i in 3:
			Kit.card(cards,names[i],texts[i],game.graphics_mode == i,func():
				game.graphics_mode = i
				game.adaptive_level = 0
				game.apply_mobile_quality()
				game.save_settings()
				reload(hub,"graphics"),Kit.EMBER)
		Kit.paragraph(parent,"I valori indicano il limite dei fotogrammi. La fluidità effettiva dipende dal telefono.",0.0,14,Kit.DIM)
		Kit.toggle(Kit.setting_row(parent,"Adatta al dispositivo","Abbassa da solo la qualità se il telefono fatica."),game.adaptive,func(v):
			game.adaptive = v
			game.save_settings()
			reload(hub,"graphics"))
		Kit.toggle(Kit.setting_row(parent,"Vibrazione","Un piccolo impulso quando tocchi."),game.haptics,func(v):
			game.haptics = v
			game.save_settings()
			reload(hub,"graphics"))
		return
	var cards: BoxContainer = Kit.row(parent,10) if not hub.portrait else Kit.column(parent,8)
	for index in 2:
		var low: bool = index == 1
		var card := Kit.card(cards,["Alta","Ridotta"][index],["Risoluzione nativa e tutti gli effetti.","Modalità prestazioni: meno effetti, più fluidità."][index],game.reduced == low,func():
			game.change_quality(low)
			reload(hub,"graphics"),Kit.EMBER)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Platform.fullscreen_available():
		section(parent,"Schermo")
		Kit.button(parent,"Esci dallo schermo intero" if Platform.is_fullscreen() else "Schermo intero",func():
			Platform.toggle_fullscreen()
			reload(hub,"graphics"),"secondary",260)

# ---- Comandi ----

static func build_controls(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	Bindings.ensure()
	section(parent,"Tastiera")
	Kit.paragraph(parent,"Premi un comando per cambiarlo, poi il nuovo tasto. Esc annulla. Invio conferma sempre e Alt+Invio cambia lo schermo intero.",0.0,15,Kit.MUTED)
	for entry in Bindings.ACTIONS:
		var line := Kit.row(parent,12)
		var caption := Kit.label(line,str(entry.name),17,Kit.TEXT,false,600)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := Kit.button(line,Bindings.key_name(Bindings.current[entry.id]),func():listen(hub,entry.id),"secondary",170)
		key.name = "Key_"+str(entry.id)
	section(parent,"Mouse")
	Kit.paragraph(parent,"Clic sinistro seleziona un dado o un totem. Clic destro ispeziona le sei facce del dado.",0.0,15,Kit.MUTED)
	Kit.button(parent,"Ripristina i comandi predefiniti",func():
		Bindings.reset()
		game.save_settings()
		reload(hub,"controls"),"secondary")

static func listen(hub: Control, id: String) -> void:
	var capture := Bindings.Capture.new()
	hub.add_child(capture)
	var holder: Button = hub.find_child("Key_"+id,true,false)
	if holder:
		holder.text = "Premi un tasto…"
	capture.captured.connect(func(keycode: int):
		capture.queue_free()
		if keycode != KEY_ESCAPE:
			Bindings.assign(id,keycode)
			hub.game.save_settings()
		reload(hub,"controls"))

# ---- Sistema ----

static func build_system(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	section(parent,"SESTRIA")
	Kit.label(parent,"Versione "+str(ProjectSettings.get_setting("application/config/version","")),18,Kit.EMBER_LIGHT,false,700)
	if game.updater:
		build_updates(hub,parent)
	else:
		Kit.paragraph(parent,"Edizione web: si aggiorna da sola a ogni caricamento della pagina. I progressi restano in questo browser.",0.0,16,Kit.MUTED)
	if Platform.is_windows() or OS.get_environment("SESTRIA_FAKE_WINDOWS") != "":
		var Installer = load("res://scripts/windows_installer.gd")
		Installer.build_section(hub,parent)
	if hub.ui.has_method("show_diagnostics"):
		Kit.button(parent,"Diagnostica locale",func():hub.ui.show_diagnostics(),"secondary",260)
	section(parent,"Dati")
	Kit.paragraph(parent,"Profilo, campagne, statistiche e progressi sono salvati su questo dispositivo.",0.0,15,Kit.MUTED)

static func build_updates(hub: Control, parent: VBoxContainer) -> void:
	var update: Node = hub.game.updater
	section(parent,"Aggiornamenti")
	var message := Kit.paragraph(parent,str(update.message),0.0,16,Kit.TEXT)
	message.name = "UpdateMessage"
	if update.state in ["downloading","verifying","ready"]:
		var meter := Kit.meter(parent,update.progress,1.0,16)
		meter.name = "UpdateMeter"
	if update.state == "available":
		Kit.label(parent,"Nuova versione · "+str(update.release.version),17,Kit.MOSS,false,700)
		if not str(update.release.get("notes","")).is_empty():
			Kit.paragraph(parent,str(update.release.notes),0.0,14,Kit.MUTED)
		Kit.button(parent,"AGGIORNA" if update.release.get("mode","package") == "content" else ("SCARICA L'APK COMPLETO" if update.has_method("install_update") else "SCARICA IL PACCHETTO COMPLETO"),update.download_update,"primary",260)
	elif update.state == "ready":
		if update.release.get("mode","package") == "content":
			Kit.button(parent,"RIAVVIA PER APPLICARE",update.restart_to_apply,"primary",260)
		elif update.has_method("install_update"):
			Kit.button(parent,"INSTALLA AGGIORNAMENTO",update.install_update,"primary",260)
		else:
			Kit.button(parent,"MOSTRA NELLA CARTELLA DOWNLOAD",update.reveal_update,"primary",260)
	elif update.state in ["checking","downloading"]:
		Kit.button(parent,"Annulla",update.cancel,"secondary")
	elif update.state != "verifying":
		Kit.button(parent,"VERIFICA NUOVI AGGIORNAMENTI",update.check_updates,"primary",260)
	Kit.paragraph(parent,"Gli aggiornamenti provengono dalle release pubbliche di GitHub. L'app scarica i nuovi contenuti, ne controlla firma e SHA-256 e li applica al riavvio. Se una versione cambia anche il motore, si scarica il pacchetto completo in Download.",0.0,14,Kit.DIM)
	Kit.button(parent,"Apri le release su GitHub",func():OS.shell_open(update.RELEASES),"ghost")
	if not update.last_checked.is_empty():
		Kit.label(parent,"Ultima verifica · "+update.last_checked,13,Kit.DIM)
