extends SceneTree
const Updates = preload("res://scripts/desktop_updater.gd")
var errors := 0
var checks := 0
func check(ok: bool, note: String) -> void:
	checks+=1
	if not ok:
		errors+=1
		push_error(note)
func _initialize() -> void:
	call_deferred("run")
func asset(name: String, tag := "v4.5") -> Dictionary:
	return {"name":name,"state":"uploaded","size":1000,"digest":"sha256:"+"b".repeat(64),"browser_download_url":Updates.RELEASES+"/download/"+tag+"/"+name}
func run() -> void:
	var mac := "-macOS-universal.zip"
	var win := "-Windows-x64.zip"
	var release := {"draft":false,"prerelease":false,"tag_name":"v4.5","body":"Novità","assets":[
		asset("Sestria-v4.5-Android.apk"),asset("Sestria-v4.5-macOS-universal.zip"),asset("Sestria-v4.5-Windows-x64.zip")]}
	check(Updates.parse_release(release,"4.4",mac).name=="Sestria-v4.5-macOS-universal.zip","Seleziona il pacchetto Mac")
	check(Updates.parse_release(release,"4.4",win).name=="Sestria-v4.5-Windows-x64.zip","Seleziona il pacchetto Windows")
	check(Updates.parse_release(release,"4.4","").is_empty(),"Nessun pacchetto per sistemi non supportati")
	check(Updates.parse_release(release,"4.5",mac).is_empty(),"Nessun download della versione corrente")
	check(Updates.parse_release(release,"4.6",mac).is_empty(),"Nessun downgrade")
	for field in ["draft","prerelease"]:
		var bad := release.duplicate(true)
		bad[field]=true
		check(Updates.parse_release(bad,"4.4",mac).is_empty(),"Escluse release "+field)
	for mutation in [["browser_download_url","http://github.com/x.zip"],["browser_download_url","https://example.com/Sestria-v4.5-macOS-universal.zip"],["digest","sha256:bad"],["digest",""],["size",Updates.MAX_PACKAGE+1],["size",0],["state","processing"],["name","Sestria-v4.5-evil-macOS-universal.zip/../x"]]:
		var bad := release.duplicate(true)
		bad.assets[1][mutation[0]]=mutation[1]
		check(Updates.parse_release(bad,"4.4",mac).is_empty(),"Asset non fidato respinto "+str(mutation))
	var update := Updates.new()
	root.add_child(update)
	update.current_version="4.4"
	update.state="checking"
	update.completed(HTTPRequest.RESULT_SUCCESS,404,PackedStringArray(),PackedByteArray())
	check(update.state=="current","Repository senza release gestito")
	update.state="checking"
	update.completed(HTTPRequest.RESULT_SUCCESS,429,PackedStringArray(),PackedByteArray())
	check(update.state=="error","Limite GitHub gestito")
	update.state="checking"
	update.completed(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())
	check(update.state=="error","Assenza di rete gestita")
	if Updates.platform_suffix()!="":
		update.state="checking"
		update.completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(release).to_utf8_buffer())
		check(update.state=="available" and update.release.version=="4.5","Risposta HTTP → aggiornamento disponibile")
	update.state="downloading"
	update.cancel()
	check(update.state=="idle","Download annullabile")
	update.queue_free()
	await process_frame
	print("AGGIORNAMENTI DESKTOP | %d controlli: pacchetti per piattaforma, integrità, asset, rete e annullamento | errori %d" % [checks,errors])
	quit(1 if errors else 0)
