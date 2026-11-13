extends Node
## Estado que atravessa as cenas (autoload "Game"): o grupo, o que já aconteceu e a troca de cena com fade.

const TITLE := "res://scenes/title.tscn"
const VALMOR := "res://scenes/main.tscn"
const BATTLE := "res://scenes/battle.tscn"
const FADE := 0.4

var party := {}                     # id -> {lv, hp, mp, bonus}
# Flags viram dado de save: depois do lançamento nenhuma muda de nome. Hoje: sineiro_morto, abertura_vista,
# igreja_vista, tumulo_visto, fatia_concluida, exame_antes_<herói>, exame_depois_<herói>.
var flags := {}
var return_pos := Vector2.ZERO      # onde o líder volta no mapa depois da batalha
var tries := 0                      # derrotas nesta jogada: a nova tentativa abre com a fala curta da igreja
var names := {}                     # {aldo} no texto vira o nome escolhido (hoje fixo)
var options := {"text_speed": "normal"}   # até existir a camada de save, vale só nesta sessão
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
	flags = {}
	return_pos = Vector2.ZERO
	tries = 0
	party = {}
	names = {}
	for id in BattleRules.HEROES:
		var lv := 4
		party[id] = {"lv": lv, "hp": BattleRules.stat(id, lv, "hp"), "mp": BattleRules.stat(id, lv, "mp"), "bonus": {}}
		names[id] = BattleRules.HEROES[id].name

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
