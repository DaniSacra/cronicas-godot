extends Node
## Estado que atravessa as cenas (autoload "Game"): o grupo e o que já aconteceu.

var party := {}                     # id -> {lv, hp, mp, bonus}
var flags := {}                     # "sineiro_morto", ...
var return_pos := Vector2.ZERO      # onde o líder volta no mapa depois da batalha

func _ready() -> void:
	reset()
	_setup_font()

## Fonte pixel do jogo (feita no Pixel Lab). Letras que ela não tem (acentos) caem numa fonte do sistema.
func _setup_font() -> void:
	var f := load("res://assets/ui/eterra_ui.ttf") as FontFile
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["DejaVu Sans", "Liberation Sans", "Arial"])
	f.fallbacks = [sys]
	ThemeDB.get_default_theme().default_font = f
	ThemeDB.get_default_theme().default_font_size = 12

func reset() -> void:
	flags = {}
	return_pos = Vector2.ZERO
	party = {}
	for id in BattleRules.HEROES:
		var lv := 4
		party[id] = {"lv": lv, "hp": BattleRules.stat(id, lv, "hp"), "mp": BattleRules.stat(id, lv, "mp"), "bonus": {}}

func heal_all() -> void:
	for id in party:
		party[id].hp = BattleRules.stat(id, party[id].lv, "hp", party[id].bonus.get("hp", 0))
		party[id].mp = BattleRules.stat(id, party[id].lv, "mp")
