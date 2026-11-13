extends CanvasLayer
## Menu de pausa mínimo (Continuar, Opções, Tela cheia, Sair), aberto pela ação `menu` em qualquer cena que o instancie.
## Teclado e controle andam pelo foco; no toque, tocar a linha. `menu` ou `cancel` de novo fecham.
## Lê as ações por Input (não por evento): o botão de menu do toque aperta a ação sem gerar evento.

const COL := Vector2(140, 0)          # largura da coluna (layout-designer 4.2: botões 140x44 a partir de x 16, y 48)

var dim: ColorRect
var box: VBoxContainer
var title: Label
var back_focus: Control
var in_options := false
var coins: HBoxContainer

func _ready() -> void:
	layer = 15                         # abaixo dos controles de toque (20): o botão de menu continua visível
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var safe := UI.safe_rect(get_viewport())
	title = UI.label("Pausa", 24, Color.WHITE, 3)
	title.position = safe.position
	dim.add_child(title)
	var panel := PanelContainer.new()
	panel.theme = UI.menu_theme()
	panel.position = safe.position + Vector2(0, 32)
	dim.add_child(panel)
	box = VBoxContainer.new()
	box.custom_minimum_size = COL
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	coins = UI.coins_row()
	coins.position = safe.position + Vector2(COL.x + 16, 36)
	dim.add_child(coins)
	visible = false

func _process(_d: float) -> void:
	if Input.is_action_just_pressed("menu") or (visible and Input.is_action_just_pressed("cancel")):
		if visible and in_options and not Input.is_action_just_pressed("menu"):
			UI.play("voltar")
			_main()                       # cancel nas opções volta para a pausa
		elif visible:
			UI.play("voltar")
			close()
		elif Input.is_action_just_pressed("menu") and not get_tree().paused:   # a loja já pausou: não abre por cima
			open()

func open() -> void:
	back_focus = get_viewport().gui_get_focus_owner()
	UI.play("confirmar")
	visible = true
	get_tree().paused = true
	UI.set_coins(coins, Game.gold)
	_main()

func _main(focus := 0) -> void:
	in_options = false
	title.text = "Pausa"
	var acts := {"Continuar": close, "Opções": _options, "Tela cheia": Controls.toggle_fullscreen, "Sair": _quit}
	_rows(UI.pause_items(OS.has_feature("web"), OS.has_feature("mobile")).map(func(item): return [item, acts[item]]), focus)

## Opções da pausa: as mesmas do título (texto, música, efeitos), guardadas em Game.options.
func _options(focus := 0) -> void:
	in_options = true
	title.text = "Opções"
	var items := Game.option_rows(_options)
	items.append(["Voltar", func(): _main(1)])
	_rows(items, focus)

func _rows(items: Array, focus: int) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	var rows: Array = []
	for it in items:
		var b := UI.menu_button(it[0], it[1], false, Controls.is_touch)
		b.custom_minimum_size.y = UI.ROW_TOUCH        # 44 em todo aparelho, como no mockup
		box.add_child(b)
		rows.append(b)
	# o foco dá a volta dentro do menu e nunca escapa para a cena pausada embaixo
	for i in rows.size():
		var b: Button = rows[i]
		var up: Button = rows[(i - 1 + rows.size()) % rows.size()]
		var down: Button = rows[(i + 1) % rows.size()]
		for side in ["focus_neighbor_top", "focus_previous"]:
			b.set(side, b.get_path_to(up))
		for side in ["focus_neighbor_bottom", "focus_next"]:
			b.set(side, b.get_path_to(down))
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	rows[mini(focus, rows.size() - 1)].grab_focus.call_deferred()

## Sair pela pausa salva antes (a jogada continua de onde parou).
func _quit() -> void:
	if Game.started:
		Save.write()
	Audio.quit()

func close() -> void:
	Game.ui_closed_frame = Engine.get_process_frames()
	visible = false
	in_options = false
	get_tree().paused = false
	if is_instance_valid(back_focus) and back_focus.is_visible_in_tree():
		back_focus.grab_focus.call_deferred()
