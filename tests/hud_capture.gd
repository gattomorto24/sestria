extends SceneTree
# Salva schermate della partita (HUD) in build/desktop/hud-*.png. Uso: godot --path . --script res://tests/hud_capture.gd
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func shot(name: String, wait := 0.5) -> void:
	for i in 10:
		await process_frame
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/desktop/hud-"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/desktop"))
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	game.change_pc(preload("res://scripts/pc_video.gd").defaults(),true)
	await shot("0-menu")
	game.start_quick()
	await shot("1-coin")
	game.toss(0)
	await create_timer(2.5).timeout
	await shot("2-roll")
	if game.phase == "roll":
		game.roll()
	await create_timer(7.0).timeout
	await shot("3-select")
	if game.phase == "select":
		game.ui.inspect_die(0,1)
		await shot("4-inspect")
		game.ui.close_context()
		game.confirm_selection()
	await create_timer(4.0).timeout
	await shot("5-after")
	game.ui.ask_leave()
	await shot("6-leave")
	quit()
