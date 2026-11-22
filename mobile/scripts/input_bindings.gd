extends RefCounted
# Comandi da tastiera di Sestria: tasti predefiniti, rimappatura e salvataggio nella sezione "keys" di user://sestria.cfg.
# Invio resta sempre un secondo tasto per "conferma" e Alt+Invio per lo schermo intero.
const SECTION := "keys"
const ACTIONS := [
	{"id":"confirm","name":"Lancia · conferma · avanza","key":KEY_SPACE},
	{"id":"back","name":"Indietro · menu","key":KEY_ESCAPE},
	{"id":"die1","name":"Tieni il dado 1","key":KEY_1},
	{"id":"die2","name":"Tieni il dado 2","key":KEY_2},
	{"id":"die3","name":"Tieni il dado 3","key":KEY_3},
	{"id":"die4","name":"Tieni il dado 4","key":KEY_4},
	{"id":"die5","name":"Tieni il dado 5","key":KEY_5},
	{"id":"die6","name":"Tieni il dado 6","key":KEY_6},
	{"id":"tactic1","name":"Tattica del primo totem","key":KEY_Q},
	{"id":"tactic2","name":"Tattica del secondo totem","key":KEY_W},
	{"id":"tactic3","name":"Tattica del terzo totem","key":KEY_E},
	{"id":"fullscreen","name":"Schermo intero","key":KEY_F11},
	{"id":"fps","name":"Contatore FPS","key":KEY_F3},
]
# Tasti che non si possono assegnare: servono al sistema o al gioco.
const RESERVED := [KEY_ENTER,KEY_KP_ENTER,KEY_ALT,KEY_CTRL,KEY_SHIFT,KEY_META,KEY_TAB,KEY_PRINT,KEY_CAPSLOCK]

static var current := {}

static func defaults() -> Dictionary:
	var map := {}
	for entry in ACTIONS:
		map[entry.id] = entry.key
	return map

static func ensure() -> void:
	if current.is_empty():
		current = defaults()

static func load_from(config: ConfigFile) -> void:
	current = defaults()
	if not config.has_section(SECTION):
		return
	var seen := {}
	for entry in ACTIONS:
		var value: Variant = config.get_value(SECTION,entry.id,entry.key)
		if value is int and value > 0 and not value in RESERVED and not seen.has(value):
			current[entry.id] = value
			seen[value] = true
		else:
			seen[current[entry.id]] = true

static func save_to(config: ConfigFile) -> void:
	ensure()
	for entry in ACTIONS:
		config.set_value(SECTION,entry.id,current[entry.id])

static func key_for(id: String) -> int:
	ensure()
	return current.get(id,0)

const KEY_NAMES := {KEY_SPACE:"Spazio",KEY_ESCAPE:"Esc",KEY_BACKSPACE:"Backspace",KEY_DELETE:"Canc",KEY_INSERT:"Ins",KEY_HOME:"Inizio",KEY_END:"Fine",KEY_PAGEUP:"Pag su",KEY_PAGEDOWN:"Pag giù",KEY_UP:"Freccia su",KEY_DOWN:"Freccia giù",KEY_LEFT:"Freccia sinistra",KEY_RIGHT:"Freccia destra"}

static func key_name(keycode: int) -> String:
	return KEY_NAMES.get(keycode,OS.get_keycode_string(keycode))

# L'azione collegata a un tasto premuto ("" se nessuna).
static func action_for(event: InputEventKey) -> String:
	ensure()
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		return "fullscreen" if event.alt_pressed else "confirm"
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
		return ""
	for id in current:
		if current[id] == event.keycode:
			return id
	return ""

# Assegna un tasto a un'azione. Se un'altra azione lo usava, le due si scambiano. Restituisce un messaggio d'errore o "".
static func assign(id: String, keycode: int) -> String:
	ensure()
	if keycode in RESERVED or keycode <= 0:
		return "Questo tasto non può essere assegnato."
	if not current.has(id):
		return "Comando sconosciuto."
	for other in current:
		if other != id and current[other] == keycode:
			current[other] = current[id]
	current[id] = keycode
	return ""

static func reset() -> void:
	current = defaults()

class Capture extends Control:
	signal captured(keycode: int)
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			captured.emit(event.keycode)

# Pagina "Comandi" delle impostazioni per i computer. `settings` è l'istanza di pc_settings.gd.
static func build_page(settings: RefCounted, parent: Node) -> void:
	ensure()
	var ui: Control = settings.ui
	var game: Node3D = settings.game
	settings.heading(parent,"TASTIERA")
	settings.note(parent,"Premi un comando per cambiarlo, poi il nuovo tasto. Esc annulla. Invio conferma sempre e Alt+Invio cambia lo schermo intero.")
	for entry in ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		parent.add_child(row)
		var caption: Label = ui.label(row,entry.name,16,ui.IVORY,true)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key_button: Button = ui.button(row,key_name(current[entry.id]),func():listen(settings,entry.id),170)
		key_button.name = "Key_"+entry.id
	settings.heading(parent,"MOUSE")
	settings.note(parent,"Clic sinistro · Seleziona un dado o un totem\nClic destro · Ispeziona le sei facce del dado")
	ui.button(parent,"Ripristina i comandi predefiniti",func():
		reset()
		game.save_settings()
		settings.show_page("comandi"))

static func listen(settings: RefCounted, id: String) -> void:
	var ui: Control = settings.ui
	var game: Node3D = settings.game
	var capture := Capture.new()
	ui.dialog.add_child(capture)
	var holder: Button = ui.dialog.find_child("Key_"+id,true,false)
	if holder:
		holder.text = "Premi un tasto…"
	capture.captured.connect(func(keycode: int):
		capture.queue_free()
		if keycode != KEY_ESCAPE:
			var problem := assign(id,keycode)
			if not problem.is_empty():
				push_warning(problem)
			game.save_settings()
		settings.show_page("comandi"))
