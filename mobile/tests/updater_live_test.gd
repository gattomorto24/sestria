extends SceneTree
# Optional live-network integration. Native APK signatures are tested separately on Android.
const Updates = preload("res://scripts/updater.gd")
class NativeVerificationStub extends RefCounted:
	func validateUpdate(_path: String,_version: String) -> String:
		return ""
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if FileAccess.file_exists(Updates.APK_PATH):
		push_error("Esiste già un aggiornamento locale: il test non lo sovrascrive.")
		quit(1)
		return
	var update := Updates.new()
	root.add_child(update)
	update.current_version="0.0"
	update.bridge=NativeVerificationStub.new()
	update.check_updates()
	var deadline := Time.get_ticks_msec()+300000
	while update.state=="checking" and Time.get_ticks_msec()<deadline:
		await process_frame
	if update.state!="available":
		push_error("GITHUB_LIVE: "+update.state+" · "+update.message)
		quit(1)
		return
	print("GITHUB_LIVE_RELEASE: ",update.release.version," · ",update.release.size," bytes · ",update.release.sha256)
	update.download_update()
	while update.state in ["downloading","verifying"] and Time.get_ticks_msec()<deadline:
		await process_frame
	if update.state!="ready":
		push_error("GITHUB_LIVE_DOWNLOAD: "+update.state+" · "+update.message)
		quit(1)
		return
	var actual := FileAccess.get_sha256(Updates.APK_PATH)
	var ok := actual==str(update.release.sha256)
	print("GITHUB_LIVE_DOWNLOAD_OK: ",actual," · verifica firma coperta dal collaudo nativo Android")
	Updates.remove_file(Updates.APK_PATH)
	update.queue_free()
	await process_frame
	quit(0 if ok else 1)
