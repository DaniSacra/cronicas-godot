extends CanvasLayer
## Loja da Dora (economy-designer): Poção, Éter e Pena Vital, venda pela metade. Regras em EconomyRules; as falas
## curtas da Dora vêm de data/dialogue/loja_dora.json pelos ids de entrada (comprar, compra_<item>, venda_ok...).
## Abre por cima da Valmor e pausa o jogo, como a pausa. Teclado e controle andam pelo foco; cancel volta da venda
## para a compra e da compra para fora. No toque, linhas de 44 e dois toques para comprar ou vender (o primeiro marca
## a linha e mostra o preço, o segundo confirma), como nos submenus da batalha.

const EC := preload("res://scripts/economy_rules.gd")
const DR := preload("res://scripts/dialogue_rules.gd")
const SCENE := "loja_dora"
const W_KEYS := 248
const W_TOUCH := 440

var panel: PanelContainer
var list: VBoxContainer
var title: Label
var dora: Label                       # a fala da Dora (muda a cada compra)
var info: Label                       # o item marcado: efeito, quanto há na bolsa, quanto falta
var coins: HBoxContainer
var selling := false
var armed := ""
var closing := Callable()             # quem abriu é avisado ao fechar

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	panel.theme = UI.menu_theme()
	var st := UI.panel_style()
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	dim.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title = UI.label("", 12, Color("#ffe6a8"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	coins = UI.coins_row()
	head.add_child(coins)
	dora = UI.label("", 12, Color("#f2f4ff"))
	dora.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(dora)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	v.add_child(list)
	info = UI.label("", 12, Color("#cfd8ff"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.y = 34
	v.add_child(info)
	visible = false

## Abre na compra ou na venda. `on_close`: chamado ao sair (a Valmor toca a despedida).
func open(sell := false, on_close := Callable()) -> void:
	closing = on_close
	visible = true
	get_tree().paused = true
	if sell:
		_sell_rows()
	else:
		_buy_rows()

func _process(_d: float) -> void:
	if not visible:
		return
	if Input.is_action_just_pressed("cancel") or Input.is_action_just_pressed("menu"):
		UI.play("voltar")
		if selling:
			_buy_rows()
		else:
			close()

func close() -> void:
	visible = false
	get_tree().paused = false
	Game.ui_closed_frame = Engine.get_process_frames()
	Save.write()
	if closing.is_valid():
		closing.call()

## Fala curta da Dora pelo id de entrada (com as condições do arquivo).
func _say(from: String) -> void:
	dora.text = "Dora: " + DR.line_text(SCENE, from, Game.flags, Game.party.keys())

## Compra: os três itens com o preço à direita, Vender e Sair. Sem dinheiro a linha fica apagada mas responde (a Dora
## diz que faltam moedas e a descrição diz quantas).
func _buy_rows(focus := 0) -> void:
	selling = false
	title.text = "Loja da Dora"
	var rows := []
	for id in EC.SHOP_DORA:
		rows.append([EC.ITEMS[id].name, func(): _trade(id, true), str(EC.price(id)), id, EC.buy_max(Game.gold, Game.inv, id) < 1])
	rows.append(["Vender", func(): _sell_rows(), "", "Vender pela metade do preço.", false])
	rows.append(["Sair", close, "", "Sair da loja.", false])
	_rows(rows, focus)
	_say("comprar")

## Venda: só o que está na bolsa, pela metade do preço.
func _sell_rows(focus := 0) -> void:
	selling = true
	title.text = "Vender"
	var rows := []
	for id in _held():
		rows.append([EC.ITEMS[id].name, func(): _trade(id, false), str(EC.sell_price(id)), id, false])
	rows.append(["Comprar", func(): _buy_rows(), "", "Voltar às compras.", false])
	rows.append(["Sair", close, "", "Sair da loja.", false])
	_rows(rows, focus)
	_say("vender" if not _held().is_empty() else "venda_nada")

func _held() -> Array:
	return EC.ITEMS.keys().filter(func(id): return int(Game.inv.get(id, 0)) > 0)

## Compra ou vende um. No toque, só no segundo toque na mesma linha.
func _trade(id: String, buying: bool) -> void:
	if not UI.tap_confirms(armed, id, Controls.is_touch):
		armed = id
		list.get_child(_index_of(id)).grab_focus()
		return
	var st := Game.purse()
	var ok := EC.buy(st, id) if buying else EC.sell(st, id)
	Game.set_purse(st)
	if not ok:
		UI.play("negado")
	if buying:
		_buy_rows(_index_of(id))
		var full := int(Game.inv.get(id, 0)) >= EC.STACK_MAX
		_say("compra_" + id if ok else ("compra_bolsa_cheia" if full else "compra_sem_moedas"))
	else:
		_sell_rows(mini(_index_of(id), _held().size()))
		_say("venda_ok")

func _index_of(id: String) -> int:
	for i in list.get_child_count():
		if list.get_child(i).get_meta("id", "") == id:
			return i
	return 0

## Linhas: [texto, ação, valor, id do item ou descrição, apagada]. A linha marcada mostra a descrição, quanto há na
## bolsa e, se não der para comprar, quantas moedas faltam.
func _rows(rows: Array, focus: int) -> void:
	armed = ""
	UI.set_coins(coins, Game.gold)
	for ch in list.get_children():
		list.remove_child(ch)
		ch.queue_free()
	var touch := Controls.is_touch
	panel.custom_minimum_size.x = W_TOUCH if touch else W_KEYS
	var buttons := []
	for r in rows:
		var item: bool = EC.ITEMS.has(r[3])
		var b := UI.menu_button(r[0], r[1], false, touch, r[2])
		b.set_meta("id", r[3] if item else "")
		if r[4]:                          # sem dinheiro: apagada, mas ainda escolhe (para a Dora responder)
			b.modulate.a = 0.45
		var desc: String = _describe(r[3]) if item else r[3]
		b.focus_entered.connect(func(): info.text = desc)
		list.add_child(b)
		buttons.append(b)
	for i in buttons.size():          # o foco dá a volta e não escapa para a cena pausada
		var b: Button = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	buttons[clampi(focus, 0, buttons.size() - 1)].grab_focus.call_deferred()
	_place.call_deferred()

func _describe(id: String) -> String:
	var have := "Na bolsa: %d." % int(Game.inv.get(id, 0))
	if not selling and EC.missing(Game.gold, id) > 0:
		have += " Faltam %d moedas." % EC.missing(Game.gold, id)
	return "%s %s" % [EC.ITEMS[id].desc, have]

## No meio da área segura, no alto.
func _place() -> void:
	panel.reset_size()
	var safe := UI.safe_rect(get_viewport())
	panel.position = Vector2(roundf(safe.position.x + (safe.size.x - panel.size.x) / 2.0), safe.position.y + 8)
