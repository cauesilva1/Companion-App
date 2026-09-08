# Life Modes + Contexto Externo (Cloud-First)

Complementa [`CLOUD_FIRST.md`](./CLOUD_FIRST.md). A sobrevivência continua nas RPCs; estes modos dizem **como o companion se comporta** (LLM / feed / hibernação).

## Os 3 modos (`LifeMode`)

| Modo | Gatilho (heurística cloud) | Comportamento |
|------|----------------------------|---------------|
| **work** | Fora do Wi‑Fi residencial, horário comercial (~7–18), passos | Tom de esforço físico / campo / rua |
| **indoor** | Em casa (SSID casa) ou fora dos gatilhos de work/sleep | Sofá, recuperação, TV/som, Xbox |
| **sleep** | Madrugada (0–6), poucos passos, carregando/parado | `decayFrozen=true`, semente `morningThought` |

`LifeMode` dita `presenceStatus` (sem ESP32/RSSI):

| LifeMode | presenceStatus | decayFrozen |
|----------|----------------|-------------|
| indoor | present | false |
| work | away | false |
| sleep | expedition | **true** |

Presença física por hardware foi **descontinuada**.

## Pipeline

```
iOS ContextTelemetryService
  → POST /functions/v1/context-ingest
  → RPC companion_ingest_context
  → Companion.lifeMode / mediaHint / gamingStatus / morningThought
```

Settings iOS: SSID da casa + gamertag Xbox → `companion_set_home_context` (via Edge).

## Xbox (OpenXBL)

- Secret Edge: `OPENXBL_API_KEY`
- Gamertag: `Companion.xboxGamertag` (Settings)
- Poll leve em `context-ingest` / `companion-state` **quando indoor**
- Campo: `gamingStatus` (ex.: `online · Forza Horizon 5`)

## Mídia

- Spotify/NowPlaying no device → `mediaHint` no ingest
- Indoor: entra no tom do feed / system prompt

## Pensamento matinal

1. Entrada em `sleep` → cloud grava `morningThought` + `morningThoughtDayKey`
2. Primeira abertura do app → feed kind `morning` + widgets preferem essa linha
3. `ackMorning: true` no ingest limpa o texto na cloud

## Widgets

`CompanionHomeWidget` / `CompanionLockWidget` leem snapshot App Group (espelho do Supabase após sync) + ordem:

1. `morningThought` / pending
2. `ThoughtFeedStore.latestLine`
3. `WidgetSpeechStore`
4. `moodText`

Deep link: `companion://feed`.

## Deploy

```bash
npx prisma migrate deploy
# ou aplicar supabase/migrations/20260908120000_life_modes_context.sql
./scripts/deploy-edge-functions.sh   # inclui context-ingest
```

Spec numérica: `src/survivalSpec.ts` (`LIFE_*` constants).
