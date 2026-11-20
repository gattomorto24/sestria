extends SceneTree
func _initialize() -> void:
	for pair in [["res://assets/ui/brand_banner.svg","res://assets/ui/banner.png"],["res://assets/ui/mobile_splash.svg","res://assets/ui/mobile_splash.png"]]:
		var image := Image.new()
		var error := image.load_svg_from_string(FileAccess.get_file_as_string(pair[0]))
		if error != OK:
			quit(1)
			return
		image.save_png(pair[1])
	quit()
