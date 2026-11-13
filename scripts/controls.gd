extends Node
## Camada única de comandos: teclado, controle e toque chamam as mesmas ações.
## O jogo nunca lê tecla direto: pergunta a `Controls`.

signal touch_mode_changed(on: bool)
signal device_changed(mode: String)    # "keys", "pad" ou "touch": as dicas na tela trocam de rótulo

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"confirm": [KEY_ENTER, KEY_SPACE, KEY_E], "cancel": [KEY_ESCAPE, KEY_BACKSPACE], "menu": [KEY_TAB, KEY_M],
	"fullscreen": [KEY_F11],
}
# Os menus do Godot (Button, foco) ouvem ui_accept e ui_cancel: recebem as mesmas teclas e botões de confirm e cancel.
const UI_ALIAS := {"ui_accept": "confirm", "ui_cancel": "cancel"}
# Rótulo de cada ação em cada aparelho, para as dicas na tela ("E: entrar", "A: entrar").
const PROMPTS := {
	"keys": {"confirm": "E", "cancel": "Esc", "menu": "Tab", "move": "WASD ou setas", "fullscreen": "F11", "hold": "E", "tap": "aperte E"},
	"pad": {"confirm": "A", "cancel": "B", "menu": "Start", "move": "Analógico", "hold": "A", "tap": "aperte A"},
	"touch": {"confirm": "A", "cancel": "B", "menu": "Menu", "move": "Círculo", "hold": "o dedo na tela", "tap": "toque na tela"},
}
const PAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
	"confirm": [JOY_BUTTON_A], "cancel": [JOY_BUTTON_B], "menu": [JOY_BUTTON_Y, JOY_BUTTON_START],
}
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

var touch_vec := Vector2.ZERO        # o joystick virtual escreve aqui
var is_touch := false
var forced := false                  # --touch ou ?touch=1: mantém a interface de toque mesmo com teclado
var pad := false                     # o último comando veio de um controle
var fingers := {}                    # dedos encostados na tela agora (índice -> true)
var heard_ms := -1                   # primeiro aperto desde listen_press() (ms de Time.get_ticks_msec), -1 se nenhum

## O vetor de maior força vence (teclado, controle ou joystick virtual), com tamanho no máximo 1.
static func combine(a: Vector2, b: Vector2) -> Vector2:
	var v := a if a.length() >= b.length() else b
	return v.limit_length(1.0)

## Posição do dedo -> vetor do joystick, com zona morta no centro.
static func stick_vector(center: Vector2, pos: Vector2, radius: float, dead := 0.15) -> Vector2:
	var d := (pos - center) / radius
	if d.length() < dead:
		return Vector2.ZERO
	return d.limit_length(1.0)

## Rótulo de uma ação no aparelho dado; ação sem rótulo devolve o próprio nome.
static func prompt_for(action: String, mode: String) -> String:
	return PROMPTS[mode].get(action, action)

## Aparelho em uso agora: "touch", "pad" ou "keys".
func mode() -> String:
	return "touch" if is_touch else ("pad" if pad else "keys")

func prompt(action: String) -> String:
	return prompt_for(action, mode())

## O botão mais perto de `pos` dentro de `reach` (índice em `centers`), ou -1. Zonas que se cruzam não apertam dois.
static func nearest(centers: Array, pos: Vector2, reach: float) -> int:
	var best := -1
	for i in centers.size():
		var d: float = pos.distance_to(centers[i])
		if d <= reach and (best == -1 or d < pos.distance_to(centers[best])):
			best = i
	return best

## Toque em modo diálogo (Voltar redondo, tocar na tela avança) só com a fala aberta e o jogo andando. Com a pausa
## por cima, a fala espera congelada e o toque é da pausa (o Voltar redondo caía sobre a linha "Sair").
static func dialogue_mode(open: bool, paused: bool) -> bool:
	return open and not paused

## "Segurar" (carga do golpe): o botão de confirmar ou, no toque, qualquer dedo na tela.
static func holding(pressed: bool, touch: bool, finger_count: int) -> bool:
	return pressed or (touch and finger_count > 0)

func confirm_held() -> bool:
	return holding(Input.is_action_pressed("confirm"), is_touch, fingers.size())

## Ação no tempo certo: começa a ouvir. Só o primeiro aperto conta (confirm ou, no toque, qualquer dedo),
## para não valer apertar sem parar.
func listen_press() -> void:
	heard_ms = -1

func _heard(e: InputEvent) -> void:
	var tap: bool = e is InputEventScreenTouch and e.pressed
	tap = tap or (forced and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed)
	if heard_ms < 0 and (tap or (e.is_action_pressed("confirm") and not e.is_echo())):
		heard_ms = Time.get_ticks_msec()

func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # troca de aparelho e tela cheia valem com o jogo pausado
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for b in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, jm)
	for ui in UI_ALIAS:
		for ev in InputMap.action_get_events(UI_ALIAS[ui]):
			if not InputMap.action_has_event(ui, ev):
				InputMap.action_add_event(ui, ev)
	# Tab abre o menu de pausa: não pode também pular o foco entre os botões (os menus andam pelas setas)
	for a in ["ui_focus_next", "ui_focus_prev"]:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and ev.keycode == KEY_TAB:
				InputMap.action_erase_event(a, ev)
	forced ="--touch" in OS.get_cmdline_user_args()
	is_touch = forced or _detect_touch()

func _detect_touch() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("(navigator.maxTouchPoints || 0) > 0 || ('ontouchstart' in window)"))
	return DisplayServer.is_touchscreen_available()

func move_vector() -> Vector2:
	return combine(Input.get_vector("move_left", "move_right", "move_up", "move_down"), touch_vec)

func _input(e: InputEvent) -> void:
	# a interface de toque aparece no primeiro toque e some quando o jogador usa teclado ou controle
	_heard(e)
	var before := mode()
	var now := is_touch
	if e is InputEventScreenTouch:
		now = true
		_finger(e.index, e.pressed)
	elif forced and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_finger(99, e.pressed)      # --touch na área de trabalho: o mouse faz o papel do dedo
	elif (e is InputEventKey or e is InputEventJoypadButton) and not forced:
		now = false
		pad = e is InputEventJoypadButton
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.5 and not forced:
		now = false
		pad = true
	if now != is_touch:
		is_touch = now
		if not now:
			fingers.clear()
		touch_mode_changed.emit(is_touch)
	if mode() != before:
		device_changed.emit(mode())

func _finger(index: int, down: bool) -> void:
	if down:
		fingers[index] = true
	else:
		fingers.erase(index)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("fullscreen"):
		toggle_fullscreen()
