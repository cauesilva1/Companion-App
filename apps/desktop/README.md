# Companion Electron — Popup Tamagotchi

Popup frameless sempre visível no canto inferior direito da tela. Consome a API do `companion-backend` e exibe o estado do companion com sprites animados pixel art, barras de status e botões de interação.

## Pré-requisitos

- Node.js 18+
- `companion-backend` rodando (ver README do backend)
- Um `COMPANION_ID` já criado no banco

## Setup

```bash
cd companion-electron

npm install

cp .env.example .env
# Edite .env com seus valores:
#   COMPANION_ID=<id do seu companion no Supabase>
#   API_URL=http://localhost:3333
```

## Rodar em desenvolvimento

```bash
npm run dev
```

Isso compila o TypeScript com `tsc` e abre o Electron. Para compilação em modo watch (requer dois terminais):

```bash
# Terminal 1 — watch TypeScript
npm run watch

# Terminal 2 — rodar o Electron após qualquer mudança compilada
npm start
```

## Build para distribuição

```bash
npm run dist
```

O instalador é gerado em `release/`.

## Estrutura

```
companion-electron/
├── electron/
│   ├── main.ts       # Processo principal: BrowserWindow, Tray, handlers IPC → HTTP
│   └── preload.ts    # Bridge segura (contextBridge) — expõe window.companion
├── renderer/
│   ├── index.html    # UI do popup
│   ├── style.css     # Pixel art, sprites por mood, animações
│   └── renderer.ts   # Lógica: poll, interações, feed, balão de fala
├── assets/
│   └── sprites/      # Coloque aqui PNGs reais de sprite por mood no futuro
├── .env.example
└── tsconfig.json
```

## Como funciona

### Arquitetura IPC

O renderer nunca acessa a rede diretamente. O fluxo é:

```
renderer.ts → window.companion.* → preload.ts (contextBridge) → ipcMain → main.ts → HTTP → backend
```

Isso segue as boas práticas de segurança do Electron (`contextIsolation: true`, sem `nodeIntegration`).

### Sprites por mood

Os 7 moods (`EXCITED`, `HAPPY`, `CONTENT`, `BORED`, `SLEEPY`, `SAD`, `LONELY`) são representados por sprites CSS placeholder com animações únicas. Para substituir por pixel art real:

1. Coloque os PNGs em `assets/sprites/<mood>.png`
2. Substitua o `::before` de cada `.sprite[data-mood="..."]` no `style.css` por `background-image: url(...)`

### Poll automático

O renderer chama `/companion/:id/state` a cada 60 segundos silenciosamente para manter o estado atualizado, igual ao comportamento esperado de um widget iOS.

### Notificação proativa

Se a energia cair abaixo de 10 durante um poll, o app dispara uma notificação nativa do sistema operacional.

## Variáveis de ambiente

| Variável | Descrição | Padrão |
|---|---|---|
| `COMPANION_ID` | ID do companion no banco | _(obrigatório)_ |
| `API_URL` | URL base do backend | `http://localhost:3333` |

## Próximos passos

- Sprites PNG reais por mood (pixel art profissional)
- Auth JWT: quando o backend tiver auth, adicione o token no header em `main.ts → fetchJSON`
- Notificações integradas ao cron do backend (webhook ou polling mais frequente)
- Widget iOS com Swift/WidgetKit consumindo a mesma API
