# Crônicas de Eterra (versão Godot, para a Steam)

RPG em **Godot 4.7** (GL Compatibility), com visual inspirado em Sea of Stars (luz 2D colorida sobre pixel art,
cenários com profundidade) e estrutura inspirada em Phantasy Star IV. Meta: lançar na Steam.
Este projeto é a evolução do jogo em JS puro que está em `/home/dani/games/dungeon-rpg` (continua no ar no GitHub
Pages e serve de referência de falas e mecânicas). **Não publicar nada daqui no GitHub sem o Daniel pedir.**

## Regras
- Código e commits em inglês; textos para o jogador em português, **sem travessão**.
- DRY e KISS. Lógica nova com teste. Saves não podem quebrar depois do lançamento.
- Fé como em Tolkien e Lewis: nunca sermão, nunca do lado do vilão de forma negativa. Detalhes em `docs/mundo/canone.md`.
- Não copiar assets nem composições do Sea of Stars; é só referência de estilo.
- **A Steam exige declarar conteúdo gerado por IA** (arte, música). Registrar o que veio do Pixel Lab.

## Celular (decidido em 12/11: é plano de lançamento, Google Play depois da Steam)
- O jogo nunca lê tecla direto: usa `Controls` (`scripts/controls.gd`). Teclado, controle e toque chamam as mesmas ações
  (`move_*`, `confirm`, `cancel`, `menu`). Ação nova entra em `Controls.KEYS`, não num script de cena.
- Interface de toque em `scripts/touch_controls.gd` (joystick à esquerda, A/B à direita, menu no canto). Aparece no
  primeiro toque e some com teclado ou controle. `--touch` força na área de trabalho.
- Botões e alvos de toque com pelo menos 44 px na tela de 640x360. Texto legível em celular.
- Telas mais compridas que 16:9: `stretch/aspect = expand`, a câmera mostra mais cenário, nunca barras pretas.
- Orçamento de desempenho em celular: poucas luzes 2D (`MAX_LIGHTS_TOUCH`), menos partículas, texturas pequenas.
- Salvar sempre pela camada única (`Save`, `scripts/save.gd`), que funciona na Steam, no Android e no navegador.
- Ordem: Steam, depois Android (Godot exporta direto), iOS por último (precisa de Mac com Xcode e US$ 99 por ano).

## Ferramentas
- Godot: `/home/dani/tools/godot/godot` (4.7.2). Templates de exportação web, Linux e Windows instalados.
- Testes de lógica: `godot --headless --path . --script tests/run_tests.gd`.
- Rodar e tirar captura sem tela: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 -- --shot=<arquivo.png>`.
- Importar assets novos: `godot --headless --import`.
- Build web: `godot --headless --path . --export-release "Web" build/web/index.html`, servir com
  `cd build/web && python3 -m http.server 8060` e abrir `http://localhost:8060` no Windows.
- Arte: Pixel Lab (MCP `pixellab`). 9 personagens já criados (hi-bit 56x72, 4 direções). O `pixelart_workbench` é grátis.

## Estrutura
- `scripts/valmor.gd`: a fatia vertical (Valmor à noite). `scripts/valmor_lights.json`: posições das luzes (pixels da imagem gerada).
- `scripts/valmor_rules.gd`: paredes, porta, baús, moradores (lugar, cena, sprite provisório), o "!" e quando a fatia acaba (falar com o Tobias depois do Sineiro).
- `scripts/battle.gd` + `scenes/battle.tscn`: batalha contra o Sineiro. `scripts/battle_rules.gd`: regras puras (testadas), portadas de `src/party.js` do jogo em JS. `scripts/game.gd`: estado entre cenas (grupo, flags, moedas, bolsa, opções, `Game.goto`). `scripts/fx.gd`: luz, sombra e quadros dos heróis.
- Autoloads: `Controls` (entrada; `Controls.prompt(ação)` dá o rótulo da tecla, botão ou toque em uso), `Game`, `Dialogue`
  (`await Dialogue.play("cena")`, falas em `data/dialogue/*.json`, regras em `dialogue_rules.gd`; quem chama respeita
  `is_open()`), `Audio` (som pelo nome, regras em `audio_rules.gd`) e `Save` (um arquivo `user://save.json` com `version`;
  formato e migração em `save_rules.gd`; flags e IDs de item e baú nunca mudam de nome).
- `scripts/ui.gd`: margem segura, painel, menus, ícones desenhados em código. `scripts/pause_menu.gd`: pausa (Continuar,
  Opções, Tela cheia, Sair). `scripts/economy_rules.gd`: itens, moedas, baús e loja; `scripts/shop.gd`: loja da Dora.
  `scripts/title.gd`: título.
- Testes de batalha sem tela: `godot --headless --path . --scene res://scenes/battle.tscn -- --auto` (joga sozinho em velocidade alta e imprime `RESULT`). `--fast` acelera a batalha manual; `--dev-battle` na Valmor vai direto à luta.
- `assets/heroes/<herói>/`: rotações e animações do Pixel Lab. `assets/valmor_night.png`: cenário.
- `docs/mundo/`: o cânone (privado, no `.gitignore`). Ler `canone.md`, `panorama.md` e `personagens.md` antes de qualquer trabalho de história.

## Pontos fracos conhecidos
- Escala de pixel misturada: cenário em 3x e heróis em 1x. Gerar cenários já na escala dos heróis.
- Colisão provisória (retângulos por cima da imagem).
- Diálogo, escolhas, save, itens, loja, baús e moradores prontos. Retratos dos heróis (`assets/portraits/`) e moradores (`assets/npcs/`, só parados, 4 direções) já são do Pixel Lab;
  moradores sem retrato de diálogo. Som provisório. Batalha sem Elos nem fuga.
- Batalha em visão de baixo para cima (como Sea of Stars): grupo embaixo à esquerda, chefe no alto à direita, piso visto de cima (`assets/battle/arena_bg.png`, `sineiro_td.png`). A versão lateral antiga ficou em `assets/battle/crypt_bg.png` e `sineiro.png`.
- Cenários gerados trazem uma borda roxa: a arte útil é recortada por `CROP` e o fundo da cripta é ampliado 1,43x (escala não inteira).
