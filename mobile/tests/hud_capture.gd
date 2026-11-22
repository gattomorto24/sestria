extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	for i in 12:
		await process_frame
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/portrait/hud-"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/portrait"))
	root.size = Vector2i(405,720)
	var game: Node3D = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	game.start_quick()
	await shot("1-coin")
	game.toss(0)
	await create_timer(2.5).timeout
	if game.phase == "roll":
		game.roll()
	await create_timer(7.0).timeout
	await shot("2-select")
	game.ui.ask_leave()
	await shot("3-pause")
	quit()
