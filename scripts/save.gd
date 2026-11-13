extends Node
## Camada única de save (autoload "Save"). Um arquivo só, user://save.json, nos três alvos:
## - Steam: Auto-Cloud apontando para a pasta do user:// (project.godot fixa custom_user_dir_name, para a pasta não
##   mudar quando o nome do jogo mudar). Um arquivo só, sem API.
## - Android: armazenamento interno do app.
## - Navegador: user:// vira IndexedDB (o Godot sincroniza depois de fechar o arquivo).
## Escrita atômica: grava save.json.tmp, guarda o save anterior como save.bak e renomeia o .tmp. Na leitura vale o
## primeiro que abrir entre save.json, .tmp (queda no meio da troca) e .bak. Formato e migração em SaveRules.
## Salva sozinho: ao entrar na Valmor, depois da luta, ao mudar uma opção, ao sair pela pausa e quando o jogo fecha
## ou vai para o fundo (celular, aba do navegador).
## Não grava nos autotestes (--auto, --shot, --demo, --dev-battle, --walk, --skip-intro) nem com --no-save.
## --save-name=<nome> usa user://<nome>.json (para testar sem mexer no save de verdade).

const S := preload("res://scripts/save_rules.gd")

var path := "user://save.json"
var enabled := true
var data := {}                        # o que foi lido no começo (SaveRules.parse); "game" só se havia jogo
var last_error := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--save-name="):
			path = "user://%s.json" % a.substr(12).validate_filename()
	enabled = not Array(args).any(func(a): return a in ["--auto", "--no-save", "--dev-battle", "--walk", "--skip-intro"] \
		or a.begins_with("--shot") or a.begins_with("--demo="))
	data = read()
	if data.has("options"):
		Game.options = data.options.duplicate()
		Audio.apply_options()

## Há um jogo salvo para "Continuar".
func has_game() -> bool:
	return data.has("game")

## Lê o save (o primeiro dos três arquivos que abrir). {} se não houver nenhum.
func read() -> Dictionary:
	for p in [path, path + ".tmp", path.trim_suffix(".json") + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var d := S.parse(FileAccess.get_file_as_string(p))
		if not d.is_empty():
			return d
		push_warning("Save: '%s' não abriu, tentando o próximo" % p)
	return {}

## Grava opções e, se há jogada, o jogo. Devolve se gravou.
func write() -> bool:
	var game: Variant = Game.snapshot() if Game.started else data.get("game")
	var text := S.pack(game, Game.options, int(Time.get_unix_time_from_system()))
	data = S.parse(text)
	if not enabled:
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail("não abriu %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
	f.store_string(text)
	f.close()
	var bak := path.trim_suffix(".json") + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return _fail("não renomeou %s (%s)" % [tmp, error_string(err)])
	last_error = ""
	return true

func _fail(msg: String) -> bool:
	last_error = msg
	push_warning("Save: " + msg)
	return false

## Continuar: o jogo salvo volta para o Game e a Valmor abre onde o líder estava.
func load_game() -> void:
	Game.reset()
	Game.restore(data.game)
	Game.started = true
	Game.goto(Game.VALMOR)

## Fechar a janela, ir para o fundo no celular ou trocar de aba no navegador: salva o que houver.
func _notification(what: int) -> void:
	var leaving := what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and (OS.has_feature("web") or OS.has_feature("mobile")):
		leaving = true
	if leaving and Game.started:
		write()
