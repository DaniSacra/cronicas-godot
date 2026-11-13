class_name DialogueRules
extends RefCounted
## Regras do diálogo em funções puras (sem nós): dados, condições, eventos, quebra de linha, ritmo da digitação,
## posição da caixa e validação dos arquivos de data/dialogue/. Especificação: docs/reviews/2026-11-13-dialogue-designer.md.

const DIR := "res://data/dialogue/"
const BOX := Vector2(544, 88)
const LINE_H := 16
const MAX_LINES := 3
const TEXT_SIZE := 12                 # tamanho nativo da Pixelify Sans: maiúscula de 9 px, linha de 16
const CARD_SIZE := 24                 # cartões em tela cheia: o dobro
const CARD_W := 480
const PORTRAIT := 64
const W_PORTRAIT := 440               # largura do texto com retrato
const W_PLAIN := 512                  # sem retrato (narração, falante sem retrato)
const OPEN_GUARD := 0.15              # o confirm que abriu a conversa não vale como avanço
const HISTORY := 20                   # falas que cancel consegue voltar
const SPEEDS := {"lenta": 30, "normal": 50, "rapida": 80, "instantanea": 0}   # caracteres por segundo (0 = tudo de uma vez)
const SPEED_NAMES := {"lenta": "Lenta", "normal": "Normal", "rapida": "Rápida", "instantanea": "Instantânea"}
const EXPRS := ["neutro", "alegre", "preocupado", "bravo", "triste", "surpreso"]
const IF_VERBS := ["flag", "party"]
const DO_VERBS := ["set", "clear", "join", "battle", "heal", "wait", "emit"]
const FORBIDDEN := ["velkor", "morvath", "irmandade", "dragã", "dragõ", "dragao", "dragoes"]   # revelação lenta
const LONG_NAME := "Maximiliano"      # nome mais longo que se aceita no lugar de {aldo}, para medir as falas

static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func load_scene(scene: String) -> Dictionary:
	var d: Variant = load_json(DIR + scene + ".json")
	return d if d is Dictionary else {"scene": scene, "lines": []}

static func speakers() -> Dictionary:
	var d: Variant = load_json(DIR + "speakers.json")
	return d if d is Dictionary else {}

## Todas as condições valem (E). `flag:x`, `!flag:x`, `party:x`, `!party:x`.
static func check(conds: Array, flags: Dictionary, party: Array) -> bool:
	for c in conds:
		var s := String(c)
		var neg := s.begins_with("!")
		var parts := s.trim_prefix("!").split(":", true, 1)
		var ok := false
		match parts[0]:
			"flag": ok = bool(flags.get(parts[1], false))
			"party": ok = parts[1] in party
		if ok == neg:
			return false
	return true

static func index_of(lines: Array, id: String) -> int:
	for i in lines.size():
		if lines[i].get("id", "") == id:
			return i
	return -1

## Índice da linha que vem depois de `i`: a seguinte na lista, ou o `next` dela; -1 encerra.
static func after(lines: Array, i: int) -> int:
	var nx: String = lines[i].get("next", "")
	if nx == "end":
		return -1
	if nx != "":
		return index_of(lines, nx)
	return i + 1 if i + 1 < lines.size() else -1

## Primeira linha a partir de `i` (inclusive) cujas condições valem; -1 se nenhuma.
static func first_valid(lines: Array, i: int, flags: Dictionary, party: Array) -> int:
	while i >= 0 and i < lines.size():
		if check(lines[i].get("if", []), flags, party):
			return i
		i += 1
	return -1

## Roda `set:` e `clear:` sobre `flags` e devolve os outros eventos, em ordem, para a cena tratar.
static func apply_events(events: Array, flags: Dictionary) -> Array:
	var rest := []
	for e in events:
		var p := String(e).split(":", true, 1)
		if p[0] == "set":
			flags[p[1]] = true
		elif p[0] == "clear":
			flags.erase(p[1])
		else:
			rest.append(String(e))
	return rest

## Texto do jogador: nomes no lugar de {id}; [em] continua para quem desenha.
static func fill(text: String, names: Dictionary) -> String:
	for id in names:
		text = text.replace("{%s}" % id, names[id])
	return text

static func plain(text: String) -> String:
	return text.replace("[em]", "").replace("[/em]", "")

static func to_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("[lb]em]", "[color=#ffe080]").replace("[lb]/em]", "[/color]")

## Quebra por palavras na largura dada, medida com a fonte de verdade. As marcações [em] não ocupam espaço.
static func wrap_lines(text: String, font: Font, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var test := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(plain(test), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			out.append(line)
			line = word
		else:
			line = test
	if line != "":
		out.append(line)
	return out

## Largura e tamanho do texto de um falante (dados de speakers.json).
static func text_width(spk: Dictionary) -> float:
	if spk.get("card", false):
		return CARD_W
	return W_PORTRAIT if spk.get("portrait", false) else W_PLAIN

static func text_size(spk: Dictionary) -> int:
	return CARD_SIZE if spk.get("card", false) else TEXT_SIZE

## Pausa extra depois do caractere `i`, em segundos na velocidade normal: fim de frase, reticências, vírgula.
## Só conta no fim da palavra (o ponto do meio de "..." não para).
static func pause_after(text: String, i: int) -> float:
	if i < 0 or i >= text.length():
		return 0.0
	if i + 1 < text.length() and not text[i + 1] in [" ", "\n"]:
		return 0.0
	var c := text[i]
	if c == "…" or (c == "." and i > 0 and text[i - 1] == "."):
		return 0.30
	if c in [".", "!", "?"]:
		return 0.25
	if c in [",", ";", ":"]:
		return 0.10
	return 0.0

## Tempo até aparecer o caractere `i`: 1/cps mais a pausa do anterior, as pausas escaladas pela velocidade.
## cps 0 = instantâneo.
static func char_time(text: String, i: int, cps: int) -> float:
	if cps <= 0:
		return 0.0
	return 1.0 / cps + pause_after(text, i - 1) * 50.0 / cps

static func accepts_confirm(since_open: float) -> bool:
	return since_open >= OPEN_GUARD

## Caixa 544x88 centrada na largura visível, embaixo ou em cima da área segura.
static func box_rect(vis_w: float, safe: Rect2, top: bool) -> Rect2:
	var y := safe.position.y if top else safe.end.y - BOX.y
	return Rect2(roundf((vis_w - BOX.x) / 2.0), y, BOX.x, BOX.y)

## Retângulo de quem fala na tela: 56x72 a partir dos pés, mais 8 px de folga.
static func speaker_rect(feet: Vector2) -> Rect2:
	return Rect2(feet - Vector2(28, 72), Vector2(56, 72)).grow(8)

## A caixa sobe se cobrir quem fala embaixo e não cobrir em cima; sem ator (narração), fica embaixo.
static func box_on_top(speaker: Rect2, bottom_box: Rect2, top_box: Rect2) -> bool:
	if speaker.size == Vector2.ZERO:
		return false
	return speaker.intersects(bottom_box) and not speaker.intersects(top_box)

## Toque com a caixa aberta: centro do botão voltar (44x44, 8 px acima da caixa, alinhado à esquerda dela; abaixo
## se a caixa estiver em cima) e do botão de menu, que desce para baixo da caixa se ela o cobrir.
static func touch_spots(box: Rect2, top: bool, menu: Vector2, r: float) -> Array:
	var y := box.end.y + 8 + r if top else box.position.y - 8 - r
	var m := menu
	if Rect2(menu - Vector2(r, r), Vector2(r, r) * 2).intersects(box):
		m = Vector2(menu.x, box.end.y + 8 + r if top else box.position.y - 8 - r)
	return [Vector2(box.position.x + r, y), m]

static func key(scene: String, id: String) -> String:
	return "dlg.%s.%s" % [scene, id]

## Erros de um arquivo de cena. `font`: fonte do corpo; `portrait_ok(id)`: o falante tem retrato.
static func validate(data: Dictionary, spk: Dictionary, font: Font, portrait_ok: Callable) -> Array:
	var errs := []
	var lines: Array = data.get("lines", [])
	var ids := {}
	for ln in lines:
		var id: String = ln.get("id", "")
		if id == "" or ids.has(id):
			errs.append("id vazio ou repetido: '%s'" % id)
		ids[id] = true
	for ln in lines:
		var id: String = ln.get("id", "")
		var nx: String = ln.get("next", "")
		if nx != "" and nx != "end" and index_of(lines, nx) == -1:
			errs.append("%s: next '%s' não existe" % [id, nx])
		if ln.has("choices"):
			errs.append("%s: escolhas ainda não existem na fatia" % id)
		for c in ln.get("if", []):
			if not String(c).trim_prefix("!").split(":")[0] in IF_VERBS:
				errs.append("%s: condição desconhecida '%s'" % [id, c])
		for e in ln.get("do", []):
			if not String(e).split(":")[0] in DO_VERBS:
				errs.append("%s: evento desconhecido '%s'" % [id, e])
		if not ln.has("text"):
			continue
		var who: String = ln.get("speaker", "")
		if not spk.has(who):
			errs.append("%s: falante '%s' não está em speakers.json" % [id, who])
			continue
		var s: Dictionary = spk[who]
		if s.get("portrait", false) and not portrait_ok.call(who):
			errs.append("%s: falante '%s' sem retrato" % [id, who])
		if ln.has("expr") and not ln.expr in EXPRS:
			errs.append("%s: expressão desconhecida '%s'" % [id, ln.expr])
		var text: String = ln.text
		errs.append_array(text_errors(id, text + " " + String(s.get("name", "")), font))
		var shown := fill(text, {"aldo": LONG_NAME})
		var n := wrap_lines(shown, font, text_size(s), text_width(s)).size()
		if n > MAX_LINES:
			errs.append("%s: %d linhas (máximo %d)" % [id, n, MAX_LINES])
	return errs

## Travessão, nomes proibidos e letras que a fonte não tem.
static func text_errors(id: String, text: String, font: Font) -> Array:
	var errs := []
	var low := text.to_lower()
	for w in FORBIDDEN:
		if low.contains(w):
			errs.append("%s: nome proibido '%s'" % [id, w])
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 0x2014 or c == 0x2013:
			errs.append("%s: travessão" % id)
		elif c > 32 and not font.has_char(c):
			errs.append("%s: a fonte não tem '%s'" % [id, text[i]])
	return errs
