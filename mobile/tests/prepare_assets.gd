extends SceneTree
func _initialize() -> void:
	var image := Image.load_from_file("res://assets/ui/mobile_splash.svg")
	image.save_png("res://assets/ui/mobile_splash.png")
	quit()
