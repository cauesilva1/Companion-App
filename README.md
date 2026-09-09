# Companion

<p align="center">
  <img src="docs/preview/ios-widget-medium.jpg" alt="Widget Companion — Jaozinho no céu" width="720" />
</p>

<p align="center">
  <strong>Um companion pixel art que vive no seu iPhone</strong><br/>
  Personalidade, céu dinâmico, pensamentos no widget<br/>
  e sobrevivência na nuvem — não só um chat.
</p>

<p align="center">
  <code>iOS · Supabase · Widgets · Life Modes</code>
</p>

---

## O que é

O Companion nasce de um quiz, ganha um dino e uma voz. No dia a dia ele:

- recupera energia no sofá, gasta energia fora de casa
- comenta a vida com pensamentos curtos (feed + widget)
- muda o céu com a hora e o clima real
- guarda convivência, títulos e badges no perfil

A fonte de verdade da vida do pet é o **Supabase** (Postgres + Edge Functions + cron).  
O app iOS é **passivo**: mostra estado, manda contexto e conversa — sem “simular” decay local.

> Detalhes de arquitetura: [`docs/CLOUD_FIRST.md`](docs/CLOUD_FIRST.md) · life modes: [`docs/LIFE_MODES.md`](docs/LIFE_MODES.md)

---

## No iPhone

<p align="center">
  <img src="docs/preview/ios-home.jpg" alt="Home do Companion com feed de pensamentos" width="280" />
  &nbsp;&nbsp;
  <img src="docs/preview/ios-profile.jpg" alt="Perfil com convivência e badges" width="280" />
</p>

| Home | Perfil |
| --- | --- |
| Card do pet, energia / afeto, feed de pensamentos e chat | Horas no sofá, rua, sono, músicas, games, badges e títulos |

### Widgets (mesma plate do app)

<p align="center">
  <img src="docs/preview/ios-widget-small.jpg" alt="Widget small" width="220" />
  &nbsp;&nbsp;
  <img src="docs/preview/ios-widget-medium.jpg" alt="Widget medium" width="420" />
</p>

Home Screen e Lock Screen espelham o snapshot do App Group: stats, fala e **céu igual ao do app** (clima + hora).

Também há **Dynamic Island / Live Activity** para presença rápida fora do app.

---

## Os dinos

Cada personalidade do quiz nasce um dino diferente:

<p align="center">
  <img src="docs/preview/dinos-lineup.png" alt="Doux, Vita, Olaf, Mort e Kuro" width="720" />
</p>

| | | | | |
|:---:|:---:|:---:|:---:|:---:|
| <img src="docs/preview/doux.png" width="88" /><br/>**Doux**<br/>curioso | <img src="docs/preview/vita.png" width="88" /><br/>**Vita**<br/>carinhoso | <img src="docs/preview/olaf.png" width="88" /><br/>**Olaf**<br/>preguiçoso | <img src="docs/preview/mort.png" width="88" /><br/>**Mort**<br/>zoeiro | <img src="docs/preview/kuro.png" width="88" /><br/>**Kuro**<br/>misterioso |

<p align="center">
  <img src="docs/preview/egg.png" alt="Ovo" width="64" /><br/>
  <sub>Começa no ovo — o hatch só depois do quiz</sub>
</p>

---

## Céu dinâmico

Amanhecer · dia · entardecer · noite · tempestade · nublado · neve

O plate muda com **hora local** e **clima real** (Open-Meteo). App e widgets usam a mesma plate.

<p align="center">
  <img src="docs/preview/skies-strip.png" alt="Faixa de céus Craftpix" width="900" />
</p>

---

## Como funciona (visão rápida)

```mermaid
flowchart LR
  ios[iOS app / widgets]
  edge[Edge Functions]
  db[(Supabase Postgres)]
  ios -->|contexto: wifi, steps, mídia, clima| edge
  edge --> db
  db -->|estado, pensamentos, badges| ios
  cron[pg_cron tick] --> db
```

| Peça | Papel |
| --- | --- |
| **Life modes** | `indoor` / `work` / `sleep` — sofá regenera, rua gasta, sono congela decay |
| **Tick** | Cron aplica decay e pode soltar pensamentos |
| **Context ingest** | App manda presença, horário, clima, Now Playing… |
| **Badges** | Títulos de convivência + badges secretas (clima / madrugada / tempestade) |
| **Chat** | LLM com personalidade; fallback de voz local |

---

## Estrutura do monorepo

```
companion-backend/
├── apps/ios/            # SwiftUI — produto principal
├── supabase/functions/  # companion-state, context-ingest, steps, thoughts, tick-decay
├── prisma/              # schema + migrations / RPCs de survival
├── apps/desktop/        # Electron LEGADO (manutenção)
├── src/                 # Express LEGADO (LLM/voz no pack Mac)
└── docs/                # cloud-first, life modes, previews
```

---

## Começar

### iOS (caminho principal)

**Requisitos:** macOS, Xcode, iOS 16.2+.

```bash
git clone https://github.com/cauesilva1/Companion-App.git
cd Companion-App
./scripts/generate-ios-project.sh
open apps/ios/Companion.xcodeproj
```

No app: conta Supabase (email/senha). Detalhes em [`apps/ios/README.md`](apps/ios/README.md).

### Cloud (Supabase)

1. Auth email/senha no dashboard  
2. `npx prisma migrate deploy`  
3. Deploy das Edge Functions: `./scripts/deploy-edge-functions.sh`  
4. `.env` com `SUPABASE_URL` + `SUPABASE_ANON_KEY` (+ DB URLs para migrate)

Contrato: [`docs/CLOUD_FIRST.md`](docs/CLOUD_FIRST.md).

### Desktop / API local (legado)

```bash
npm install          # sempre na raiz
cp .env.example .env
npm run dev          # API + Electron
```

Útil para mock LLM/voz no Mac. **Não** é a fonte de survival.

---

## Variáveis úteis

| Variável | Uso |
| --- | --- |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | Clients (Auth + REST) |
| `DATABASE_URL` / `DIRECT_URL` | Migrations Prisma |
| `NVIDIA_API_KEY` / `OPENROUTER_API_KEY` | Chat LLM (legado / desktop) |

`.env` fica fora do git. Se alguma chave vazou, revogue.

---

## Créditos

Ver [`apps/desktop/ATTRIBUTION.md`](apps/desktop/ATTRIBUTION.md):

- Dinos — [arks / Dino Characters](https://arks.itch.io/dino-characters)
- Céus — Craftpix / Free Game Assets
- SFX — Prehistoric Sound Pack

---

## Licença

Projeto pessoal / experimental. Assets de terceiros seguem as licenças dos autores.
