# Cloud-First + IoT Edge

Fonte de verdade da sobrevivência do dino: **Supabase (Postgres RPCs + Edge Functions + cron)**.

## Deprecated (modo manutenção)

| Peça | Status |
|------|--------|
| Express em `src/` (mock / legacy) | Só LLM/voz no pack Mac. **Não** tick de decay. |
| Electron survival em `apps/desktop` | UI legada. Sem features novas de fome/humor/missões. |
| Decay local iOS/desktop | Cache offline apenas; cloud é autoritativa. |

## Deploy Edge Functions

```bash
# 1) Access token: https://supabase.com/dashboard/account/tokens
export SUPABASE_ACCESS_TOKEN=sbp_...

# 2) Deploy
./scripts/deploy-edge-functions.sh
```

CLI local (se não estiver no PATH): `.tools/supabase`.

## Registrar ESP32

```bash
# JWT do usuário (access_token):
curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"SEU@EMAIL","password":"SUA_SENHA"}' | jq -r .access_token

# Registrar device (imprime deviceKey uma vez):
node scripts/register-esp32.mjs --token='eyJ...' --label=mesa
```

Ou REST Client: [`scripts/iot-register.http`](../scripts/iot-register.http).

## Cron de survival

- **pg_cron:** job `companion-tick-decay` a cada 15 min → `SELECT companion_tick_all()` (já agendado se a extension existir).
- **Fallback:** [`.github/workflows/companion-tick.yml`](../.github/workflows/companion-tick.yml) — secrets `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.

## Contrato IoT (ESP32)

Base: `https://<PROJECT>.supabase.co/functions/v1`

| Manifesto | Edge Function | Auth |
|-----------|---------------|------|
| `POST /api/iot/presence` | `POST /iot-presence` | `X-Device-Key` |
| `POST /api/iot/interact` | `POST /iot-interact` | `X-Device-Key` |

### Presence

```json
{ "rssi": -62, "ts": 1710000000 }
```

- RSSI ≥ limiar (default −75) → `presenceStatus = present`, decay ativo.
- RSSI fraco / sem ping > 15 min → `expedition` (decay congelado).

### Interact

```json
{ "kind": "pet" }
```

`pet` → `POKE`; `attention` → `TEASE`.

### Pairing

Com JWT do usuário: `POST /iot-register` body `{ "label": "mesa" }` → retorna `deviceKey` **uma vez**. Guarde no firmware.

## Survival (servidor)

- `companion_apply_decay(id)` — no-op se `decayFrozen` / expedition / away.
- `companion_apply_interaction(id, type)` — deltas autoritativos.
- `companion_tick_all()` — cron a cada ~10 min (pg_cron ou Edge `tick-decay`).
- Spec numérica: `src/survivalSpec.ts` (espelha testes em `tests/companion-logic`).

## iOS passivo

- HealthKit → `POST /steps-ingest` (passos → energia).
- Live Activity contínua = status cloud (energy / mood / presence).
