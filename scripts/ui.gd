class_name UI
extends RefCounted
## Peças de interface comuns a todas as cenas: margem segura, rótulo com contorno, painel, tema do menu e ícones
## desenhados em código (pixel a pixel, sem arte gerada).

const SAFE := 16                     # margem de cada borda da tela (640x360 lógicos), somada ao recorte do aparelho
const ROW_KEYS := 28                 # altura mínima de linha de menu no teclado e no controle
const ROW_TOUCH := 44                # alvo de toque
const PANEL_BG := Color(0.04, 0.05, 0.12, 0.86)
const PANEL_BORDER := Color(0.55, 0.65, 0.95, 0.8)
const FOCUS_BG := Color("#2a5a9a")
const TEXT_TOUCH := 24               # menus no toque: o dobro do tamanho nativo
# Números (PV, dano, custos) na Press Start 2P (OFL): na Pixelify Sans o "5" e o "9" parecem "S".
# Tamanho nativo 8 (maiúscula de 7 px, como a Pixelify em 12) e o dobro, 16.
const NUM_FONT := "res://assets/ui/PressStart2P.ttf"

## Área útil da tela: o retângulo visível menos SAFE e menos o recorte do aparelho (câmera, cantos), já em pixels lógicos.
static func safe_area(vis: Vector2, device_tl := Vector2.ZERO, device_br := Vector2.ZERO) -> Rect2:
	var tl := Vector2(SAFE, SAFE) + device_tl
	var br := Vector2(SAFE, SAFE) + device_br
	return Rect2(tl, vis - tl - br)

## A área útil do viewport atual (no celular soma o recorte da tela informado pelo sistema).
static func safe_rect(vp: Viewport) -> Rect2:
	var vis := vp.get_visible_rect().size
	if not OS.has_feature("mobile"):
		return safe_area(vis)
	var win := Vector2(DisplayServer.window_get_size())
	var sa := DisplayServer.get_display_safe_area()
	var k := vis / win
	return safe_area(vis, Vector2(sa.position) * k, (win - Vector2(sa.end)) * k)

## Posição de um painel de tamanho `size` dentro de `area`, o mais perto possível de `want`.
static func clamp_in(want: Vector2, size: Vector2, area: Rect2) -> Vector2:
	return Vector2(clampf(want.x, area.position.x, maxf(area.position.x, area.end.x - size.x)),
		clampf(want.y, area.position.y, maxf(area.position.y, area.end.y - size.y)))

## Rótulo com contorno escuro, no tamanho nativo da fonte (12) ou no dobro (24).
static func label(text := "", size := 12, color := Color.WHITE, outline := 2) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.01, 0.01, 0.04, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	return l

## Fonte pixel do corpo do texto (Pixelify Sans, OFL), com todos os acentos do português.
## A Eterra UI (assets/ui/eterra_ui.ttf, Pixel Lab) não tem acentos e fica fora do corpo.
const BODY_FONT := "res://assets/ui/PixelifySans.ttf"

static var _body: FontVariation
static var _num: FontFile

## A fonte do corpo como o jogo usa (sem suavização; em 12 px o espaço some, o espaçamento extra o devolve).
## Os testes medem as falas com esta mesma fonte.
static func body_font() -> FontVariation:
	if _body == null:
		var f := load(BODY_FONT) as FontFile
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_body = FontVariation.new()
		_body.base_font = f
		_body.spacing_space = 3
	return _body

static func num_font() -> FontFile:
	if _num == null:
		_num = load(NUM_FONT) as FontFile
		_num.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_num.hinting = TextServer.HINTING_NONE
		_num.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _num

## Rótulo de números: Press Start 2P em 8 (nativo) ou 16.
static func num_label(text := "", size := 8, color := Color.WHITE, outline := 2) -> Label:
	var l := label(text, size, color, outline)
	l.add_theme_font_override("font", num_font())
	return l

## Estilo de painel único: fundo azul escuro, borda de 1 px, cantos de 2 px.
static func panel_style(border := PANEL_BORDER, bw := 1, bg := PANEL_BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(2)
	return s

static var _theme: Theme

## Tema dos menus: texto à esquerda, linha marcada em azul, espaço para o cursor, opção apagada em 35%.
static func menu_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 14
	empty.content_margin_right = 6
	var focus := panel_style(Color(0.7, 0.85, 1.0, 0.9), 1, FOCUS_BG)
	focus.content_margin_left = 14
	focus.content_margin_right = 6
	for st in ["normal", "disabled", "pressed"]:
		_theme.set_stylebox(st, "Button", empty)
	for st in ["hover", "focus", "hover_pressed"]:
		_theme.set_stylebox(st, "Button", focus)
	_theme.set_constant("outline_size", "Button", 2)
	_theme.set_color("font_outline_color", "Button", Color(0.01, 0.01, 0.04, 0.95))
	_theme.set_color("font_color", "Button", Color(0.92, 0.94, 1.0))
	_theme.set_color("font_focus_color", "Button", Color.WHITE)
	_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	_theme.set_stylebox("panel", "PanelContainer", panel_style())
	return _theme

## Botão de menu com o tema acima; o mouse em cima também marca a linha (um foco só).
## `touch`: passe Controls.is_touch (aqui não se lê o autoload, para o script rodar nos testes).
## `value`: número à direita da linha (custo, pontos), na fonte de números. No toque a letra dobra.
static func menu_button(text: String, cb: Callable, disabled := false, touch := false, value := "") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, ROW_TOUCH if touch else ROW_KEYS)
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_ALL
	if touch:
		b.add_theme_font_size_override("font_size", TEXT_TOUCH)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	if value != "":
		# medidas pelas próprias fontes: fora da árvore o Label ainda não enxerga a fonte sobreposta
		var nsize := 16 if touch else 8
		var nw := num_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x
		var font: Font = ThemeDB.get_default_theme().default_font
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_TOUCH if touch else 12).x if font else 0.0
		var n := num_label(value, nsize)
		n.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		n.offset_left = -nw - 8
		n.offset_right = -6
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if disabled:
			n.modulate.a = 0.35
		b.add_child(n)
		b.custom_minimum_size.x = 14 + tw + 12 + nw + 8
	return b

## Centros dos botões A e B do toque numa tela visível `s`: zonas de toque (1,5x o raio de 22) sem parte em comum.
static func ab_spots(s: Vector2) -> Array:
	return [Vector2(s.x - 48, s.y - 80), Vector2(s.x - 106, s.y - 42)]

## Dois toques nos submenus: o primeiro marca a linha (e mostra a descrição), o segundo na mesma linha confirma.
## Fora do toque, confirma de primeira. `armed`: a linha marcada antes; `key`: a linha tocada agora.
static func tap_confirms(armed: String, key: String, touch: bool) -> bool:
	return not touch or armed == key

## Itens do menu de pausa: "Sair" some na web e no celular; "Tela cheia" some no celular (já é tela cheia).
static func pause_items(web: bool, mobile: bool) -> Array:
	var items := ["Continuar"]
	if not mobile:
		items.append("Tela cheia")
	if not web and not mobile:
		items.append("Sair")
	return items

# ---------- ícones em pixel, desenhados aqui ----------
# o = contorno, x = cor, h = brilho, . = transparente. Cada desenho tem 16x16.
const ICONS := {
	"hit": [   # punho
		"................",
		"................",
		"....oooooooo....",
		"...oxxoxxoxxo...",
		"...ohxohxohxoo..",
		"...oxxoxxoxxoxo.",
		"..ooxxoxxoxxoxo.",
		".ohxoooooooooxo.",
		".ohxxxxxxxxxxxo.",
		".oxxxxxxxxxxxo..",
		"..oxxxxxxxxxxo..",
		"...oxxxxxxxxo...",
		"....oxxxxxxo....",
		"....oxxxxxxo....",
		"....oooooooo....",
		"................"],
	"drain": [   # gota
		"................",
		".......oo.......",
		"......oxxo......",
		"......oxxo......",
		".....oxhxxo.....",
		".....oxhxxo.....",
		"....oxhxxxxo....",
		"....oxhxxxxo....",
		"...oxhhxxxxxo...",
		"...oxhxxxxxxo...",
		"...oxxxxxxxxo...",
		"...oxxxxxxxxo...",
		"....oxxxxxxo....",
		".....oxxxxo.....",
		"......oooo......",
		"................"],
	"bell": [   # sino
		"................",
		".......oo.......",
		"......oxxo......",
		".....oxhxxo.....",
		"....oxhxxxxo....",
		"....oxhxxxxo....",
		"....oxhxxxxo....",
		"...oxhxxxxxxo...",
		"...oxhxxxxxxo...",
		"..oxhxxxxxxxxo..",
		"..oxxxxxxxxxxo..",
		".oxxxxxxxxxxxxo.",
		".oooooooooooooo.",
		"......oxxo......",
		"......oooo......",
		"................"],
	"cursor": [   # seta do menu (8x8 no canto de cima)
		"oo..............",
		"oxo.............",
		"oxxo............",
		"oxhxo...........",
		"oxxo............",
		"oxo.............",
		"oo..............",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................"],
	"more": [   # seta de "continua" do diálogo (8x6 no canto de cima)
		"oooooooo........",
		"oxxxxxxo........",
		".oxhhxo.........",
		"..oxxo..........",
		"...oo...........",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................"],
	"back": [   # seta de voltar (botão Voltar do toque)
		"................",
		"................",
		"................",
		"......o.........",
		".....oxo........",
		"....oxxo........",
		"...oxxxoooooooo.",
		"..oxhhhhhhhhhho.",
		"..oxxxxxxxxxxxo.",
		"...oxxxoooooooo.",
		"....oxxo........",
		".....oxo........",
		"......o.........",
		"................",
		"................",
		"................"],
	"menu": [   # três traços (botão de menu do toque)
		"................",
		"................",
		"................",
		".oooooooooooooo.",
		".oxxxxxxxxxxxxo.",
		".oooooooooooooo.",
		"................",
		".oooooooooooooo.",
		".oxxxxxxxxxxxxo.",
		".oooooooooooooo.",
		"................",
		".oooooooooooooo.",
		".oxxxxxxxxxxxxo.",
		".oooooooooooooo.",
		"................",
		"................"],
}
const ICON_COLOR := {"hit": Color("#e86a5a"), "drain": Color("#b07ae8"), "bell": Color("#f0c850"), "cursor": Color.WHITE,
	"more": Color.WHITE, "back": Color.WHITE, "menu": Color.WHITE}

static var _icons := {}

static func icon(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var rows: Array = ICONS[kind]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var base: Color = ICON_COLOR[kind]
	var pal := {"o": Color(0.04, 0.03, 0.08), "x": base, "h": base.lerp(Color.WHITE, 0.55)}
	for y in 16:
		for x in 16:
			var ch: String = rows[y][x]
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	_icons[kind] = ImageTexture.create_from_image(img)
	return _icons[kind]
