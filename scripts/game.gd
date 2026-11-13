extends Node
## Estado que atravessa as cenas (autoload "Game"): o grupo, o que já aconteceu e a troca de cena com fade.

const TITLE := "res://scenes/title.tscn"
const VALMOR := "res://scenes/main.tscn"
const BATTLE := "res://scenes/battle.tscn"
const FADE := 0.4

var party := {}                     # id -> {lv, hp, mp, bonus}
# Flags viram dado de save: depois do lançamento nenhuma muda de nome. Hoje: sineiro_morto, abertura_vista,
# igreja_vista, tumulo_visto, fatia_concluida, exame_antes_<herói>, exame_depois_<herói>, falou_<morador>_antes,
# falou_<morador>_depois (ValmorRules.NPCS), falou_berta_rei, tobias_visto.
var flags := {}
var return_pos := Vector2.ZERO      # onde o líder volta no mapa depois da batalha
var tries := 0                      # derrotas nesta jogada: a nova tentativa abre com a fala curta da igreja
var names := {}                     # {aldo} no texto vira o nome escolhido (hoje fixo)
var inv := {}                       # bolsa: id do item (EconomyRules.ITEMS) -> quantidade
var gold := 0                       # moedas
var opened: Array = []              # baús já abertos (EconomyRules.CHESTS)
var started := false                # há uma jogada em andamento (Nova jogada ou Continuar): só então o save guarda o jogo
var leader_pos := Callable()        # a Valmor diz onde o líder está (para o save); fora dela vale return_pos
var ui_closed_frame := -1           # quadro em que a pausa ou a loja fechou: o confirm que fechou não vale para a cena
# Opções: salvas pelo Save junto com o jogo (mescladas sobre os padrões ao carregar). "music" e "sfx": 0 a 10
# (AudioRules.LEVELS). Chaves não mudam de nome depois do lançamento.
var options := SaveRules.default_options()
var fade: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()
	_setup_font()
	var layer := CanvasLayer.new()
	layer.layer = 40                 # acima de tudo, inclusive do diálogo (22)
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)

func _setup_font() -> void:
	ThemeDB.get_default_theme().default_font = UI.body_font()
	ThemeDB.get_default_theme().default_font_size = 12

func reset() -> void:
	restore(SaveRules.new_game())
	started = false

## Põe no Game um jogo já limpo por SaveRules (jogo novo ou carregado do arquivo).
func restore(g: Dictionary) -> void:
	flags = g.flags.duplicate(true)
	party = g.party.duplicate(true)
	gold = int(g.gold)
	inv = g.inv.duplicate()
	opened = g.opened.duplicate()
	return_pos = Vector2(g.pos[0], g.pos[1]) if g.pos is Array else Vector2.ZERO
	tries = 0
	names = {}
	for id in BattleRules.HEROES:
		names[id] = BattleRules.HEROES[id].name

## O jogo como vai para o save. A posição é a do líder na Valmor; em outra cena, a de volta (porta da igreja).
func snapshot() -> Dictionary:
	var p := return_pos
	if leader_pos.is_valid():
		p = leader_pos.call()
	return {"scene": "valmor", "pos": [p.x, p.y] if p != Vector2.ZERO else null, "flags": flags.duplicate(true),
		"party": party.duplicate(true), "gold": gold, "inv": inv.duplicate(), "opened": opened.duplicate()}

## Moedas e bolsa juntas, no formato das regras da loja e dos baús (EconomyRules): {gold, inv}.
func purse() -> Dictionary:
	return {"gold": gold, "inv": inv}

func set_purse(st: Dictionary) -> void:
	gold = st.gold
	inv = st.inv

func heal_all() -> void:
	for id in party:
		var d: Dictionary = party[id]
		d.hp = BattleRules.max_stat(id, d.lv, "hp", d.bonus)
		d.mp = BattleRules.max_stat(id, d.lv, "mp", d.bonus)

## Autotestes pulam o título e a abertura (--skip-intro); --dev-battle e --walk também, para não depender do diálogo.
func skip_intro() -> bool:
	var args := OS.get_cmdline_user_args()
	return ["--skip-intro", "--dev-battle", "--walk"].any(func(a): return a in args)

func text_cps() -> int:
	return DialogueRules.SPEEDS[options.text_speed]

## Linhas de opções comuns ao título e à pausa: [rótulo, ação]. Cada ação muda a opção e chama `refresh(i)` com o
## índice da linha, para o menu se refazer com o foco no mesmo lugar.
func option_rows(refresh: Callable) -> Array:
	var speeds: Array = DialogueRules.SPEEDS.keys()
	var rows := [["Texto: " + DialogueRules.SPEED_NAMES[options.text_speed], func():
		options.text_speed = speeds[(speeds.find(options.text_speed) + 1) % speeds.size()]
		Save.write()
		refresh.call(0)]]
	for o in [["music", "Música"], ["sfx", "Efeitos"]]:
		var key: String = o[0]
		var idx := rows.size()
		rows.append(["%s: %s" % [o[1], AudioRules.level_text(options[key])], func():
			options[key] = AudioRules.level_next(options[key])
			Audio.apply_options()
			Save.write()
			refresh.call(idx)])
	return rows

## Troca de cena com um fade só: escurece, troca, clareia. `black`: já começa no preto (depois de um cartão).
func goto(path: String, black := false) -> void:
	var tw := create_tween()
	if black:
		fade.color.a = 1.0
	else:
		tw.tween_property(fade, "color:a", 1.0, FADE)
	tw.tween_callback(func(): get_tree().change_scene_to_file(path))
	tw.tween_interval(0.05)
	tw.tween_property(fade, "color:a", 0.0, FADE)
