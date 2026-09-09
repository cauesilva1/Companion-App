# Life Modes + Contexto Externo (Cloud-First)

Complementa [`CLOUD_FIRST.md`](./CLOUD_FIRST.md). A sobrevivência continua nas RPCs; estes modos dizem **como o companion se comporta** (LLM / feed / hibernação).

## Os 3 modos (`LifeMode`)

| Modo | Gatilho (heurística cloud) | Energia / decay | Feed |
|------|----------------------------|-----------------|------|
| **indoor** | Em casa (SSID) ou fora de work/sleep | **Recupera** ~3 energia/h (grace 15 min) | `rest` — sofá / regenerando |
| **work** | Fora de casa, horário comercial, passos | **Gasta** ~3.5/h + fadiga por passos | `work` — rua / cansaço |
| **sleep** | A partir das **23h** (hora local). Só **acorda** se o app abrir **depois das 6h**. Abrir antes das 6h → continua sleep (sonolento) | **Congela** (`decayFrozen`) | `dream` — sonhos; chat pré-6h com tom de meio dormindo |

### Sono como pessoa

1. **23h–5h59** → entra / permanece em `sleep` (não precisa estar carregando).
2. **Abrir o app antes das 6h** → continua `sleep`; UI/LLM em tom sonolento (“Meio dormindo”).
3. **Abrir o app ≥ 6h** (`appForeground=true`) → acorda para `indoor` ou `work` + `morningThought`.
4. Ingest em background **não** acorda sozinho depois das 6h — precisa do foreground.

`LifeMode` dita `presenceStatus` (sem ESP32/RSSI):

| LifeMode | presenceStatus | decayFrozen |
|----------|----------------|-------------|
| indoor | present | false |
| work | away | false |
| sleep | expedition | **true** (modo sonhos; não é mais “expedição física”) |

Presença física por hardware foi **descontinuada**.

### Passos (HealthKit → `steps_ingest`)

| Modo | Efeito |
|------|--------|
| work | Fadiga: −1 energia / 400 passos (cap 30/dia) |
| indoor | Recarga leve: +1 / 750 passos (cap 12/dia) |
| sleep | Ignora passos na energia |

### Anti-spam do feed

- SQL `companion_append_thought`: cooldown 3 min (mood/dream/rest/work), 5 min (music/gaming)
- iOS: intervalo 3–6 min por modo; sem burst no boot
- Cron `companion_tick_all`: ~1/3 dos ticks gera linha de modo (respeita cooldown)
## Telemetria autônoma (sem Settings)

| Gatilho | Onde | Ação |
|---------|------|------|
| Boot / companion na cloud | `bootstrap` | `BackgroundTelemetry.runForegroundIngest()` |
| Voltar ao foreground | `scenePhase == .active` | passos + Spotify refresh + `ingestNow` + reload feed |
| Ir ao background | `scenePhase` | `ingestNow` best-effort |
| Loop do feed | `startThoughtFeed` | `ingestNow` periódico enquanto ativo |
| Troca de faixa Spotify | notificação NowPlaying | `ingestNow` |

> `BGAppRefreshTask` foi **desligado** (causava SIGKILL no launch em alguns profiles). Telemetria roda no foreground/background do ciclo de vida SwiftUI.

Settings (“Salvar contexto”) continua só como ação manual opcional.

## Xbox (OpenXBL)

- Secret Edge: `OPENXBL_API_KEY`
- Gamertag: `Companion.xboxGamertag` (Settings)
- Poll leve em `context-ingest` / `companion-state` **quando indoor**
- Campo: `gamingStatus` (ex.: `online · Forza Horizon 5`)

## Mídia

- Spotify/NowPlaying no device → `mediaHint` no ingest
- Indoor: entra no tom do feed / system prompt

## Pensamento matinal + feed cloud

1. Entrada em `sleep` → cloud grava `morningThought` + row em `CompanionThought`
2. Primeira abertura do app → sync via `companion-state` / `thoughts`
3. `ackMorning: true` no ingest limpa o texto pendente em `Companion.morningThought`

Tabela autoritativa: **`CompanionThought`** (Edge `GET|POST /thoughts`).

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
