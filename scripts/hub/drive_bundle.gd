extends RefCounted
# Il pacchetto di salvataggio che va su Google Drive (un file creato dall'app): progressi, campagne, profilo, amici,
# statistiche e preferenze di gioco. `merge` unisce due pacchetti (questo dispositivo e Drive) senza perdere nulla.
const Profile = preload("res://scripts/hub/profile_store.gd")
const SCHEMA := 1

static func now() -> int:
	return int(Time.get_unix_time_from_system())

# ---- Lettura dal gioco ----

static func collect(game: Node) -> Dictionary:
	var bundle := {"schema":SCHEMA,"saved":now()}
	bundle.progression = {"xp":int(game.progression.data.xp),"ranks":game.progression.data.ranks.duplicate(true),"claimed":game.progression.data.claimed.duplicate(true)}
	bundle.campaigns = {"items":game.campaigns.campaigns.duplicate(true),"deleted":game.campaigns.deleted.duplicate()}
	bundle.profile = game.profile.data.duplicate(true)
	var stats: Dictionary = game.stats_store.data.duplicate(true) if game.stats_store else {}
	bundle.statistics = stats
	if game.friends != null:
		var f: RefCounted = game.friends.store
		bundle.friends = {"friends":f.friends.duplicate(true),"removed":f.removed.duplicate()}
	bundle.settings = {"updated":int(game.settings_updated),"difficulty":int(game.difficulty),"favors":game.equipped.duplicate(),"start_page":str(game.start_page),"quick":game.quick_settings.duplicate(true)}
	return bundle

# ---- Unione ----

static func newer_list(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for x in b:
		if not out.has(x):
			out.append(x)
	return out

static func merge_progression(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"xp":maxi(int(a.get("xp",0)),int(b.get("xp",0))),"ranks":{},"claimed":{}}
	for source in [a,b]:
		for key in source.get("claimed",{}):
			out.claimed[key] = true
		for key in source.get("ranks",{}):
			out.ranks[key] = maxi(int(out.ranks.get(key,0)),int(source.ranks[key]))
	# i punti spesi non possono superare quelli guadagnati: altrimenti si azzera la scelta dei potenziamenti
	var Progression = preload("res://scripts/progression.gd")
	var level := 1
	var remaining: int = out.xp
	while remaining >= Progression.xp_required(level):
		remaining -= Progression.xp_required(level)
		level += 1
	var spent := 0
	for id in out.ranks:
		if Progression.UPGRADES.has(id):
			var rank: int = clampi(int(out.ranks[id]),0,Progression.UPGRADES[id].costs.size())
			out.ranks[id] = rank
			for index in rank:
				spent += int(Progression.UPGRADES[id].costs[index])
	if spent > (level-1)*2:
		out.ranks = {}
	return out

static func merge_campaigns(a: Dictionary, b: Dictionary) -> Dictionary:
	var deleted: Array = newer_list(a.get("deleted",[]),b.get("deleted",[]))
	var by_id := {}
	for source in [a,b]:
		for item in source.get("items",[]):
			if not item is Dictionary or deleted.has(str(item.get("id",""))):
				continue
			var id := str(item.id)
			if not by_id.has(id):
				by_id[id] = item
			else:
				var mine: Dictionary = by_id[id]
				var mine_games: int = int(mine.get("wins",0))+int(mine.get("losses",0))
				var other_games: int = int(item.get("wins",0))+int(item.get("losses",0))
				if other_games > mine_games or (other_games == mine_games and int(item.get("played",0)) > int(mine.get("played",0))):
					by_id[id] = item
	return {"items":by_id.values(),"deleted":deleted}

static func merge_profile(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a if int(a.get("updated",0)) >= int(b.get("updated",0)) else b
	out = out.duplicate(true)
	# il codice amico è quello del profilo più vecchio, così è lo stesso su tutti i dispositivi
	var older: Dictionary = a if (int(a.get("created",0)) > 0 and (int(a.get("created",0)) <= int(b.get("created",0)) or int(b.get("created",0)) == 0)) else b
	if Profile.valid_id(str(older.get("friend_id",""))):
		out.friend_id = older.friend_id
		out.created = older.get("created",0)
	return out

static func merge_friends(a: Dictionary, b: Dictionary) -> Dictionary:
	var removed: Array = newer_list(a.get("removed",[]),b.get("removed",[]))
	var by_id := {}
	for source in [a,b]:
		for item in source.get("friends",[]):
			if item is Dictionary and not removed.has(str(item.get("id",""))):
				var id := str(item.id)
				if not by_id.has(id) or int(item.get("seen",0)) > int(by_id[id].get("seen",0)):
					by_id[id] = item
	return {"friends":by_id.values(),"removed":removed}

static func merge(local: Dictionary, remote: Dictionary) -> Dictionary:
	if remote.is_empty() or int(remote.get("schema",0)) != SCHEMA:
		return local.duplicate(true)
	var out := {"schema":SCHEMA,"saved":now()}
	out.progression = merge_progression(local.get("progression",{}),remote.get("progression",{}))
	out.campaigns = merge_campaigns(local.get("campaigns",{}),remote.get("campaigns",{}))
	out.profile = merge_profile(local.get("profile",{}),remote.get("profile",{}))
	var ls: Dictionary = local.get("statistics",{})
	var rs: Dictionary = remote.get("statistics",{})
	out.statistics = ls if int(ls.get("played",0)) >= int(rs.get("played",0)) else rs
	if local.has("friends") or remote.has("friends"):
		out.friends = merge_friends(local.get("friends",{}),remote.get("friends",{}))
	var lset: Dictionary = local.get("settings",{})
	var rset: Dictionary = remote.get("settings",{})
	out.settings = lset if int(lset.get("updated",0)) >= int(rset.get("updated",0)) else rset
	return out

# Due pacchetti dicono la stessa cosa (si ignora l'ora di salvataggio).
static func same(a: Dictionary, b: Dictionary) -> bool:
	var x := a.duplicate(true)
	var y := b.duplicate(true)
	x.erase("saved")
	y.erase("saved")
	return JSON.stringify(x,"",true) == JSON.stringify(y,"",true)

# ---- Applicazione al gioco ----

static func apply(game: Node, bundle: Dictionary) -> void:
	if int(bundle.get("schema",0)) != SCHEMA:
		return
	var p: Dictionary = bundle.get("progression",{})
	if not p.is_empty():
		game.progression.data.xp = clampi(int(p.get("xp",0)),0,2_000_000_000)
		game.progression.data.ranks = p.get("ranks",{}).duplicate(true)
		game.progression.data.claimed = p.get("claimed",{}).duplicate(true)
		game.progression.save()
	var c: Dictionary = bundle.get("campaigns",{})
	if not c.is_empty():
		game.campaigns.campaigns.clear()
		for item in c.get("items",[]):
			var clean: Dictionary = game.campaigns.sanitize(item)
			if not clean.is_empty() and game.campaigns.campaigns.size() < game.campaigns.MAX_CAMPAIGNS:
				game.campaigns.campaigns.append(clean)
		game.campaigns.deleted = c.get("deleted",[]).duplicate()
		game.campaigns.save()
	var pr: Dictionary = bundle.get("profile",{})
	if not pr.is_empty():
		game.profile.update({"name":pr.get("name","Giocatore"),"emblem":pr.get("emblem",0),"color":pr.get("color",0),"banner":pr.get("banner",1),"title":pr.get("title","novice")},false)
		if Profile.valid_id(str(pr.get("friend_id",""))):
			game.profile.data.friend_id = str(pr.friend_id)
			game.profile.data.created = int(pr.get("created",0))
		game.profile.data.updated = int(pr.get("updated",0))
		game.profile.save()
	var st: Dictionary = bundle.get("statistics",{})
	if not st.is_empty() and game.stats_store and game.stats_store.active.is_empty():
		for key in game.stats_store.data:
			if st.has(key) and typeof(st[key]) == typeof(game.stats_store.data[key]):
				game.stats_store.data[key] = st[key]
		game.stats_store.save()
	var f: Dictionary = bundle.get("friends",{})
	if not f.is_empty() and game.friends != null:
		var store: RefCounted = game.friends.store
		store.removed = f.get("removed",[]).duplicate()
		var keep: Array = []
		for item in f.get("friends",[]):
			var person: Dictionary = store.person(item)
			if not person.is_empty() and not store.removed.has(person.id):
				keep.append(person)
		store.friends = keep
		store.save()
	var s: Dictionary = bundle.get("settings",{})
	if not s.is_empty():
		game.apply_synced_settings(s)
