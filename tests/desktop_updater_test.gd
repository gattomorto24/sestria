extends SceneTree
const Updates = preload("res://scripts/desktop_updater.gd")
const Content = preload("res://scripts/content_pack.gd")
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
	if Content.platform_key()!="":
		content_flow(update)
	update.queue_free()
	await process_frame
	print("AGGIORNAMENTI DESKTOP | %d controlli: pacchetti per piattaforma, contenuti firmati, ripiego, integrità, asset, rete e annullamento | errori %d" % [checks,errors])
	quit(1 if errors else 0)

func content_release(version: String, min_base: String, signer: CryptoKey, tamper := false) -> Dictionary:
	var key := Content.platform_key()
	var name := "Sestria-v%s-%s-content.pck" % [version,key]
	var manifest := {"schema":1,"version":version,"engine":Content.engine_label(),"packs":{key:{"name":name,"size":1000,"sha256":"d".repeat(64),"min_base":min_base}}}
	var body := JSON.stringify(manifest)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(body.to_utf8_buffer())
	var text := body+"\n"+Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256,hashing.finish(),signer))+"\n"
	if tamper:
		text = text.replace("1000","9999")
	var tag := "v"+version
	return {"info":{"draft":false,"prerelease":false,"tag_name":tag,"body":"Novità","assets":[
		asset(Content.manifest_name(version),tag),asset(name,tag),asset("Sestria-v%s-macOS-universal.zip" % version,tag),asset("Sestria-v%s-Windows-x64.zip" % version,tag)]},"manifest":text.to_utf8_buffer()}

# Aggiornamento dei contenuti: manifest firmato → "content"; firma falsa, motore diverso, base vecchia o versione respinta → pacchetto completo.
func content_flow(update: Node) -> void:
	var signer := Crypto.new().generate_rsa(2048)
	Content.trusted_key = signer.save_to_string(true)
	Content.dir = "user://desktop_updater_test"
	update.current_version = "4.5"
	update.base_version = "4.5"
	var cases := [["4.6","4.5",false,"content"],["4.6","4.7",false,"package"],["4.6","4.5",true,"package"]]
	for entry in cases:
		var made := content_release(entry[0],entry[1],signer,entry[2])
		for item in made.info.assets:
			if item.name.ends_with("-content.pck"):
				item.size = 1000
				item.digest = "sha256:"+"d".repeat(64)
		update.state = "checking"
		update.step = "manifest"
		update.pending_info = made.info
		update.manifest_received(HTTPRequest.RESULT_SUCCESS,200,made.manifest)
		check(update.state=="available" and update.release.get("mode")==entry[3],"Esito %s per %s" % [entry[3],str(entry)])
		if entry[3]=="package":
			check(not update.fallback_reason.is_empty() and update.message.contains(update.fallback_reason),"Il ripiego spiega il motivo: "+update.fallback_reason)
		else:
			check(update.release.name.ends_with("-content.pck") and update.release.size==1000,"Pacchetto contenuti scelto")
	var made2 := content_release("4.6","4.5",signer)
	made2.info.assets[1].digest = "sha256:"+"d".repeat(64)
	update.state = "checking"
	update.step = "manifest"
	update.pending_info = made2.info
	update.manifest_received(HTTPRequest.RESULT_CANT_CONNECT,0,PackedByteArray())
	check(update.state=="available" and update.release.get("mode")=="package","Manifest irraggiungibile: pacchetto completo")
	var wrong_size := content_release("4.6","4.5",signer)
	wrong_size.info.assets[1].size = 5
	wrong_size.info.assets[1].digest = "sha256:"+"d".repeat(64)
	update.state = "checking"
	update.step = "manifest"
	update.pending_info = wrong_size.info
	update.manifest_received(HTTPRequest.RESULT_SUCCESS,200,wrong_size.manifest)
	check(update.release.get("mode")=="package","Dimensione dell'asset diversa dal manifest: pacchetto completo")
	Content.write_state({"rejected":["4.6"]})
	update.state = "checking"
	update.step = "manifest"
	update.pending_info = made2.info
	update.manifest_received(HTTPRequest.RESULT_SUCCESS,200,made2.manifest)
	check(update.release.get("mode")=="package" and update.fallback_reason.contains("non è riuscito"),"Versione già respinta su questo computer: non si ripete")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Content.state_path()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Content.dir))
