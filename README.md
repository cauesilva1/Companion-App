# Companion App

<p align="center">
  <img src="docs/preview/hero.png" alt="Companion App — dinos no céu" width="900" />
</p>

<p align="center">
  <strong>Um companion virtual estilo Tamagotchi para o desktop</strong><br/>
  Popup pixel art que vive no canto da tela, reage a você,<br/>
  escuta a música que está tocando e conversa com personalidade.
</p>

<p align="center">
  macOS (Electron) + API Node local
</p>

---

## Os dinos

Cada personalidade do quiz nasce um dino diferente:

<p align="center">
  <img src="docs/preview/dinos-lineup.png" alt="Doux, Vita, Olaf, Mort e Kuro" width="720" />
</p>

| | | | | |
|:---:|:---:|:---:|:---:|:---:|
| <img src="docs/preview/doux.png" width="96" /><br/>**Doux**<br/>curioso | <img src="docs/preview/vita.png" width="96" /><br/>**Vita**<br/>carinhoso | <img src="docs/preview/olaf.png" width="96" /><br/>**Olaf**<br/>preguiçoso | <img src="docs/preview/mort.png" width="96" /><br/>**Mort**<br/>zoeiro | <img src="docs/preview/kuro.png" width="96" /><br/>**Kuro**<br/>misterioso |

<p align="center">
  <img src="docs/preview/egg.png" alt="Ovo do companion" width="72" /><br/>
  <sub>Começa no ovo — o hatch só depois do quiz</sub>
</p>

---

## Céu por hora do dia

Amanhecer · dia · entardecer · noite · tempestade

<p align="center">
  <img src="docs/preview/skies-strip.png" alt="Céus do companion" width="900" />
</p>

---

## O que ele faz

- **Quiz de personalidade** — responde umas perguntas e nasce um dino
- **Animações pixel** — idle, corrida, pulo, dash, poke, chat e nascimento do ovo
- **Céu dinâmico** — muda com a hora (+ clima do dia)
- **Spotify / Apple Music** — detecta a faixa (se o app já estiver aberto) e comenta
- **Tray + minimizar** — some pro tray e manda notificações personalizadas
- **Chat com LLM** — NVIDIA NIM (cascata) → OpenRouter → voz local

Design: widget arredondado, dino à esquerda no céu, painel de ações à direita.

---

## Estrutura

```
companion-backend/
├── src/                 # API Express (cérebro)
├── prisma/              # schema (opcional; mock sem DB)
├── apps/desktop/        # popup Electron
│   ├── electron/        # main / preload / Spotify
│   └── renderer/        # UI, sprites, sons, céus
├── docs/preview/        # imagens do README
└── data/                # sessão local (gitignored)
```

---

## Setup

**Requisitos:** Node.js 20+, macOS (para o desktop + mídia).

```bash
git clone https://github.com/cauesilva1/Companion-App.git
cd Companion-App
npm install
cp .env.example .env
```

Edite o `.env` com suas chaves (nunca commite esse arquivo):

| Variável | Onde pegar |
| --- | --- |
| `NVIDIA_API_KEY` | [build.nvidia.com](https://build.nvidia.com) |
| `OPENROUTER_API_KEY` | [openrouter.ai/keys](https://openrouter.ai/keys) |
| `HUGGINGFACE_API_KEY` | opcional |
| `DATABASE_URL` | deixe vazio para modo mock (JSON local) |

No desktop, se precisar:

```bash
cp apps/desktop/.env.example apps/desktop/.env
# API_URL=http://127.0.0.1:3333
```

---

## Rodar

```bash
npm run dev
```

Sobe a API em `http://127.0.0.1:3333` e abre o Electron quando `/health` responder.

Só API:

```bash
npm run dev:api
```

---

## Modelos NVIDIA (cascata)

Ordem padrão (configurável em `NVIDIA_MODELS`):

1. `openai/gpt-oss-20b`
2. `moonshotai/kimi-k3`
3. `nvidia/nemotron-3-super-120b-a12b`
4. `deepseek-ai/deepseek-v4-pro-0813`

Se um falhar, tenta o próximo; depois OpenRouter; por fim fala local.

---

## Atalhos e tray

- `Cmd+Shift+C` — mostra / esconde
- **−** / **×** — minimizar pro tray
- Clique no tray ou na notificação — volta
- Spotify: **Ajustes → Privacidade → Automação** (permitir controlar Spotify)

---

## API (resumo)

| Método | Rota | Uso |
| --- | --- | --- |
| `POST` | `/companion` | cria companion |
| `GET` | `/companion/:id/state` | estado + humor |
| `POST` | `/companion/:id/interact` | Play / Poke / Chat |
| `GET` | `/companion/:id/feed` | histórico |

---

## Créditos de arte / som

Ver [apps/desktop/ATTRIBUTION.md](apps/desktop/ATTRIBUTION.md):

- Dinos — [arks / Dino Characters](https://arks.itch.io/dino-characters)
- Céus — Craftpix / Free Game Assets
- SFX — Prehistoric Sound Pack

---

## Segurança

- `.env` está no `.gitignore` — **não** suba chaves reais
- Use só placeholders em `.env.example`
- Sessão local e `data/` também ficam fora do git

Se uma chave vazou em algum momento, **revogue e gere outra** no provedor.

---

## Licença

Projeto pessoal / experimental. Assets de terceiros seguem as licenças dos respectivos autores (ver ATTRIBUTION).
