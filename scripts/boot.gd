extends Node
# Scena di avvio senza interfaccia: monta l'eventuale pacchetto contenuti già verificato e passa al gioco.
# Il pacchetto viene montato prima che qualunque scena o script del gioco sia caricato.
const Content = preload("res://scripts/content_pack.gd")
const SCENE := "res://scenes/table.tscn"

func _ready() -> void:
	var skip := "--no-content-pack" in OS.get_cmdline_args() or "--no-content-pack" in OS.get_cmdline_user_args()
	var status := Content.apply_at_boot(skip)
	if status=="restart":
		fail_and_restart.call_deferred()
		return
	start.call_deferred()

func start() -> void:
	var broken := Content.validate_loaded() if Content.boot_status=="applied" else ""
	if not broken.is_empty():
		push_warning("SESTRIA content: non si carica "+broken)
	var packed := load(SCENE) as PackedScene if broken.is_empty() else null
	var game := packed.instantiate() if packed!=null else null
	if packed==null or game==null:
		if Content.boot_status=="applied":
			# Il pacchetto non permette di caricare il gioco: lo si rifiuta e si riparte dai file integrati.
			Content.reject_after_failed_boot()
			fail_and_restart()
		else:
			push_error("SESTRIA: la scena principale non si carica.")
			get_tree().quit(1)
		return
	var tree := get_tree()
	tree.root.add_child(game)
	tree.current_scene = game
	queue_free()
	Content.confirm_when_running(tree)
	print("SESTRIA contenuti %s · base %s · %s" % [Content.running_version(),Content.base_version(),Content.boot_status])

func fail_and_restart() -> void:
	push_warning("SESTRIA content: "+Content.boot_note)
	if not Content.restart(get_tree()):
		push_error("SESTRIA: riavvia l'app per tornare ai contenuti integrati.")
		get_tree().quit(1)
