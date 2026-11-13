class_name AudioRules
extends RefCounted
## Regras puras do som (sem nós): nome do som -> arquivo e barramento, escolha de voz, volumes em dB, ducking,
## tempos de espera e o clique da digitação. O autoload Audio só executa o que sai daqui.
## Arquivos e origem: assets/audio/ORIGEM.md. Trocar um som é trocar o arquivo; os nomes abaixo não mudam.

const ROOT := "res://assets/audio/"
# Nome usado no código -> arquivo. Apelidos (digitar, em_cheio) apontam para um arquivo que já existe até haver um próprio.
const SOUNDS := {
	"valmor_noite": "music/valmor_noite.ogg", "chefe_sineiro": "music/chefe_sineiro.ogg",
	"valmor_vento": "amb/valmor_vento.ogg", "cripta_gotas": "amb/cripta_gotas.ogg",
	"vitoria": "sfx/jingle/vitoria.ogg", "derrota": "sfx/jingle/derrota.ogg",
	"passo_neve_1": "sfx/field/passo_neve_1.wav", "passo_neve_2": "sfx/field/passo_neve_2.wav",
	"passo_neve_3": "sfx/field/passo_neve_3.wav", "passo_neve_4": "sfx/field/passo_neve_4.wav",
	"descer_cripta": "sfx/field/descer_cripta.wav",
	"sino_entrada": "sfx/boss/sino_entrada.wav", "badalada": "sfx/boss/badalada.wav", "dobre": "sfx/boss/dobre.wav",
	"golpe_sino": "sfx/boss/golpe_sino.wav", "furia": "sfx/boss/furia.wav", "ultimo_toque": "sfx/boss/ultimo_toque.wav",
	"avanco": "sfx/battle/avanco.wav", "volta": "sfx/battle/volta.wav", "espada": "sfx/battle/espada.wav",
	"impacto": "sfx/battle/impacto.wav", "impacto_magico": "sfx/battle/impacto_magico.wav",
	"dano_heroi": "sfx/battle/dano_heroi.wav", "queda": "sfx/battle/queda.wav", "defender": "sfx/battle/defender.wav",
	"golpe_forte": "sfx/skill/golpe_forte.wav", "passo_sombras_some": "sfx/skill/passo_sombras_some.wav",
	"passo_sombras_volta": "sfx/skill/passo_sombras_volta.wav", "fogo": "sfx/skill/fogo.wav", "gelo": "sfx/skill/gelo.wav",
	"cura": "sfx/skill/cura.wav", "luz_sagrada": "sfx/skill/luz_sagrada.wav",
	"carga": "sfx/skill/carga.wav", "carga_cheia": "sfx/skill/carga_cheia.wav",
	"cursor": "sfx/ui/cursor.wav", "confirmar": "sfx/ui/confirmar.wav", "voltar": "sfx/ui/voltar.wav", "negado": "sfx/ui/negado.wav",
	"digitar": "sfx/ui/cursor.wav",
}
const STEPS := ["passo_neve_1", "passo_neve_2", "passo_neve_3", "passo_neve_4"]
const BUSES := ["Music", "Ambience", "SFX", "UI"]
# Volume de cada barramento antes das opções do jogador (os arquivos já vêm no pico da tabela de mixagem:
# música -18, ambiente -24, golpes -10 a -4, UI -20 dBFS). Ajustar aqui depois de ouvir (A.4).
const BUS_DB := {"Music": 0.0, "Ambience": 0.0, "SFX": 0.0, "UI": 0.0}
const MAX_VOICES := {"SFX": 8, "UI": 3}     # celular e navegador: no máximo ~8 efeitos ao mesmo tempo
const DUCK_DB := -5.0                       # a música desce durante a habilidade especial
const DUCK_IN := 0.3
const DUCK_OUT := 0.4
const XFADE := 0.5                          # troca de música
const MUTE_DB := -80.0
# Opções: nível de 0 a 10 (10 = volume da mixagem). O botão dá a volta nestes passos.
const LEVELS := [10, 8, 6, 4, 2, 0]
const DEFAULT_LEVEL := 10
const CLICK_GAP := 0.07                     # digitação: no máximo um clique a cada 70 ms
const CLICK_DB := -6.0
const QUIET := " \n\t.,;:!?…\"'()-"         # letras que não clicam
const STEP_GAP := 0.26                      # passo na neve enquanto o líder anda (o balanço do quadro dura 0,26 s)
const BELL_TAIL := 2.5                      # a música do chefe espera a cauda da badalada de entrada
const LAST_TOLL := 6.5                      # o último toque se apaga
const SILENCE := 1.2                        # silêncio antes do jingle de vitória

static func path(name: String) -> String:
	return ROOT + SOUNDS[name] if SOUNDS.has(name) else ""

## Barramento pela pasta: música e jingles no Music (o volume de Música vale para eles), ambiente no Ambience,
## UI no UI, o resto no SFX.
static func bus_of(name: String) -> String:
	var p: String = SOUNDS.get(name, "")
	if p.begins_with("music/") or p.begins_with("sfx/jingle/"):
		return "Music"
	if p.begins_with("amb/"):
		return "Ambience"
	if p.begins_with("sfx/ui/"):
		return "UI"
	return "SFX"

## Toca em laço (música e ambiente). Jingles não.
static func loops(name: String) -> bool:
	var p: String = SOUNDS.get(name, "")
	return p.begins_with("music/") or p.begins_with("amb/")

## Qual voz do grupo usar: a primeira livre; se todas tocam, a que começou há mais tempo (corta a mais velha).
static func pick_voice(busy: Array, started: Array) -> int:
	var oldest := 0
	for i in busy.size():
		if not busy[i]:
			return i
		if started[i] < started[oldest]:
			oldest = i
	return oldest

## Nível de opção (0 a 10) em dB: 10 = 0 dB, 0 = mudo.
static func level_db(level: int) -> float:
	if level <= 0:
		return MUTE_DB
	return linear_to_db(clampf(level / 10.0, 0.0, 1.0))

## Volume final de um barramento: mixagem + opção do jogador + ducking (só na música).
static func bus_db(bus: String, level: int, duck := 0.0) -> float:
	if level <= 0:
		return MUTE_DB
	return BUS_DB.get(bus, 0.0) + level_db(level) + (duck if bus == "Music" else 0.0)

## Qual opção controla o barramento: "music" (Música) ou "sfx" (Efeitos, inclui ambiente e UI).
static func option_of(bus: String) -> String:
	return "music" if bus == "Music" else "sfx"

static func level_next(level: int) -> int:
	var i := LEVELS.find(level)
	return LEVELS[(i + 1) % LEVELS.size()] if i >= 0 else DEFAULT_LEVEL

static func level_text(level: int) -> String:
	return "%d%%" % (clampi(level, 0, 10) * 10)

## Quanto falta esperar para `total` segundos depois de algo que começou há `elapsed` (nunca negativo).
static func wait_left(elapsed: float, total: float) -> float:
	return maxf(0.0, total - elapsed)

## Clique da digitação: só em letra visível e com intervalo mínimo, para não virar zumbido nas falas rápidas.
static func click_due(ch: String, since: float) -> bool:
	return ch != "" and not QUIET.contains(ch) and since >= CLICK_GAP

## Próximo passo na neve: sorteia entre as quatro variações sem repetir a anterior. `r` em [0, 1).
static func step_pick(last: int, r: float) -> int:
	var n := STEPS.size()
	if last < 0:
		return int(r * n) % n
	var i := int(r * (n - 1)) % (n - 1)
	return i + 1 if i >= last else i

## No navegador o som só liga depois do primeiro toque ou tecla: até lá a música e o ambiente ficam guardados.
static func may_start(web: bool, unlocked: bool) -> bool:
	return not web or unlocked
