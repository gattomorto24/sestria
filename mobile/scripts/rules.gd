extends RefCounted

const AXE = 0
const ARROW = 1
const HELMET = 2
const SHIELD = 3
const HAND = 4
const TYPES = [AXE, AXE, ARROW, HELMET, SHIELD, HAND]
const NAMES = ["Ascia", "Freccia", "Elmo", "Scudo", "Mano"]
const PAIRS = [[2,3], [2,4], [2,5], [3,4], [3,5], [4,5]]
const FAVOR = {
	"disruption": ["Interferenza", 1, [3,6,9], [1,2,3], "Riduce la tattica rivale di %s livelli."],
	"bond": ["Legame vitale", 1, [10,14,18], [1,2,3], "Cura %s per gettone speso dal rivale."],
	"reroll": ["Seconda occasione", 2, [2,3,4], [2,3,4], "Rilancia fino a %s dadi scelti."],
	"reinforcements": ["Rinforzi", 2, [2,4,6], [1,2,3], "Lancia %s dadi aggiuntivi."],
	"sabotage": ["Sabotaggio", 2, [3,6,9], [1,2,3], "Esclude %s dadi rivali."],
	"attrition": ["Logoramento", 3, [4,6,8], [2,3,4], "Distrugge %s gettoni rivali per freccia."],
	"exchange": ["Scambio deciso", 3, [4,6,8], [2,3,4], "Distrugge %s gettoni rivali per pietra sacrificata."],
	"fortify": ["Fortificazione", 4, [3,6,9], [1,2,3], "Aggiunge %s difese per dado elmo o scudo."],
	"harvest": ["Raccolta", 4, [4,8,12], [2,3,4], "Guadagna %s gettoni per dado mano."],
	"assault": ["Assalto", 4, [6,10,18], [1.5,2,3], "Moltiplica le asce per %s e arrotonda per eccesso."],
	"resonance": ["Risonanza", 4, [4,6,8], [2,3,4], "Aggiunge %s al simbolo più frequente."],
	"recovery": ["Recupero", 4, [4,7,10], [1,2,3], "Cura %s per attacco bloccato."],
	"siphon": ["Sottrazione", 4, [6,12,18], [1,2,3], "Cura %s per danno d’ascia inferto."],
	"resolve": ["Tenacia", 4, [3,5,7], [1,2,3], "Guadagna %s gettoni per danno ricevuto."],
	"volley": ["Raffica", 4, [6,10,14], [1,2,3], "Aggiunge %s frecce per dado freccia."],
	"pierce": ["Precisione", 4, [2,3,4], [2,3,6], "%s frecce ignorano gli scudi."],
	"breach": ["Breccia", 4, [2,4,6], [2,4,6], "Rimuove %s elmi rivali."],
	"impact": ["Impatto", 6, [4,8,12], [2,5,8], "Infligge %s danni dopo i dadi."],
	"renew": ["Rinnovamento", 7, [4,7,10], [2,4,6], "Cura %s dopo i dadi."],
	"reserve": ["Riserva", 7, [6,8,10], [3,4,5], "Guadagna %s gettoni per pietra sacrificata, dopo i dadi."]
}

var rng := RandomNumberGenerator.new()
var hp := [15,15]
var gold := [0,0]
var board: Array = [[],[]]
var first := 0
var round_no := 1
var winner := -1
var events: Array = []
var plans: Array
var buffs: Array
var bonus: Array
var banned: Array
var spent: Array

static func die(id: int, face: int) -> Dictionary:
	return {"id":id, "face":face, "kind":TYPES[face], "gold":face in PAIRS[id % 6]}

func reset(initiative: int) -> void:
	hp = [15,15]
	gold = [0,0]
	board = [[],[]]
	first = initiative
	round_no = 1
	winner = -1

func next_round() -> void:
	first = 1 - first
	round_no += 1
	board = [[],[]]

func count(side: int, kind: int) -> int:
	var total := 0
	for d in board[side]:
		if d.kind == kind:
			total += 1
	return total

func marks(side: int) -> int:
	var total := 0
	for d in board[side]:
		if d.gold:
			total += 1
	return total

func record(kind: String, side: int, amount: int, detail: String, extra := {}) -> void:
	events.append({"kind":kind,"side":side,"amount":amount,"text":detail,
		"hp":hp.duplicate(),"gold":gold.duplicate(),"extra":extra})

func resolve(intents: Array) -> Array:
	events = []
	plans = intents.duplicate(true)
	buffs = [{},{}]
	bonus = [[0,0,0,0,0],[0,0,0,0,0]]
	banned = [[],[]]
	spent = [0,0]
	for priority in range(1, 8):
		if priority == 5:
			resolve_dice()
		else:
			for side in [first, 1-first]:
				var p: Dictionary = plans[side]
				if not p.is_empty() and p.level >= 0 and FAVOR[p.id][1] == priority:
					invoke(side, p)
				if winner >= 0:
					break
		if winner >= 0:
			break
	return events

func heal(side: int, amount: int) -> void:
	var before: int = hp[side]
	hp[side] = mini(15, before + amount)
	if hp[side] > before:
		record("heal", side, hp[side] - before, "Pietre recuperate")

func damage(side: int, amount: int, detail: String, extra := {}) -> void:
	if amount <= 0:
		return
	var lost := mini(hp[side], amount)
	hp[side] -= lost
	record("hit", side, lost, detail, extra)
	if hp[side] == 0:
		winner = 1 - side

func count_effect(side: int, kind: int) -> int:
	return maxi(0, count(side, kind) + bonus[side][kind])

func invoke(side: int, p: Dictionary) -> void:
	var other := 1-side
	var info: Array = FAVOR[p.id]
	var cost: int = info[2][p.level]
	var value: Variant = info[3][p.level]
	if gold[side] < cost:
		record("fail", side, 0, "%s · offerta insufficiente" % info[0])
		return
	gold[side] -= cost
	spent[side] += cost
	record("favor", side, cost, info[0], {"id":p.id})
	if buffs[other].has("bond"):
		heal(other, cost * buffs[other].bond)
	match p.id:
		"disruption":
			if not plans[other].is_empty():
				plans[other].level -= value
		"bond":
			buffs[side].bond = value
			heal(side, spent[other] * value)
		"reroll":
			var targets: Array = p.get("targets", [])
			for pair in targets.slice(0, value):
				var target_side: int = pair[0]
				var id: int = pair[1]
				for index in board[target_side].size():
					if board[target_side][index].id == id:
						var fresh := die(id, rng.randi_range(0,5))
						board[target_side][index] = fresh
						record("reroll", target_side, 0, "Seconda occasione", fresh)
						break
		"reinforcements":
			for i in int(value):
				var fresh := die(6 + i, rng.randi_range(0,5))
				board[side].append(fresh)
				record("extra", side, 0, "Dado di Rinforzi", fresh)
		"sabotage":
			var candidates: Array = board[other].duplicate()
			for _i in mini(value, candidates.size()):
				var d: Dictionary = candidates.pop_at(rng.randi_range(0, candidates.size()-1))
				board[other].erase(d)
				banned[other].append(d.id)
				record("ban", other, 0, "Dado escluso", d)
		"attrition":
			gold[other] = maxi(0, gold[other] - count(side, ARROW)*value)
			record("token", other, 0, "Gettoni distrutti")
		"exchange", "reserve":
			var n := clampi(p.get("sacrifice", 0), 0, hp[side]-1)
			damage(side, n, "Pietre sacrificate")
			if p.id == "exchange":
				gold[other] = maxi(0, gold[other] - n*value)
				record("token", other, 0, "Gettoni distrutti")
			else:
				gold[side] += n*value
				record("token", side, n*value, "Gettoni ottenuti")
		"fortify":
			for kind in [HELMET, SHIELD]:
				bonus[side][kind] += count(side, kind)*value
		"harvest":
			gold[side] += count(side, HAND)*value
			record("token", side, count(side, HAND)*value, "Gettoni della Raccolta")
		"assault":
			var axes := count_effect(side, AXE)
			bonus[side][AXE] += ceili(axes * float(value)) - axes
		"resonance":
			var kind := 0
			for j in range(1,5):
				if count_effect(side, j) > count_effect(side, kind):
					kind = j
			if count_effect(side, kind) > 0:
				bonus[side][kind] += value
		"recovery", "siphon", "resolve", "pierce":
			buffs[side][p.id] = value
		"volley":
			bonus[side][ARROW] += count(side, ARROW)*value
		"breach":
			bonus[other][HELMET] -= value
		"impact":
			damage(other, value, "Impatto")
		"renew":
			heal(side, value)

func resolve_dice() -> void:
	for side in [first, 1-first]:
		var earned := marks(side)
		gold[side] += earned
		if earned:
			record("token", side, earned, "Facce dorate")
	for side in [first, 1-first]:
		var other: int = 1-side
		var axe := count_effect(side, AXE)
		var arrow := count_effect(side, ARROW)
		var piercing := mini(arrow, buffs[side].get("pierce",0))
		var melee_block := mini(axe, count_effect(other, HELMET))
		var ranged_block := mini(arrow-piercing, count_effect(other, SHIELD))
		if melee_block + ranged_block > 0:
			record("block", other, melee_block+ranged_block, "Attacchi bloccati",
				{"attacker":side, "asce":melee_block, "frecce":ranged_block, "ignora":piercing})
			heal(other, (melee_block+ranged_block) * buffs[other].get("recovery",0))
		var direct := maxi(0, axe-melee_block)
		damage(other, direct, "Danni d’ascia", {"attacker":side,"symbol":AXE,"blocked":melee_block})
		if winner >= 0:
			return
		heal(side, direct * buffs[side].get("siphon",0))
		damage(other, arrow-ranged_block, "Danni di freccia",
			{"attacker":side,"symbol":ARROW,"blocked":ranged_block,"ignora":piercing})
		if winner >= 0:
			return
		var reward: int = (direct + arrow-ranged_block) * buffs[other].get("resolve",0)
		gold[other] += reward
		if reward:
			record("token", other, reward, "Gettoni di Tenacia")
	# Le mani agiscono per ultime, dopo bordi dorati, mimir e combattimento:
	# possono quindi rubare anche i gettoni appena guadagnati. Le mani
	# contrapposte si annullano a coppie, solo l'eccedenza ruba.
	var hands := [count_effect(0,HAND), count_effect(1,HAND)]
	var clash := mini(hands[0], hands[1])
	if clash > 0:
		record("clash", first, clash, "Mani che si annullano", {"hand":true})
	var thief := 0 if hands[0] > hands[1] else 1
	var steal := mini(hands[thief] - clash, gold[1-thief])
	if steal > 0:
		gold[thief] += steal
		gold[1-thief] -= steal
		record("token", thief, steal, "Gettoni sottratti", {"hand":true})
