class_name ValmorRules
extends RefCounted
## A Valmor em dados e funções puras: paredes, a porta da igreja velha, os baús, os moradores, o que responde ao
## confirm e quando a fatia acaba. Posições em pixels da imagem gerada (assets/valmor_night.png); a cena converte.
## IDs de morador viram parte de flag de save (falou_<id>_antes, falou_<id>_depois, tobias_visto): nunca mudam.

const CROP := Rect2(98, 55, 444, 249)   # a arte útil dentro da imagem gerada (sem a borda roxa)
const ZOOM := 3.0                       # escala inteira do cenário
const BLOCKERS := [                     # casas e árvores
	Rect2(200, 80, 105, 122), Rect2(122, 135, 95, 90), Rect2(295, 98, 68, 66), Rect2(405, 140, 122, 100),
	Rect2(100, 228, 92, 80), Rect2(190, 256, 150, 50), Rect2(98, 55, 36, 250), Rect2(98, 55, 110, 82),
	Rect2(448, 55, 94, 88), Rect2(500, 55, 42, 250)]
const WALK := Rect2(130, 140, 380, 160)
const START := Vector2(345, 262)       # onde o grupo nasce (jogo novo, ou save com posição que não serve)
const CHURCH := Vector2(295, 232)       # a porta da igreja velha (a descida para a cripta)
const RANGE := 34.0                     # alcance do confirm, em pixels do mundo
const SOLID := Vector2(32, 12)          # baú e morador são sólidos (mundo): o líder para do lado, não em cima
const NPC_DEPTH := 20.0                 # o morador é sólido até 20 px abaixo do pé: o líder para antes e não o cobre
# Baús (EconomyRules.CHESTS). O escondido fica ao pé do poste, no fim da estrada para o norte.
const CHEST_AT := {"valmor:poco": Vector2(240, 238), "valmor:quintal": Vector2(392, 146)}
# Moradores, com sprite provisório: o quadro parado de um herói (`base`) em silhueta tingida (`tint`), sem arte nova.
# Ficam fora do meio da estrada e fora das luzes dos postes. A capela é a casa do meio, no alto da estrada; o Tobias
# está deitado na porta dela, no fim do caminho: falar com ele depois do Sineiro fecha a fatia.
const NPCS := {
	"hugo": {"at": Vector2(320, 226), "scene": "valmor_hugo", "verb": "falar com Hugo", "base": "aldo", "tint": "#b08d57"},
	"berta": {"at": Vector2(296, 208), "scene": "valmor_berta", "verb": "falar com Berta", "base": "andilla", "tint": "#c9826b"},
	"ana": {"at": Vector2(200, 240), "scene": "valmor_ana", "verb": "falar com Ana", "base": "teo", "tint": "#a7a3c9"},
	"clara": {"at": Vector2(220, 226), "scene": "valmor_clara", "verb": "falar com Clara", "base": "lyra", "tint": "#d9a6c8"},
	"bertoldo": {"at": Vector2(262, 246), "scene": "valmor_bertoldo", "verb": "falar com Bertoldo", "base": "aldo", "tint": "#9a9a8a"},
	"irene": {"at": Vector2(332, 172), "scene": "valmor_irene", "verb": "falar com Irene", "base": "lyra", "tint": "#e8e4d0"},
	"tobias": {"at": Vector2(356, 180), "scene": "capela_tobias", "verb": "ver o ferido", "base": "aldo", "tint": "#d8c8b0", "lying": true},
	"nino": {"at": Vector2(463, 286), "scene": "valmor_nino", "verb": "falar com Nino", "base": "teo", "tint": "#7fb0d8", "scale": 0.85},
	"dora": {"at": Vector2(440, 245), "scene": "loja_dora", "verb": "loja da Dora", "base": "andilla", "tint": "#c7b06a"},
}

static func to_world(img: Vector2) -> Vector2:
	return (img - CROP.position) * ZOOM

static func to_img(world: Vector2) -> Vector2:
	return world / ZOOM + CROP.position

## Parede ou fora do chão andável (pixel da imagem). Baús e moradores ficam de fora: ver solid_rect.
static func wall(img: Vector2) -> bool:
	return not WALK.has_point(img) or BLOCKERS.any(func(r): return r.has_point(img))

## O líder não pode ficar neste ponto do mundo: parede, fora do chão, baú ou morador.
static func blocked(world: Vector2) -> bool:
	if wall(to_img(world)):
		return true
	for c in CHEST_AT:
		if solid_rect(CHEST_AT[c]).has_point(world):
			return true
	for n in NPCS:
		if solid_rect(NPCS[n].at, true, NPCS[n].has("lying")).has_point(world):
			return true
	return false

## Onde o líder aparece: a posição salva (mundo) se ela for andável, senão o começo. Save antigo com a Valmor
## refeita, arquivo mexido ou posição fora do mapa nunca prendem o jogador numa parede.
static func spawn(saved: Vector2) -> Vector2:
	if saved.is_finite() and not blocked(saved):
		return saved
	return to_world(START)

## Retângulo sólido (mundo) de um baú (`npc` falso) ou de um morador em `img`. O morador vai mais para baixo (o líder
## para antes e não fica na frente dele); deitado, ocupa também a esteira.
static func solid_rect(img: Vector2, npc := false, lying := false) -> Rect2:
	var top := SOLID.y * 2.0 / 3.0
	if lying:
		return Rect2(to_world(img) - Vector2(26, 11), Vector2(52, 11 + NPC_DEPTH))
	var h := top + NPC_DEPTH if npc else SOLID.y
	return Rect2(to_world(img) - Vector2(SOLID.x / 2.0, top), Vector2(SOLID.x, h))

## Pontos que respondem ao confirm: a porta (até a vitória), os baús e os moradores. {id, at, verb, kind}.
static func spots(flags: Dictionary, opened: Array) -> Array:
	var out := []
	if not flags.get("sineiro_morto", false):
		out.append({"id": "igreja", "at": CHURCH, "verb": "entrar na igreja velha", "kind": "door"})
	for c in CHEST_AT:
		out.append({"id": c, "at": CHEST_AT[c], "verb": "olhar o baú" if c in opened else "abrir o baú", "kind": "chest"})
	for n in NPCS:
		out.append({"id": n, "at": NPCS[n].at, "verb": NPCS[n].verb, "kind": "npc"})
	return out

## O ponto mais perto do líder (pixel da imagem) dentro do alcance, ou {}.
static func nearest(list: Array, leader_img: Vector2) -> Dictionary:
	var best := {}
	var reach := RANGE / ZOOM
	for sp in list:
		var d := leader_img.distance_to(sp.at)
		if d < reach and (best.is_empty() or d < leader_img.distance_to(best.at)):
			best = sp
	return best

## Onde fica o "!": na porta até a vitória, depois no Tobias até a conversa final; Vector2.ZERO quando acabou.
static func mark_at(flags: Dictionary) -> Vector2:
	if not flags.get("sineiro_morto", false):
		return CHURCH
	if not flags.get("tobias_visto", false):
		return NPCS.tobias.at
	return Vector2.ZERO

## O cartão final toca quando o Tobias foi visto (fala depois do Sineiro) e a fatia ainda não acabou.
static func ending_ready(flags: Dictionary) -> bool:
	return flags.get("tobias_visto", false) and not flags.get("fatia_concluida", false)

## Para que lado o morador olha para encarar quem fala com ele.
static func face_toward(from: Vector2, to: Vector2) -> String:
	var d := to - from
	if absf(d.x) > absf(d.y):
		return "east" if d.x > 0 else "west"
	return "south" if d.y >= 0 else "north"
