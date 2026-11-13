class_name BattleRules
extends RefCounted
## Regras da batalha, em funções puras (sem cena, sem sorteio escondido), portadas de src/party.js do jogo em JS.
## O sorteio entra por parâmetro para os testes serem exatos.

const E := preload("res://scripts/economy_rules.gd")
const GUARD_MAX := 80.0
const GUARD_HALF := 55.0

const HEROES := {
	"aldo": {"name": "Aldo", "cls": "Guerreiro", "color": "#e0a040", "energy": true,
		"base": {"hp": 48, "mp": 0, "atk": 13, "def": 22.5, "res": 4, "mag": 3, "agi": 7},
		"grow": {"hp": 10, "mp": 0, "atk": 3, "def": 5, "res": 1, "mag": 0.5, "agi": 1}, "skills": ["golpe"]},
	"lyra": {"name": "Lyra", "cls": "Maga", "color": "#d070e0", "energy": false,
		"base": {"hp": 30, "mp": 20, "atk": 6, "def": 10, "res": 12, "mag": 12, "agi": 10},
		"grow": {"hp": 5, "mp": 4, "atk": 1, "def": 2.5, "res": 3, "mag": 3, "agi": 1.2}, "skills": ["fogo", "gelo"]},
	"teo": {"name": "Teo", "cls": "Aprendiz", "color": "#60d0a0", "energy": false,
		"base": {"hp": 36, "mp": 16, "atk": 9, "def": 15, "res": 10, "mag": 9, "agi": 6},
		"grow": {"hp": 7, "mp": 3, "atk": 2, "def": 3.75, "res": 3, "mag": 2, "agi": 1}, "skills": ["cura", "luz"]},
	"andilla": {"name": "Andilla", "cls": "Ladina", "color": "#e05a5a", "energy": true,
		"base": {"hp": 34, "mp": 0, "atk": 11, "def": 12.5, "res": 6, "mag": 4, "agi": 14},
		"grow": {"hp": 6, "mp": 0, "atk": 2.5, "def": 3, "res": 2, "mag": 0.5, "agi": 1.6}, "skills": ["golpeBaixo"]},
}

# cost_kind: "mp" ou "en" (Energia, que só existe em batalha)
const SKILLS := {
	"golpe": {"name": "Golpe Forte", "kind": "phys", "cost_kind": "en", "cost": 20, "power": 1.4, "target": "enemy"},
	"golpeBaixo": {"name": "Passo das Sombras", "kind": "phys", "cost_kind": "en", "cost": 20, "power": 1.3, "pierce": true, "target": "enemy"},
	"fogo": {"name": "Fogo", "kind": "mag", "cost_kind": "mp", "cost": 4, "power": 2.8, "base": 8, "target": "enemy"},
	"gelo": {"name": "Gelo", "kind": "mag", "cost_kind": "mp", "cost": 8, "power": 1.4, "base": 6, "target": "enemy", "delay": true},
	"cura": {"name": "Cura", "kind": "heal", "cost_kind": "mp", "cost": 3, "power": 2.0, "base": 20, "target": "ally"},
	"luz": {"name": "Luz Sagrada", "kind": "holy", "cost_kind": "mp", "cost": 5, "power": 2.0, "base": 10, "target": "enemy"},
}

const ENERGY := {"max": 100, "start": 10, "attack": 15, "defend": 10, "hurt": 8}

# O Sineiro (src/data.js)
const SINEIRO := {"name": "O Sineiro", "hp": 1010, "atk": 39, "def": 25, "res": 10, "agi": 11, "undead": true}

const ORDER := ["aldo", "lyra", "teo", "andilla"]     # ordem fixa da rodada

# Sorteios: a cena passa randf() (0 a 1) e a regra converte na faixa. "dmg" para golpes e magias de ataque,
# "soft" para cura, combo, badalada e dobre.
const ROLL := {"dmg": Vector2(0.88, 1.12), "soft": Vector2(0.9, 1.1)}

static func roll(kind: String, r: float) -> float:
	return lerpf(ROLL[kind].x, ROLL[kind].y, r)

static func stat(hero_id: String, lv: int, key: String, bonus := 0) -> int:
	var d: Dictionary = HEROES[hero_id]
	return int(floor(d.base[key] + d.grow[key] * (lv - 1))) + bonus

## Máximo de um atributo com o bônus de equipamento (`bonus` é {chave: valor}). Batalha e Game usam o mesmo.
static func max_stat(hero_id: String, lv: int, key: String, bonus: Dictionary) -> int:
	return stat(hero_id, lv, key, int(bonus.get(key, 0)))

static func cut_pct(points: float) -> float:
	var p := maxf(0.0, points)
	return GUARD_MAX * p / (p + GUARD_HALF)

static func guard_cut(points: float) -> float:
	return 1.0 - cut_pct(points) / 100.0

static func phys_dmg(atk: float, def: float, power := 1.0, v := 1.0) -> int:
	return maxi(1, roundi(atk * power * v * guard_cut(def)))

static func mag_dmg(raw: float, res: float) -> int:
	return maxi(1, roundi(raw * guard_cut(res)))

const HOLY_UNDEAD := 1.5       # Luz Sagrada contra morto-vivo (era 2,0: a Luz era o maior dano do jogo)

## Dano de uma habilidade de ataque (phys, mag ou holy). `v` é o sorteio de 0.88 a 1.12.
static func skill_damage(skill: Dictionary, atk: float, mag: float, target_def: float, target_res: float, target_undead: bool, v := 1.0) -> int:
	match skill.kind:
		"phys":
			return phys_dmg(atk, 0.0 if skill.get("pierce", false) else target_def, skill.power, v)
		"mag", "holy":
			var d := mag_dmg((mag * skill.power + skill.base) * v, target_res)
			if skill.kind == "holy" and target_undead:
				d = int(d * HOLY_UNDEAD)
			return d
	return 0

static func heal_amount(skill: Dictionary, mag: float, v := 1.0) -> int:
	return maxi(1, roundi((mag * skill.power + skill.base) * v))

# ---------- o Sineiro: ciclo de golpes e previsão ----------
# Calmo: golpe, dobre, golpe, badalada. Furioso (abaixo de RAGE_FRAC): golpe, dobre, badalada, mais curto.
const BOSS_CYCLE := ["hit", "drain", "hit", "bell"]
const BOSS_CYCLE_RAGE := ["hit", "drain", "bell"]
const RAGE_FRAC := 0.4

static func boss_move(step: int, enraged: bool) -> String:
	var c: Array = BOSS_CYCLE_RAGE if enraged else BOSS_CYCLE
	return c[step % c.size()]

## Estado do chefe entre turnos: posição no ciclo e se já está furioso.
## `frozen`: o Gelo tirou a próxima vez dele; `thawed`: acabou de descongelar e resiste ao frio por uma rodada.
static func boss_state() -> Dictionary:
	return {"step": 0, "enraged": false, "frozen": false, "thawed": false}

## Gelo: o chefe perde a próxima vez e o golpe anunciado só vem depois (a previsão não muda). Não acumula, e logo
## depois de descongelar ele resiste, para o Gelo não travar o chefe toda rodada. Devolve se congelou.
static func can_freeze(state: Dictionary) -> bool:
	return not state.frozen and not state.thawed

static func freeze(state: Dictionary) -> bool:
	if not can_freeze(state):
		return false
	state.frozen = true
	return true

## Turno do chefe: devolve o golpe já anunciado (o primeiro da previsão, que nunca muda depois de mostrado)
## e avança o estado. Se a vida caiu abaixo de RAGE_FRAC, ele fica furioso e o ciclo novo começa do zero
## no turno seguinte: a fúria só muda os ícones que vêm depois.
static func boss_turn(state: Dictionary, hp_frac: float) -> String:
	if state.frozen:                  # perde a vez: nem o ciclo nem a fúria andam, a previsão continua certa
		state.frozen = false
		state.thawed = true
		return "frozen"
	state.thawed = false
	var move := boss_move(state.step, state.enraged)
	if not state.enraged and hp_frac < RAGE_FRAC:
		state.enraged = true
		state.step = 0
	else:
		state.step += 1
	return move

const RAGE_MULT := 1.25          # furioso, todo golpe do chefe sai 25% mais forte
const BELL_RAW := 34.0           # Badalada: dano mágico em todos
const DRAIN_RAW := 41.0          # Dobre fúnebre: dano mágico em um, e o chefe se cura
const DRAIN_HEAL := 1.0          # o dobre devolve ao chefe todo o dano que causa

static func boss_atk(base_atk: float, enraged: bool) -> float:
	return base_atk * (RAGE_MULT if enraged else 1.0)

static func boss_hit_damage(def: float, enraged: bool, v := 1.0) -> int:
	return phys_dmg(boss_atk(SINEIRO.atk, enraged), def, 1.0, v)

static func bell_damage(res: float, enraged: bool, v := 1.0) -> int:
	return mag_dmg(BELL_RAW * v * (RAGE_MULT if enraged else 1.0), res)

static func drain_damage(res: float, v := 1.0) -> int:
	return mag_dmg(DRAIN_RAW * v, res)

static func drain_heal(dmg: int) -> int:
	return int(dmg * DRAIN_HEAL)

## Dano que o herói recebe de fato: defender corta pela metade, e bloquear no tempo certo corta outra metade.
static func taken(dmg: int, defending: bool, blocked := false) -> int:
	for cut in [defending, blocked]:
		if cut:
			dmg = maxi(1, dmg / 2)
	return dmg

## Energia depois de uma ação ("attack", "defend" ou "hurt"). Só Aldo e Andilla têm energia; apanhar só enche a do Aldo.
static func energy_after(hero_id: String, en: int, reason: String) -> int:
	if not HEROES[hero_id].energy or (reason == "hurt" and hero_id != "aldo"):
		return en
	return mini(ENERGY.max, en + int(ENERGY[reason]))

const CHARGE_BONUS := 0.3        # dano extra com a carga cheia (segure confirm)

static func charged(dmg: int, full: float) -> int:
	return int(dmg * (1.0 + CHARGE_BONUS * full))

## Ataque básico de um herói no Sineiro. `timed`: apertou no impacto.
static func attack_damage(atk: float, v := 1.0, timed := false) -> int:
	return phys_dmg(atk, SINEIRO.def, 1.0 + (TIMED_BONUS if timed else 0.0), v)

# ---------- ação no tempo certo (ataque e bloqueio, como em Sea of Stars) ----------
const TIMED_EARLY_MS := 60       # janela de 150 ms: um pouco antes do impacto e um pouco mais depois,
const TIMED_LATE_MS := 90        # porque a imagem chega à tela com atraso e quem aperta tende a atrasar
const TIMED_BONUS := 0.5         # ataque no tempo certo: +50% de dano e +1 ponto de combo
const AUTO_TIMED := 0.5          # o --auto acerta metade, para o balanceamento valer para quem joga razoável

## O aperto valeu? `press_ms` é o primeiro aperto desde que a ação começou (-1 se nenhum); só ele conta.
static func timed_ok(press_ms: int, impact_ms: int) -> bool:
	return press_ms >= 0 and press_ms >= impact_ms - TIMED_EARLY_MS and press_ms <= impact_ms + TIMED_LATE_MS

static func can_pay(skill: Dictionary, mp: int, en: int) -> bool:
	return (mp if skill.cost_kind == "mp" else en) >= skill.cost

# ---------- combo (pontos do grupo, como em Sea of Stars) ----------

const COMBO_MAX := 8
const COMBOS := {
	"corte": {"name": "Corte Duplo", "cost": 3, "members": ["aldo", "andilla"], "power": 1.2, "desc": "Aldo e Andilla atacam juntos."},
	"escudo": {"name": "Escudo de Luz", "cost": 4, "members": ["teo", "lyra"], "heal": 0.4, "desc": "Cura o grupo e levanta a guarda de todos."},
}

# Pontos só de ataque básico (e de acerto no tempo certo): defender, técnica, magia e cura não dão nada.
const COMBO_FROM := {"attack": 1, "timed": 1}

static func combo_gain(points: int, amount := 1) -> int:
	return clampi(points + amount, 0, COMBO_MAX)

static func combo_points(action: String) -> int:
	return int(COMBO_FROM.get(action, 0))

## Combos que aparecem no menu deste herói: só os de que ele participa.
static func combos_of(hero_id: String) -> Array:
	return COMBOS.keys().filter(func(id): return hero_id in COMBOS[id].members)

static func combo_ready(id: String, points: int, alive: Array) -> bool:
	var c: Dictionary = COMBOS[id]
	return points >= c.cost and c.members.all(func(m): return m in alive)

static func combo_damage(atk_a: float, atk_b: float, target_def: float, v := 1.0) -> int:
	var p: float = COMBOS.corte.power
	return phys_dmg(atk_a, target_def, p, v) + phys_dmg(atk_b, target_def, p, v)

static func combo_heal(hpmax: int) -> int:
	return int(hpmax * float(COMBOS.escudo.heal))

## Próximos golpes do chefe, para mostrar acima dele. O primeiro é o que ele vai fazer de fato.
static func boss_forecast(state: Dictionary, n := 3) -> Array:
	var out := []
	for i in n:
		out.append(boss_move(state.step + i, state.enraged))
	return out

# ---------- jogada automática (--auto e simulador) ----------
const AUTO_SHIELD_BELOW := 0.6   # Escudo de Luz quando 2 ou mais estão abaixo disto
const AUTO_HEAL_BELOW := 0.45    # Cura em quem está abaixo disto
const AUTO_POTION_BELOW := 0.3   # Poção em quem está abaixo disto, se o herói não tem Cura para pagar

## Vivos na ordem da rodada. `party`: id -> {hp, hpmax, mp, en}.
static func alive_ids(party: Dictionary) -> Array:
	return ORDER.filter(func(id): return party.has(id) and party[id].hp > 0)

## O que o herói `hid` faz no --auto: Pena Vital em quem caiu, Escudo se 2 ou mais estão fracos, Corte Duplo
## sempre que dá, Cura em quem está mal (ou Poção, se não tem Cura), a primeira técnica que dá para pagar, senão ataque.
static func auto_choice(hid: String, party: Dictionary, combo: int, boss := {}, bag := {}) -> Dictionary:
	var alive := alive_ids(party)
	if E.usable(bag, "pena", party, ORDER):
		return {"type": "item", "id": "pena", "target": E.targets("pena", party, ORDER)[0]}
	var below := func(f: float) -> Array: return alive.filter(func(id): return party[id].hp < party[id].hpmax * f)
	var mine := combos_of(hid)
	if "escudo" in mine and below.call(AUTO_SHIELD_BELOW).size() >= 2 and combo_ready("escudo", combo, alive):
		return {"type": "combo", "id": "escudo"}
	if "corte" in mine and combo_ready("corte", combo, alive):
		return {"type": "combo", "id": "corte"}
	var h: Dictionary = party[hid]
	var hurt: Array = below.call(AUTO_HEAL_BELOW)
	var can_cure: bool = HEROES[hid].skills.any(func(sid): return SKILLS[sid].kind == "heal" and can_pay(SKILLS[sid], h.mp, h.en))
	var low: Array = below.call(AUTO_POTION_BELOW)
	if not can_cure and not low.is_empty() and int(bag.get("pocao", 0)) > 0:
		return {"type": "item", "id": "pocao", "target": low[0]}
	# Gelo só quando a próxima é a Badalada e o chefe pode congelar; fora isso, a primeira técnica que dá para pagar
	var bell_next: bool = not boss.is_empty() and can_freeze(boss) and boss_forecast(boss)[0] == "bell"
	for sid in HEROES[hid].skills:
		if SKILLS[sid].get("delay", false) and bell_next and can_pay(SKILLS[sid], h.mp, h.en):
			return {"type": "skill", "id": sid}
	for sid in HEROES[hid].skills:
		var s: Dictionary = SKILLS[sid]
		if not can_pay(s, h.mp, h.en):
			continue
		if s.kind == "heal":
			if not hurt.is_empty():
				return {"type": "skill", "id": sid, "target": hurt[0]}
			continue
		return {"type": "skill", "id": sid}
	return {"type": "attack"}
