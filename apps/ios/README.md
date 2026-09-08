# Companion iOS

App SwiftUI + WidgetKit + Live Activity. **Cloud-First** (sobrevivência no Supabase).

## Modo passivo (atual)

1. Sync / decay / missões: Postgres RPCs + Edge Functions — ver [`docs/CLOUD_FIRST.md`](../../docs/CLOUD_FIRST.md).
2. HealthKit: passos → `POST /functions/v1/steps-ingest` (alimenta energia).
3. Live Activity / Dynamic Island: status contínuo (energy / presence), não só vignette ao sair.
4. IoT (ESP32): presence/interact na mesa — pairing via `iot-register`.

No Mac: `SUPABASE_URL` + `SUPABASE_ANON_KEY` no `.env` → `node scripts/sync-supabase-config.mjs`.

Em Auth → Providers: **Anonymous** ligado. Após migrations: `npx prisma migrate deploy`.

## Requisitos

- macOS Sequoia 15+, Xcode, iOS 16.2+
- Capability HealthKit no target Companion
- Projeto Supabase com migration `cloud_survival_iot`

## Gerar / abrir

```bash
./scripts/generate-ios-project.sh
open apps/ios/Companion.xcodeproj
```
