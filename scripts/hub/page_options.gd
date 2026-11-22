extends RefCounted
const Kit = preload("res://scripts/hub/kit.gd")
static func build(hub: Control, parent: VBoxContainer) -> void:
	var box := Kit.panel(parent,"glass",24,26)
	Kit.label(box,"options · in costruzione",24,Kit.TEXT,true)
