# Companion iOS

App SwiftUI + WidgetKit + Live Activity. **Cloud-First** (sobrevivência no Supabase).

## Modo passivo (atual)

1. Sync / decay: Postgres RPCs + Edge — [`docs/CLOUD_FIRST.md`](../../docs/CLOUD_FIRST.md).
2. Life modes (trabalho / sofá / sono): [`docs/LIFE_MODES.md`](../../docs/LIFE_MODES.md) + `POST /context-ingest`.
3. HealthKit: passos → `POST /functions/v1/steps-ingest`.
4. Spotify / NowPlaying → `mediaHint` no contexto.
5. Live Activity: status cloud (energy / lifeMode / presence espelhado).
6. Home = feed de pensamentos; widgets abrem `companion://feed`.

> IoT ESP32 / pareamento de hardware foi **removido** do produto.

No Mac: `SUPABASE_URL` + `SUPABASE_ANON_KEY` no `.env` → `node scripts/sync-supabase-config.mjs`.

Em Auth → Providers: **Anonymous** ligado. Após migrations: `npx prisma migrate deploy`.

## Requisitos

- macOS Sequoia 15+, Xcode, iOS 16.2+
- Capability HealthKit no target Companion
- Projeto Supabase com migrations de survival + life modes

## Gerar / abrir

```bash
./scripts/generate-ios-project.sh
open apps/ios/Companion.xcodeproj
```
