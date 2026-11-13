extends CanvasLayer
## Caixa de diálogo (autoload "Dialogue"), camada 22: acima da vinheta e do toque, abaixo do fade do Game.
## `await Dialogue.play("cena")` mostra as falas de data/dialogue/cena.json e devolve os eventos que a cena trata
## (por exemplo "battle:sineiro"). Regras puras em DialogueRules. Não pausa a árvore: quem chama checa is_open().
## Entrada só por Controls: confirm completa a fala ou avança; cancel volta para a fala anterior.
## Escolhas (até 4): painel acima da caixa, alinhado à direita dela, depois que a pergunta termina de digitar. Setas
## andam, confirm escolhe, cancel escolhe a opção marcada "cancel" (se houver). No toque, tocar a linha escolhe.
## Depois de uma escolha, cancel não volta para antes dela.

signal event(name: String)            # eventos "emit:<nome>" das falas
signal _advance
signal _chosen(index: int)

const R := preload("res://scripts/dialogue_rules.gd")
const BG := Color("#0e1428e0")
const BORDER := Color("#3a4a78")
const SHINE := Color(0.353, 0.431, 0.659, 0.5)
const TEXT := Color("#f2f4ff")
const NARRATION := Color("#cfd8ff")
const SHADOW := Color("#0b0f1e")
const FRAME_BG := Color("#0a0f20")

var cover: ColorRect                  # fundo preto dos cartões
var card_text: RichTextLabel
var box: Panel
var portrait: TextureRect
var frame: Panel
var text: RichTextLabel
var arrow: TextureRect
var plate: PanelContainer
var plate_label: Label

var actors := {}                      # id -> Node2D na cena (para a caixa não cobrir quem fala)
var spk := {}
var lines: Array = []
var history: Array = []               # falas já mostradas nesta conversa (dicionários), no máximo R.HISTORY
var hist_pos := -1
var open := false
var closed_frame := -1
var opened_at := 0.0
var plain := ""                       # texto da fala atual, já quebrado em linhas e sem marcação
var shown := 0
var clock := 0.0
var typing := false
var on_top := false
var t := 0.0
var scene_name := ""
var cover_tw: Tween
var last_click := 0.0
var choice_panel: PanelContainer
var choice_box: VBoxContainer
var choosing: Array = []              # opções abertas agora (vazio: sem escolha)
var choice_at := 0.0                  # quando o painel abriu (CHOICE_GUARD)

func _ready() -> void:
	layer = 22
	spk = R.speakers()
	cover = ColorRect.new()
	cover.color = Color.BLACK
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	card_text = _rich(R.CARD_SIZE)
	cover.add_child(card_text)
	box = Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = R.BOX
	var st := UI.panel_style(BORDER, 1, BG)
	st.set_corner_radius_all(3)
	st.anti_aliasing = false
	box.add_theme_stylebox_override("panel", st)
	add_child(box)
	var shine := ColorRect.new()
	shine.color = SHINE
	shine.position = Vector2(3, 1)
	shine.size = Vector2(R.BOX.x - 6, 1)
	box.add_child(shine)
	frame = Panel.new()
	frame.size = Vector2(R.PORTRAIT, R.PORTRAIT)
	frame.add_theme_stylebox_override("panel", UI.panel_style(BORDER, 1, FRAME_BG))
	box.add_child(frame)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.size = frame.size
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(portrait)
	text = _rich(R.TEXT_SIZE)
	box.add_child(text)
	arrow = TextureRect.new()
	arrow.texture = UI.icon("more")
	arrow.size = Vector2(16, 16)
	box.add_child(arrow)
	plate = PanelContainer.new()
	var ps := UI.panel_style(BORDER, 1, Color("#0e1428"))
	ps.set_corner_radius_all(3)
	ps.anti_aliasing = false
	ps.content_margin_left = 6
	ps.content_margin_right = 6
	ps.content_margin_top = 0
	ps.content_margin_bottom = 0
	plate.add_theme_stylebox_override("panel", ps)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	choice_panel = PanelContainer.new()
	choice_panel.theme = UI.menu_theme()
	var cs := UI.panel_style(BORDER, 1, BG)
	cs.set_content_margin_all(R.CHOICE_PAD)
	cs.set_corner_radius_all(3)
	choice_panel.add_theme_stylebox_override("panel", cs)
	add_child(choice_panel)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 0)
	choice_panel.add_child(choice_box)
	Controls.touch_mode_changed.connect(func(_on): if not choosing.is_empty(): _build_choices())
	plate_label = UI.label("", R.TEXT_SIZE, Color.WHITE, 0)
	plate_label.custom_minimum_size.y = 16
	plate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(plate_label)
	_hide_all()

func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF      # as linhas já vêm quebradas (DialogueRules.wrap)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("font_shadow_color", SHADOW)
	r.add_theme_constant_override("shadow_offset_x", 1)
	r.add_theme_constant_override("shadow_offset_y", 1)
	r.add_theme_constant_override("line_separation", 0)
	return r

func _hide_all() -> void:
	cover.hide()
	box.hide()
	plate.hide()
	choice_panel.hide()

## A conversa está na tela (ou acabou de fechar neste quadro: o confirm que fechou não vale para a cena).
func is_open() -> bool:
	return open or closed_frame == Engine.get_process_frames()

## A caixa está em cima (a batalha esconde a barra do topo).
func box_on_top() -> bool:
	return open and box.visible and on_top

## Retângulo da caixa na tela (o toque põe o botão voltar acima dela).
func box_rect() -> Rect2:
	return Rect2(box.position, box.size)

func register_actor(id: String, node: Node2D) -> void:
	actors[id] = node

## Toca a cena inteira. Devolve os eventos que não são de flag nem de tempo (ex.: "battle:sineiro").
func play(scene: String, from := "") -> Array:
	var out := []
	if open:
		push_warning("Dialogue.play('%s') com outra conversa aberta" % scene)
		return out
	scene_name = scene
	lines = R.load_scene(scene).get("lines", [])
	history.clear()
	hist_pos = -1
	var i := R.index_of(lines, from) if from != "" else 0
	while true:
		i = R.first_valid(lines, i, Game.flags, Game.party.keys())
		if i == -1:
			break
		var ln: Dictionary = lines[i]
		if ln.has("text"):
			_show_line(ln)
		await _run_events(ln.get("do", []), out)
		var opts := R.choices_for(ln, Game.flags, Game.party.keys()) if ln.has("text") else []
		if not opts.is_empty():
			var c: Dictionary = opts[await _choose(opts)]
			await _run_events(c.get("do", []), out)
			history.clear()               # cancel não volta para antes da escolha
			hist_pos = -1
			i = R.choice_next(lines, i, c)
			continue
		if ln.has("text"):
			await _advance
		i = R.after(lines, i)
	_close()
	return out

## Eventos `do` de uma fala ou de uma opção: os de jogo rodam aqui, os outros vão para `out` (a cena trata).
func _run_events(evs: Array, out: Array) -> void:
	for e in R.apply_events(evs, Game.flags):
		var p := String(e).split(":", true, 1)
		match p[0]:
			"wait": await get_tree().create_timer(float(p[1]), false).timeout
			"heal": Game.heal_all()
			"emit": event.emit(p[1])
			"join": pass             # o grupo da fatia já está completo
			_: out.append(e)

## Espera a pergunta terminar de digitar, abre o painel e devolve o índice da opção escolhida.
func _choose(opts: Array) -> int:
	while typing or hist_pos < history.size() - 1:
		await get_tree().process_frame
	choosing = opts
	choice_at = t
	_build_choices()
	var idx: int = await _chosen
	choosing = []
	choice_panel.hide()
	opened_at = t                     # o aperto que escolheu não pula a fala seguinte
	return idx

## Monta as linhas (44 px no toque, 26 no teclado) e põe o painel acima ou abaixo da caixa.
func _build_choices(focus := 0) -> void:
	for ch in choice_box.get_children():
		choice_box.remove_child(ch)
		ch.queue_free()
	var touch := Controls.is_touch
	var row_h := R.choice_row_h(touch)
	var size := UI.TEXT_TOUCH if touch else R.TEXT_SIZE
	var texts := choosing.map(func(c): return R.fill(String(c.text), Game.names))
	var w := R.choice_width(texts, UI.body_font(), size)
	var rows: Array = []
	for i in choosing.size():
		var b := UI.menu_button(texts[i], func(): _pick(i), false, touch)
		b.custom_minimum_size = Vector2(w - 2 * R.CHOICE_PAD, row_h)
		var cur := TextureRect.new()
		cur.texture = UI.icon("cursor")
		cur.position = Vector2(4, (row_h - 7) / 2.0)
		cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cur.hide()
		b.add_child(cur)
		b.focus_entered.connect(cur.show)
		b.focus_exited.connect(cur.hide)
		choice_box.add_child(b)
		rows.append(b)
	for i in rows.size():                 # setas dão a volta e o foco não sai do painel
		var b: Button = rows[i]
		b.focus_neighbor_top = b.get_path_to(rows[(i - 1 + rows.size()) % rows.size()])
		b.focus_neighbor_bottom = b.get_path_to(rows[(i + 1) % rows.size()])
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	var r := R.choice_rect(box_rect(), on_top, rows.size(), row_h, w)
	choice_panel.position = r.position
	choice_panel.size = r.size
	choice_panel.show()
	rows[clampi(focus, 0, rows.size() - 1)].grab_focus.call_deferred()

func _pick(i: int) -> void:
	if choosing.is_empty() or t - choice_at < R.CHOICE_GUARD:
		return
	_chosen.emit(i)

func _show_line(ln: Dictionary) -> void:
	if not open:
		open = true
		opened_at = t
	history.append(ln)
	if history.size() > R.HISTORY:
		history.pop_front()
	hist_pos = history.size() - 1
	_render(ln, true)

func _close() -> void:
	if not open:
		return
	open = false
	closed_frame = Engine.get_process_frames()
	box.hide()
	plate.hide()
	if cover.visible:
		_fade_cover()

func _fade_cover() -> void:
	cover_tw = create_tween()
	cover_tw.tween_property(cover, "modulate:a", 0.0, 0.6)
	cover_tw.tween_callback(cover.hide)

## Desenha a fala: cartão em tela cheia, narração, ou fala com plaquinha e retrato.
func _render(ln: Dictionary, animate: bool) -> void:
	var who: Dictionary = spk.get(ln.get("speaker", ""), {})
	# tradução: a chave dlg.<cena>.<id>; sem tradução carregada, vale o português do JSON
	var k := R.key(scene_name, String(ln.get("id", "")))
	var src := tr(k)
	var raw := R.fill(String(ln.text) if src == k else src, Game.names)
	var font := UI.body_font()
	var wrapped := "\n".join(R.wrap_lines(raw, font, R.text_size(who), R.text_width(who)))
	plain = R.plain(wrapped)
	var target: RichTextLabel = card_text if who.get("card", false) else text
	var card: bool = who.get("card", false)
	target.text = ("[center]%s[/center]" if card else "%s") % R.to_bbcode(wrapped)
	shown = 0 if animate and Game.text_cps() > 0 else plain.length()
	clock = 0.0
	typing = shown < plain.length()
	target.visible_characters = shown
	if who.get("card", false):
		_layout_card()
		box.hide()
		plate.hide()
		if not cover.visible or cover.modulate.a < 1.0:
			if cover_tw != null:
				cover_tw.kill()
			cover.show()
			cover.modulate.a = 1.0
		return
	if cover.visible and cover.modulate.a >= 1.0:
		_fade_cover()
	_layout_box(String(ln.get("speaker", "")), who)

func _layout_card() -> void:
	var vis := get_viewport().get_visible_rect().size
	var lines_n := plain.count("\n") + 1
	var h := lines_n * UI.body_font().get_height(R.CARD_SIZE)
	card_text.size = Vector2(R.CARD_W, h + 4)
	card_text.position = ((vis - Vector2(R.CARD_W, h)) / 2.0).round()
	card_text.add_theme_color_override("default_color", TEXT)
	var safe := UI.safe_rect(get_viewport())
	arrow.reparent(cover, false)
	arrow.position = safe.end - Vector2(16, 12)

func _layout_box(id: String, who: Dictionary) -> void:
	var vis := get_viewport().get_visible_rect().size
	var safe := UI.safe_rect(get_viewport())
	var bottom := R.box_rect(vis.x, safe, false)
	var top := R.box_rect(vis.x, safe, true)
	var feet := Rect2()
	if actors.has(id) and is_instance_valid(actors[id]) and actors[id].is_inside_tree():
		feet = R.speaker_rect(actors[id].get_global_transform_with_canvas().origin)
	on_top = R.box_on_top(feet, bottom, top)
	var r := top if on_top else bottom
	box.position = r.position
	box.show()
	arrow.reparent(box, false)
	arrow.position = Vector2(R.BOX.x - 20, R.BOX.y - 14)
	var narr := String(who.get("name", "")) == ""
	var has_face: bool = who.get("portrait", false)
	var left: bool = who.get("side", "left") == "left"
	frame.visible = has_face
	var tx := 16.0
	if has_face:
		portrait.texture = Fx.face_texture(id, 32)
		portrait.flip_h = not left and who.get("flip", true)
		frame.position = Vector2(12, 12) if left else Vector2(R.BOX.x - 12 - R.PORTRAIT, 12)
		tx = 88.0 if left else 16.0
	var tw := R.text_width(who)
	text.position = Vector2(tx, 14)
	text.size = Vector2(tw, R.LINE_H * R.MAX_LINES + 4)
	text.add_theme_color_override("default_color", NARRATION if narr else TEXT)
	plate.visible = not narr
	if not narr:
		plate_label.text = R.fill(String(who.name), Game.names).to_upper()
		plate_label.add_theme_color_override("font_color", Color(who.get("color", "#e6e9f5")))
		plate.reset_size()
		var px := r.position.x + tx if left else r.position.x + tx + tw - plate.size.x
		plate.position = Vector2(px, r.position.y - 8)

func _process(delta: float) -> void:
	t += delta
	if not open:
		return
	var target: RichTextLabel = card_text if box.visible == false else text
	if typing:
		clock += delta
		var cps := Game.text_cps()
		var before := shown
		while shown < plain.length() and clock >= R.char_time(plain, shown, cps):
			clock -= R.char_time(plain, shown, cps)
			shown += 1
		# clique baixo da digitação, só nas falas (o cartão é silencioso) e com intervalo mínimo
		if shown > before and box.visible and AudioRules.click_due(plain[shown - 1], t - last_click):
			last_click = t
			Audio.sfx("digitar", AudioRules.CLICK_DB, randf_range(0.94, 1.06))
		typing = shown < plain.length()
		target.visible_characters = shown
	arrow.visible = not typing and choosing.is_empty()
	if not choosing.is_empty():
		if Input.is_action_just_pressed("cancel") and R.cancel_choice(choosing) != -1 and t - choice_at >= R.CHOICE_GUARD:
			UI.play("voltar")
			_chosen.emit(R.cancel_choice(choosing))
		return
	arrow.position.y = (R.BOX.y - 14 if arrow.get_parent() == box else UI.safe_rect(get_viewport()).end.y - 12) + (2.0 if fmod(t, 1.0) < 0.5 else 0.0)
	if Input.is_action_just_pressed("confirm") and R.accepts_confirm(t - opened_at):
		if typing:
			shown = plain.length()
			typing = false
			target.visible_characters = -1
		elif hist_pos < history.size() - 1:
			hist_pos += 1
			_render(history[hist_pos], false)
		else:
			_advance.emit()
	elif Input.is_action_just_pressed("cancel") and hist_pos > 0:
		hist_pos -= 1
		_render(history[hist_pos], false)
