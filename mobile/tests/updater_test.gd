extends SceneTree
const Updates = preload("res://scripts/updater.gd")
var errors := 0
var checks := 0
func check(ok: bool, note: String) -> void:
	checks+=1
	if not ok:
		errors+=1
		push_error(note)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for pair in [["4.4","4.3",true],["v4.3.1","4.3",true],["10.0","9.9",true],["4.3.0","4.3",false],["4.2","4.3",false],["4.4-beta","4.3",false],["4.x","4.3",false],["4.3/evil","4.2",false]]:
		check(Updates.newer(pair[0],pair[1])==pair[2],"Confronto semantico versioni "+str(pair))
	var valid := {"draft":false,"prerelease":false,"tag_name":"v4.4","body":"Novità","assets":[{"name":"Sestria-v4.4-Android.apk","state":"uploaded","size":100,"digest":"sha256:"+"a".repeat(64),"browser_download_url":Updates.RELEASES+"/download/v4.4/Sestria-v4.4-Android.apk"}]}
	check(Updates.parse_release(valid,"4.3").get("version")=="4.4","Release pubblica valida")
	for field in ["draft","prerelease"]:
		var bad := valid.duplicate(true)
		bad[field]=true
		check(Updates.parse_release(bad,"4.3").is_empty(),"Escluse release "+field)
	for mutation in [["browser_download_url","http://github.com/x.apk"],["browser_download_url","https://github.com/another/repo/releases/download/v4.4/app.apk"],["digest","sha256:bad"],["digest",""],["size",Updates.MAX_APK+1],["size",0],["state","processing"],["name","Sestria-debug.apk"]]:
		var bad := valid.duplicate(true)
		bad.assets[0][mutation[0]]=mutation[1]
		check(Updates.parse_release(bad,"4.3").is_empty(),"Asset incompleto o non fidato respinto "+str(mutation))
	check(Updates.parse_release(valid,"4.4").is_empty(),"Nessun download ripetuto della versione corrente")
	var update := Updates.new()
	root.add_child(update)
	update.state="checking"
	update.completed(HTTPRequest.RESULT_SUCCESS,404,PackedStringArray(),PackedByteArray())
	check(update.state=="current","Repository senza release gestito")
	update.state="checking"
	update.completed(HTTPRequest.RESULT_SUCCESS,429,PackedStringArray(),PackedByteArray())
	check(update.state=="error","Limite GitHub gestito")
	update.state="checking"
	update.completed(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())
	check(update.state=="error","Assenza di rete gestita")
	update.state="checking"
	update.completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(valid).to_utf8_buffer())
	check(update.state=="available" and update.release.version=="4.4","Risposta HTTP → aggiornamento disponibile")
	update.state="downloading"
	update.cancel()
	check(update.state=="idle","Download annullabile")
	update.queue_free()
	await process_frame
	print("AGGIORNAMENTI | %d controlli: versioni, GitHub, integrità, asset, rete, rate limit e annullamento | errori %d" % [checks,errors])
	quit(1 if errors else 0)
