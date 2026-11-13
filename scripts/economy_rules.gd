class_name EconomyRules
extends RefCounted
## Itens, bolsa, moedas, baús e loja em funções puras (economy-designer, 13/11). As cenas só leem daqui.
## IDs de item e de baú viram chave do save: NUNCA mudam depois do lançamento (ver SaveRules).

const ITEMS := {
	"pocao": {"name": "Poção", "kind": "heal", "amount": 50, "price": 15, "desc": "Recupera 50 PV de um aliado."},
	"eter": {"name": "Éter", "kind": "mp", "amount": 20, "price": 30, "desc": "Recupera 20 PM de um aliado."},
	"pena": {"name": "Pena Vital", "kind": "revive", "frac": 0.5, "price": 80, "desc": "Levanta quem caiu com metade dos PV."},
}
# Começo da fatia: 60 moedas e 2 Poções. A Pena Vital (80) só cabe a quem achou as 25 moedas do baú escondido.
const START_BAG := {"pocao": 2}
const START_GOLD := 60
# Bolsa do jogador cuidadoso (achou os dois baús e comprou a Pena): é o perfil do balanceamento (--auto, simulador).
const CAREFUL_BAG := {"pocao": 2, "pena": 1}
const STACK_MAX := 99
const GOLD_MAX := 999999
const SHOP_DORA := ["pocao", "eter", "pena"]
# Baús: "<lugar>:<baú>", nunca coordenada. Conteúdo: "item" (e "n") ou "gold".
const CHESTS := {
	"valmor:poco": {"item": "pocao", "n": 1},       # perto do poço, à vista: ensina que baú abre com confirm
	"valmor:quintal": {"gold": 25},                 # fora do caminho da igreja: premia quem explora
}

static func start_bag() -> Dictionary:
	return START_BAG.duplicate()

## O item serve para este alvo? `t`: {hp, hpmax, mp, mpmax}. A Pena só em quem caiu; o resto só em quem está de pé
## e precisa (Poção com PV faltando, Éter com PM faltando).
static func can_use(id: String, t: Dictionary) -> bool:
	match ITEMS[id].kind:
		"revive":
			return t.hp <= 0
		"heal":
			return t.hp > 0 and t.hp < t.hpmax
		"mp":
			return t.hp > 0 and t.get("mpmax", 0) > 0 and t.mp < t.mpmax
	return false

## Quem pode receber o item, na ordem do grupo.
static func targets(id: String, party: Dictionary, order: Array) -> Array:
	return order.filter(func(h): return party.has(h) and can_use(id, party[h]))

## Tem na bolsa e alguém pode receber.
static func usable(bag: Dictionary, id: String, party: Dictionary, order: Array) -> bool:
	return int(bag.get(id, 0)) > 0 and not targets(id, party, order).is_empty()

## Aplica o item no alvo (muda `t`) e devolve quanto recuperou.
static func apply_item(id: String, t: Dictionary) -> int:
	var it: Dictionary = ITEMS[id]
	match it.kind:
		"revive":
			t.hp = maxi(1, int(t.hpmax * float(it.frac)))
			return t.hp
		"heal":
			var before: int = t.hp
			t.hp = mini(t.hpmax, t.hp + int(it.amount))
			return t.hp - before
		"mp":
			var before: int = t.mp
			t.mp = mini(t.mpmax, t.mp + int(it.amount))
			return t.mp - before
	return 0

## Tira um da bolsa; falso se não havia.
static func take(bag: Dictionary, id: String) -> bool:
	if int(bag.get(id, 0)) <= 0:
		return false
	bag[id] = int(bag[id]) - 1
	return true

static func add(bag: Dictionary, id: String, n := 1) -> void:
	bag[id] = clampi(int(bag.get(id, 0)) + n, 0, STACK_MAX)

# ---------- moedas, loja e baús ----------
# `st` é o estado da bolsa: {"gold": int, "inv": {id: n}} (Game passa ele mesmo). As funções mudam `st` e dizem se deu.

static func price(id: String) -> int:
	return int(ITEMS[id].price)

## Venda pela metade, para baixo (Poção 7, Éter 15, Pena 40).
static func sell_price(id: String) -> int:
	return price(id) / 2

## Quantos dá para comprar com o dinheiro e o espaço da bolsa.
static func buy_max(gold: int, bag: Dictionary, id: String) -> int:
	return maxi(0, mini(gold / price(id), STACK_MAX - int(bag.get(id, 0))))

## Moedas que faltam para comprar um (0 se já dá).
static func missing(gold: int, id: String) -> int:
	return maxi(0, price(id) - gold)

static func buy(st: Dictionary, id: String) -> bool:
	if buy_max(st.gold, st.inv, id) < 1:
		return false
	st.gold -= price(id)
	add(st.inv, id)
	return true

static func sell(st: Dictionary, id: String) -> bool:
	if not take(st.inv, id):
		return false
	st.gold = mini(GOLD_MAX, st.gold + sell_price(id))
	return true

## Abre o baú uma vez só: põe o conteúdo em `st`, marca em `opened` e devolve o conteúdo. Já aberto: devolve {}.
static func open_chest(opened: Array, st: Dictionary, chest: String) -> Dictionary:
	if chest in opened or not CHESTS.has(chest):
		return {}
	opened.append(chest)
	var c: Dictionary = CHESTS[chest]
	if c.has("gold"):
		st.gold = mini(GOLD_MAX, st.gold + int(c.gold))
	if c.has("item"):
		add(st.inv, c.item, int(c.get("n", 1)))
	return c

## Texto do que saiu do baú: "Poção" ou "25 moedas" (e "2 Poções" não existe na fatia: "Poção x2").
static func loot_text(c: Dictionary) -> String:
	if c.has("gold"):
		return "%d moedas" % int(c.gold)
	var n := int(c.get("n", 1))
	return ITEMS[c.item].name + ("" if n == 1 else " x%d" % n)
