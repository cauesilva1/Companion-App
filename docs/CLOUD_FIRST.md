# Cloud-First (sem IoT ESP32)

Fonte de verdade da sobrevivência do dino: **Supabase (Postgres RPCs + Edge Functions + cron)**.  
Presença / hibernação vêm dos **Life Modes** via telemetria iOS (`context-ingest`) — ver [`LIFE_MODES.md`](./LIFE_MODES.md).

## Deprecated (modo manutenção)

| Peça | Status |
|------|--------|
| Express em `src/` (mock / legacy) | Só LLM/voz no pack Mac. **Não** tick de decay. |
| Electron survival em `apps/desktop` | UI legada. Sem features novas de fome/humor/missões. |
| Decay local iOS/desktop | Cache offline apenas; cloud é autoritativa. |
| **IoT ESP32 / RSSI** (`iot-register`, `iot-presence`, `iot-interact`) | **Removido.** Não usar. |

## Deploy Edge Functions

```bash
export SUPABASE_ACCESS_TOKEN=sbp_...
./scripts/deploy-edge-functions.sh
```

Funções ativas: `companion-state`, `context-ingest`, `steps-ingest`, `thoughts`, `tick-decay`.

CLI local (se não estiver no PATH): `.tools/supabase`.

## Cron de survival

- **pg_cron:** job `companion-tick-decay` a cada 15 min → `SELECT companion_tick_all()`.
- **Fallback:** [`.github/workflows/companion-tick.yml`](../.github/workflows/companion-tick.yml).

## Survival (servidor)

- `companion_apply_decay(id)` — por `lifeMode`:
  - **indoor** → recupera energia; afeto cai bem devagar
  - **work** → gasta energia (tempo + passos recentes)
  - **sleep** / `decayFrozen` → no-op físico
- `companion_apply_interaction(id, type)` — deltas autoritativos.
- `companion_tick_all()` — cron; decay + chance de thought `rest`/`work`/`dream`
- `companion_ingest_context(...)` — lifeMode + `presenceStatus` espelhado:
  - `indoor` → `present` (recupera energia)
  - `work` → `away` (consome energia)
  - `sleep` → `expedition` + `decayFrozen=true` (sonhos no feed)
- Spec: `src/survivalSpec.ts`

## iOS passivo

- HealthKit → `POST /steps-ingest`
- Contexto Wi‑Fi / carga / hora → `POST /context-ingest`
- Spotify → `mediaHint`; Xbox (OpenXBL) → `gamingStatus` em indoor
- Feed autoritativo → tabela `CompanionThought` + Edge `GET|POST /thoughts`
- Home = feed de pensamentos; widgets → `companion://feed`
