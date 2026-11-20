extends SceneTree

const Rules = preload("res://scripts/rules.gd")
const Die = preload("res://scripts/die.gd")
const AI = preload("res://scripts/ai.gd")
var failures := 0
var assertions := 0

func check(b: bool, reason: String) -> void:
	assertions += 1
	if not b:
		failures += 1
		push_error(reason)

func _initialize() -> void:
	var pairs := {}
	for id in 6:
		var counts := [0,0,0,0,0]
		var marks := []
		for face in 6:
			var d := Rules.die(id,face)
			counts[d.kind] += 1
			if d.gold:
				marks.append(face)
			var basis := Basis(Quaternion(Die.NORMALS[face],Vector3.UP))
			check(Die.top_face(basis)==face,"La faccia deve corrispondere alla normale")
		check(counts == [2,1,1,1,1],"Ogni dado ha due asce e quattro simboli singoli")
		check(marks.size()==2 and not 0 in marks and not 1 in marks,"Due bordi oro e nessuno sulle asce")
		pairs[str(marks)] = true
	check(pairs.size()==6,"Sei combinazioni distinte")
	var r = Rules.new()
	r.reset(0)
	var tagged_hand := Rules.die(2,5)
	var tagged_arrow := Rules.die(0,2)
	var plain_axe := Rules.die(0,0)
	r.board = [[tagged_hand,plain_axe],[tagged_arrow,Rules.die(1,3)]]
	r.resolve([{},{}])
	check(r.hp == [14,15],"Elmo blocca ascia e freccia passa")
	check(r.gold == [2,0],"Il bordo si accredita prima del furto")
	r.reset(0)
	r.hp = [15,1]
	r.board = [[plain_axe,tagged_arrow,Rules.die(3,2)],
		[Rules.die(0,3),Rules.die(1,4)]]
	r.resolve([{},{}])
	var parries: Array = r.events.filter(func(e):return e.kind=="block")
	var strikes: Array = r.events.filter(func(e):return e.kind=="hit")
	check(parries.size()==1 and parries[0].extra.asce==1 and parries[0].extra.frecce==1,
		"Le parate distinguono asce ed elmi da frecce e scudi")
	check(strikes.size()==1 and strikes[0].extra.symbol==Rules.ARROW and strikes[0].amount==1,
		"Un colpo indica origine e pietre effettivamente perse")
	r.reset(0)
	r.hp = [15,1]
	r.board = [[plain_axe,Rules.die(1,1)],[]]
	r.resolve([{},{}])
	check(r.events[-1].amount==1 and r.events[-1].hp[1]==0,"Il colpo letale indica una sola pietra rimossa")
	r.reset(0)
	r.gold = [0,1]
	r.board = [[Rules.die(0,5),Rules.die(1,5)],[Rules.die(0,5)]]
	r.resolve([{},{}])
	check(r.gold == [1,0],"Le mani si annullano e ruba solo l’eccedenza")
	check(r.events.any(func(e):return e.kind=="clash" and e.amount==1),"Evento di mani annullate")
	r.reset(0)
	r.gold = [0,0]
	r.board = [[tagged_hand],[tagged_hand]]
	r.resolve([{},{}])
	check(r.gold == [1,1] and not r.events.any(func(e):return e.kind=="token" and e.extra.has("hand")),
		"Mani pari: nessun furto")
	r.reset(0)
	r.gold = [3,0]
	r.board = [[tagged_hand],[tagged_arrow]]
	r.resolve([{"id":"impact","level":0},{}])
	check(r.gold[0] == 1 and r.hp[1] == 13,"Impatto può spendere i gettoni ottenuti in manche")
	r.reset(0)
	r.gold = [4,0]
	r.board = [[plain_axe],[tagged_hand]]
	r.resolve([{"id":"impact","level":0},{}])
	check(r.hp[1]==14 and r.events[-1].kind=="fail","Furto prima di Impatto")
	r.reset(0)
	r.gold = [0,6]
	r.board = [[tagged_arrow,tagged_hand],[]]
	r.resolve([{"id":"attrition","level":0},{}])
	check(r.events[0].kind=="fail","L’offerta anticipata precede i bordi")
	r.reset(1)
	r.hp = [1,1]
	r.board = [[plain_axe],[plain_axe]]
	r.resolve([{},{}])
	check(r.winner==1,"L’iniziativa risolve prima l’attacco letale")
	r.next_round()
	check(r.first==0 and r.board==[[],[]],"La manche inverte l’iniziativa")
	r.reset(0)
	r.gold = [6,12]
	r.resolve([{"id":"disruption","level":1},{"id":"impact","level":2}])
	check(r.hp[0]==13 and r.gold[1]==8,"Thrymr riduce livello, effetto e costo effettivo")
	r.reset(0)
	r.hp = [4,9]
	r.gold = [12,8]
	r.board = [[plain_axe],[tagged_hand]]
	r.resolve([{"id":"bond","level":0},{"id":"impact","level":1}])
	check(r.hp[0]==7,"Var cura al pagamento prima del colpo")
	r.reset(0)
	r.gold = [6,0]
	r.board = [[tagged_arrow],[]]
	r.resolve([{"id":"reinforcements","level":2},{}])
	check(r.board[0].size()==4,"Rinforzi aggiunge tre dadi")
	r.reset(0)
	r.gold = [2,0]
	r.board = [[plain_axe],[tagged_arrow,tagged_hand]]
	r.resolve([{"id":"reroll","level":0,"targets":[[0,0],[1,0]]},{}])
	check(r.events.filter(func(e):return e.kind=="reroll").size()==2,"Seconda occasione consente dadi propri e rivali")
	for id in Rules.FAVOR:
		for level in 3:
			r.reset(0)
			r.rng.seed = 4
			r.hp = [10,10]
			r.gold = [25,20]
			r.board = [[plain_axe,tagged_arrow,tagged_hand],[plain_axe,tagged_arrow,tagged_hand]]
			r.resolve([{"id":id,"level":level,"sacrifice":2,"targets":[[1,0]]},{}])
			check(r.events.any(func(e):return e.kind=="favor" and e.extra.id==id),
				"Attivazione eseguibile " + id)
			check(r.hp.all(func(value):return value>=0 and value<=15) and r.gold.all(func(value):return value>=0),
				"Risorse valide " + id)
	var ai = AI.new()
	for level in 3:
		ai.level = level
		r.reset(1)
		r.gold = [3,9]
		var landed := [plain_axe,tagged_arrow,tagged_hand]
		ai.rng.seed = 700+level
		var ids := ai.keep(r,1,landed,false)
		check(ids.all(func(id):return landed.any(func(d):return d.id == id)),"AI seleziona soltanto dadi visibili")
		check(ai.keep(r,1,landed,true).size()==landed.size(),"L’ultimo lancio è obbligatorio anche per l’AI")
		var plan := ai.favor(r,1,["impact","breach","renew"])
		check(plan.is_empty() or plan.id in ["impact","breach","renew"],"L’AI usa solo favori equipaggiati")
	print("REGOLE | %d controlli | %d errori" % [assertions,failures])
	quit(1 if failures else 0)
