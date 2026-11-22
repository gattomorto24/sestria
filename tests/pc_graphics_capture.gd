extends SceneTree
# Salva schermate del tavolo con diversi livelli e upscaling (finestra reale). Uso: godot --path . --script res://tests/pc_graphics_capture.gd
const PC = preload("res://scripts/pc_video.gd")
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	for i in 12:
		await process_frame
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/desktop/gfx-"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/desktop"))
	var game: Node3D = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	await shot("menu-alta")
	var cases := {"bassa":PC.with_preset(game.pc,"bassa"),"ultra":PC.with_preset(game.pc,"ultra"),
		"fsr1":PC.with_preset(game.pc,"alta").merged({"scaling":"fsr1","fsr_quality":"performance"},true),
		"fsr2":PC.with_preset(game.pc,"alta").merged({"scaling":"fsr2","fsr_quality":"balanced"},true)}
	for name in cases:
		game.change_pc(cases[name],false)
		await shot("menu-"+name)
		print("GFX ",name," · ",root.scaling_3d_mode," · scala ",root.scaling_3d_scale," · msaa ",root.msaa_3d," · taa ",root.use_taa)
	print("GPU: ",PC.gpu_text())
	quit()
