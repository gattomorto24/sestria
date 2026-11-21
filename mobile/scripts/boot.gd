extends Control
const Content = preload("res://scripts/content_pack.gd")
const SCENE := "res://scenes/table.tscn"
var progress_bar: ProgressBar
var status: Label
var ready_at := 0
var failed := false
func _ready() -> void:
	# Prima di caricare il gioco: monta l'eventuale pacchetto contenuti già verificato (vedi content_pack.gd).
	var content_status := Content.apply_at_boot("--no-content-pack" in OS.get_cmdline_user_args())
	if content_status=="applied":
		var broken := Content.validate_loaded()
		if not broken.is_empty():
			push_warning("SESTRIA content: non si carica "+broken)
			Content.reject_after_failed_boot()
			content_status="restart"
	if content_status=="restart":
		recover_from_content()
		return
	var bg := ColorRect.new()
	bg.color = Color("#071316")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 500
	column.add_theme_constant_override("separation",24)
	center.add_child(column)
	var sigil := preload("res://scripts/sigil.gd").new()
	sigil.custom_minimum_size = Vector2(500,300)
	column.add_child(sigil)
	var title := Label.new()
	title.text = "SESTRIA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font",preload("res://assets/fonts/Cinzel.ttf"))
	title.add_theme_font_size_override("font_size",76)
	title.add_theme_color_override("font_color",Color("#f4e7cf"))
	column.add_child(title)
	status = Label.new()
	status.text = "PREPARAZIONE DELLA SFIDA"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_override("font",preload("res://assets/fonts/Manrope.ttf"))
	status.add_theme_font_size_override("font_size",22)
	status.add_theme_color_override("font_color",Color("#a7bdb9"))
	column.add_child(status)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 4
	progress_bar.show_percentage = false
	for type in ["background","fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#d8b47b") if type == "fill" else Color("#243c3e")
		progress_bar.add_theme_stylebox_override(type,style)
	column.add_child(progress_bar)
	await get_tree().process_frame
	ResourceLoader.load_threaded_request(SCENE)

func _process(_delta: float) -> void:
	if failed:
		return
	var progress := []
	var state := ResourceLoader.load_threaded_get_status(SCENE,progress)
	if not progress.is_empty():
		progress_bar.value = float(progress[0])*90
	if state == ResourceLoader.THREAD_LOAD_FAILED:
		if Content.boot_status=="applied":
			Content.reject_after_failed_boot()
			recover_from_content()
			return
		failed = true
		status.text = "Avvio non riuscito. Tocca per riprovare."
		return
	if state == ResourceLoader.THREAD_LOAD_LOADED and ready_at == 0:
		ready_at = Time.get_ticks_msec()
		progress_bar.value = 96
		status.text = "PREPARAZIONE DEL TAVOLO"
		var packed: PackedScene = ResourceLoader.load_threaded_get(SCENE)
		var game := packed.instantiate()
		get_tree().root.add_child(game)
		get_tree().current_scene = game
		move_to_front()
		Content.confirm_when_running(get_tree())
		await get_tree().process_frame
		await get_tree().process_frame
		progress_bar.value = 100
		var fade := create_tween()
		fade.tween_property(self,"modulate:a",0,.25)
		await fade.finished
		queue_free()
# Il pacchetto contenuti non funziona: è già stato scartato; si riavvia l'app con i file integrati.
func recover_from_content() -> void:
	failed = true
	push_warning("SESTRIA content: "+Content.boot_note)
	if not Content.restart(get_tree()):
		get_tree().quit(1)

func _gui_input(event: InputEvent) -> void:
	if failed and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		get_tree().reload_current_scene()
