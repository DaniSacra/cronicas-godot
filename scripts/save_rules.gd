class_name SaveRules
extends RefCounted
## Formato do save em funções puras (sem arquivo, sem nós): montar, ler, migrar e limpar. O autoload Save só grava.
##
## REGRAS QUE NÃO MUDAM DEPOIS DO LANÇAMENTO (save antigo não pode quebrar):
## - IDs de item (EconomyRules.ITEMS: "pocao", "eter", "pena") e de baú (EconomyRules.CHESTS: "valmor:poco",
##   "valmor:quintal") nunca mudam de nome. Item que sair do jogo continua lido (fica na bolsa sem aparecer).
## - Nomes de flag (Game.flags) e chaves de opção ("text_speed", "music", "sfx") nunca mudam.
## - Campo nunca é removido. Mudou o formato: VERSION sobe e entra um passo em `migrate` (v1 -> v2), sem apagar o antigo.
## - Campo que faltar ou vier estragado volta ao padrão; arquivo que não abre vira "sem save" (o jogo não trava).
##
## Arquivo (JSON): {"version", "saved_at", "options": {...}, "game": {...}}. "game" só existe depois de "Nova jogada":
## sem ele o título não mostra "Continuar" (as opções podem ser salvas antes de começar).
## game: {"scene", "pos": [x, y] ou null, "flags", "party": {id: {lv, hp, mp, bonus}}, "gold", "inv": {id: n},
## "opened": [ids de baú]}.
##
## Versões: v0 = rascunho de antes da economia (sem "version": party, flags, return_pos e text_speed soltos no topo).
## v1 = este formato.

const R := preload("res://scripts/battle_rules.gd")
const E := preload("res://scripts/economy_rules.gd")
const D := preload("res://scripts/dialogue_rules.gd")
const A := preload("res://scripts/audio_rules.gd")

const VERSION := 1
const START_LV := 4
const LV_MAX := 99
const SCENES := ["valmor"]            # onde o jogo pode continuar (hoje só a Valmor)

static func default_options() -> Dictionary:
	return {"text_speed": "normal", "music": A.DEFAULT_LEVEL, "sfx": A.DEFAULT_LEVEL}

## Jogo novo: grupo no nível 4 com PV e PM cheios, 60 moedas e a bolsa inicial.
static func new_game() -> Dictionary:
	var party := {}
	for id in R.HEROES:
		party[id] = {"lv": START_LV, "hp": R.max_stat(id, START_LV, "hp", {}), "mp": R.max_stat(id, START_LV, "mp", {}), "bonus": {}}
	return {"scene": "valmor", "pos": null, "flags": {}, "party": party, "gold": E.START_GOLD, "inv": E.start_bag(), "opened": []}

## O texto que vai para o arquivo.
static func pack(game: Variant, options: Dictionary, saved_at := 0) -> String:
	var d := {"version": VERSION, "saved_at": saved_at, "options": options}
	if game is Dictionary:
		d["game"] = game
	return JSON.stringify(d, "\t")

## Lê o texto do arquivo: migra e limpa. Devolve {} quando não dá para ler (vazio, JSON quebrado, não é objeto).
static func parse(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var json := JSON.new()                # parse_string imprimiria erro no log a cada arquivo estragado
	if json.parse(text) != OK:
		return {}
	var raw: Variant = json.data
	if not raw is Dictionary:
		return {}
	var d := migrate(raw)
	var out := {"version": VERSION, "saved_at": int(_num(d.get("saved_at"), 0)), "options": clean_options(d.get("options"))}
	if d.get("game") is Dictionary:
		out["game"] = clean_game(d.game)
	return out

## Leva qualquer versão antiga até VERSION, um passo de cada vez. Versão maior que a nossa (save de um jogo mais novo)
## fica como está: os campos conhecidos são lidos e os outros ignorados.
static func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	if version_of(d) < 1:
		d = _v0_to_v1(d)
	return d

## A versão do arquivo. Número (ou texto de número) vale como está. Sem versão legível, decide a forma: com "game"
## ou "options" é o formato v1 (version estragada não joga o jogo fora), senão é o rascunho v0.
static func version_of(d: Dictionary) -> int:
	var v: Variant = d.get("version")
	if _is_num(v) and is_finite(float(v)):
		return int(v)
	if v is String and String(v).strip_edges().is_valid_int():
		return int(String(v))
	return 1 if d.get("game") is Dictionary or d.get("options") is Dictionary else 0

## v0: {party, flags, return_pos: [x, y], text_speed} no topo, sem economia. Vira um jogo com 60 moedas e a bolsa inicial.
static func _v0_to_v1(d: Dictionary) -> Dictionary:
	var game := {"scene": "valmor", "pos": d.get("return_pos"), "flags": d.get("flags", {}), "party": d.get("party", {}),
		"gold": E.START_GOLD, "inv": E.start_bag(), "opened": []}
	var opts := {}
	if d.has("text_speed"):
		opts["text_speed"] = d.text_speed
	var out := {"version": 1, "saved_at": 0, "options": opts}
	if d.has("party") or d.has("flags"):
		out["game"] = game
	return out

## Opções sobre os padrões: chave que falta ou valor fora da lista fica no padrão.
static func clean_options(o: Variant) -> Dictionary:
	var out := default_options()
	if not o is Dictionary:
		return out
	if String(o.get("text_speed", "")) in D.SPEEDS:
		out.text_speed = String(o.text_speed)
	for k in ["music", "sfx"]:
		var lv := int(_num(o.get(k), -1))
		if lv in A.LEVELS:
			out[k] = lv
	return out

## Jogo sobre o jogo novo: cada campo é conferido (tipo e faixa); o que vier estragado fica no padrão.
static func clean_game(g: Dictionary) -> Dictionary:
	var out := new_game()
	if String(g.get("scene", "")) in SCENES:
		out.scene = String(g.scene)
	var p: Variant = g.get("pos")
	if p is Array and p.size() == 2 and _is_num(p[0]) and _is_num(p[1]):
		out.pos = [float(p[0]), float(p[1])]
	if g.get("flags") is Dictionary:
		for k in g.flags:
			if g.flags[k] is bool:
				out.flags[String(k)] = g.flags[k]
	if g.get("party") is Dictionary:
		for id in out.party:
			var h: Variant = g.party.get(id)
			if not h is Dictionary:
				continue
			var lv := clampi(int(_num(h.get("lv"), START_LV)), 1, LV_MAX)
			var bonus := {}
			if h.get("bonus") is Dictionary:
				for k in h.bonus:
					if _is_num(h.bonus[k]):
						bonus[String(k)] = int(h.bonus[k])
			var hpmax := R.max_stat(id, lv, "hp", bonus)
			var mpmax := R.max_stat(id, lv, "mp", bonus)
			out.party[id] = {"lv": lv, "hp": clampi(int(_num(h.get("hp"), hpmax)), 1, hpmax),
				"mp": clampi(int(_num(h.get("mp"), mpmax)), 0, mpmax), "bonus": bonus}
	out.gold = clampi(int(_num(g.get("gold"), E.START_GOLD)), 0, E.GOLD_MAX)
	if g.get("inv") is Dictionary:
		out.inv = {}
		for k in g.inv:
			var n := clampi(int(_num(g.inv[k], 0)), 0, E.STACK_MAX)
			if n > 0:
				out.inv[String(k)] = n
	if g.get("opened") is Array:
		for c in g.opened:
			if c is String and not c in out.opened:
				out.opened.append(c)
	return out

static func _is_num(x: Variant) -> bool:
	return x is int or x is float

static func _num(x: Variant, fallback: float) -> float:
	return float(x) if _is_num(x) else fallback
