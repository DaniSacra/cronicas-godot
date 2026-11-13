# Origem do áudio (registro para a declaração de IA da Steam)

**Todos os arquivos desta pasta são PROVISÓRIOS** (decisão D3, caminho A, 13/11/2026). Para o lançamento a música
deve vir de compositor humano e os efeitos de biblioteca gravada (caminho C); quando um arquivo for trocado, atualizar
a linha dele aqui e em `docs/conteudo-ia.md`.

## Como foram feitos

- **Origem:** sintetizador portado do jogo antigo em JS (`/home/dani/games/dungeon-rpg/src/audio.js`, partituras em
  `dungeon-rpg/docs/som/trilhas-2026-11-05.md` e propostas de `avaliacao-2026-11-07.md`), reescrito como renderizador
  offline em Python: `tools/audio/render.py` (só biblioteca padrão, saída determinística, sementes fixas).
- **Feito com ajuda de IA: sim.** Melodias, harmonias, timbres, efeitos e o próprio renderizador foram escritos com
  um assistente de IA (Claude: os commits de `audio.js` têm `Co-Authored-By: Claude`; o porte e os efeitos novos
  foram feitos pelo agente audio-designer em 13/11/2026). Declarar na Steam como conteúdo pré-gerado.
- **Pixel Lab: nada.** O Pixel Lab não gera som; nenhum arquivo desta pasta veio dele.
- **Nenhuma amostra gravada, nenhum arquivo de terceiros.** Tudo é síntese (osciladores, ruído, filtros, eco).
- **Refazer:** `python3 tools/audio/render.py` (tudo) ou `--only nome1,nome2`; `--list` mostra os nomes. Precisa de
  `ffmpeg` com libvorbis para os `.ogg`.
- Formato: `.ogg` Vorbis q4, 44,1 kHz, estéreo para música, ambiente e jingles; `.wav` 16 bits mono 44,1 kHz para
  efeitos.

## Arquivos

Base: "porte" = partitura ou efeito do `audio.js` renderizado quase igual; "novo" = escrito agora no mesmo
sintetizador, seguindo o briefing de `docs/reviews/2026-11-13-audio-designer.md`. Todos: origem A, IA sim, provisório.

| Arquivo | Base | O que é |
|---|---|---|
| `music/valmor_noite.ogg` | porte (`town`) + parte B de `avaliacao-2026-11-07.md` | Valsa em Fá, 96 bpm, laço de 45 s |
| `music/chefe_sineiro.ogg` | porte (`boss`) + sino em Sol a cada 4 compassos | Chefe em Dó menor, 160 bpm, laço de 36 s. Sem coro, sem órgão |
| `amb/valmor_vento.ogg` | novo | Vento, duas rajadas, lareira ao longe; laço de 60 s |
| `amb/cripta_gotas.ogg` | novo | Ronco de pedra, gotas com eco, ar; laço de 60 s |
| `sfx/jingle/vitoria.ogg` | novo | Vitória contida (Láb, Sib, Dó maior), 5 s |
| `sfx/jingle/derrota.ogg` | novo (ideia de `gameover`/`bellFar`) | Badalada ao longe e acorde menor que se apaga, 5 s |
| `sfx/field/passo_neve_1..4.wav` | novo (ideia de `step('snow')`) | Passo na neve, 4 variações |
| `sfx/field/descer_cripta.wav` | novo (passos de `step('stone')`) | Laje arrastando e três passos descendo com eco (entrar na igreja velha) |
| `sfx/boss/sino_entrada.wav` | novo (ideia de `bossEncounter`) | Badalada grave de entrada, 5 s |
| `sfx/boss/badalada.wav` | novo (ideia de `bell`) | Duas badaladas e baque: ataque em todos |
| `sfx/boss/dobre.wav` | novo (ideia de `drain`) | Badalada abafada que desce de tom e brilho fraco |
| `sfx/boss/golpe_sino.wav` | novo | Sino batendo como arma |
| `sfx/boss/furia.wav` | novo | Sino sacudido em fúria, desafinado |
| `sfx/boss/ultimo_toque.wav` | novo (ideia de `bellFar`) | Sino rolando na pedra e um último toque longe |
| `sfx/battle/avanco.wav` | novo (passos de `flee`) | Corrida até o inimigo |
| `sfx/battle/volta.wav` | novo | Volta ao lugar |
| `sfx/battle/espada.wav` | novo (ideia de `slash`) | Corte de espada |
| `sfx/battle/impacto.wav` | porte (`hit`) + estalo | Lâmina acerta |
| `sfx/battle/impacto_magico.wav` | novo | Impacto mágico com brilho |
| `sfx/battle/dano_heroi.wav` | porte (`hurt`) + baque | Herói leva dano |
| `sfx/battle/queda.wav` | porte (`fall`) + baque e armadura | Herói cai |
| `sfx/battle/defender.wav` | porte (`defend`) + anel metálico | Defender |
| `sfx/skill/golpe_forte.wav` | novo | Aldo, Golpe Forte |
| `sfx/skill/passo_sombras_some.wav` | novo | Andilla some |
| `sfx/skill/passo_sombras_volta.wav` | novo | Andilla volta e golpeia |
| `sfx/skill/fogo.wav` | porte (`fire`) + explosão | Lyra, Fogo |
| `sfx/skill/gelo.wav` | porte (`ice`) + estilhaço | Lyra, Gelo |
| `sfx/skill/cura.wav` | porte (`heal`) com timbre de sino de vidro | Teo, Cura |
| `sfx/skill/luz_sagrada.wav` | porte (`holy`) + coro sem palavras sintetizado | Teo, Luz Sagrada (coro só do lado dos heróis) |
| `sfx/skill/carga.wav` | novo | Segure A: sobe em exatamente 1,0 s |
| `sfx/skill/carga_cheia.wav` | novo | Segure A: carga cheia |
| `sfx/ui/cursor.wav` | porte (`cursor`) | Cursor |
| `sfx/ui/confirmar.wav` | porte (`select`) | Confirmar |
| `sfx/ui/voltar.wav` | porte (`cancel`) | Voltar |
| `sfx/ui/negado.wav` | porte (`bump`) | Opção indisponível |
