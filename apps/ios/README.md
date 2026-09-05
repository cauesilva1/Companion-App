# Companion iOS

App SwiftUI + WidgetKit + Live Activity. Sync **direto com Supabase** (sem Express na nuvem).

## Modo padrão

1. No Mac (uma vez): coloque `SUPABASE_URL` + `SUPABASE_ANON_KEY` no `.env` da raiz e rode `node scripts/sync-supabase-config.mjs` (embute no Info.plist).
2. Compile no Xcode (scheme **Companion**).
3. **Config → Conta**: só email + senha (criar / entrar). Sem colar URL/key.
4. Quiz → pet nasce e sobe no Postgres.
5. Mesmo email no desktop → mesmo pet.

Standalone (sem login) continua funcionando no aparelho.

### Música (Spotify)

No iPhone **não** dá para ler Spotify/YouTube/Safari pelo Now Playing do sistema. O app usa a **Spotify Web API** (OAuth PKCE).

**Um Client ID do produto** (seu), embutido no build — cada usuário só faz login com a conta Spotify dele:

1. Crie um app em [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
2. Redirect URI: `companion://spotify-callback`
3. No `.env`: `SPOTIFY_CLIENT_ID=...` → `node scripts/sync-supabase-config.mjs` → rebuild
4. No app: **Config → Conectar Spotify** (sem digitar Client ID)

**Quota Spotify:** em Development Mode só ~25 emails listados no dashboard funcionam. Para qualquer usuário Spotify, peça Extended Quota / revisão no dashboard.

YouTube e Safari: sem API pública equivalente — não suportados.

### O que NÃO é embutido

O iPhone **não** embute a API Node (diferente do DMG do Mac). Cloud = projeto Supabase. Express local (`npm run dev`) é só mock no PC.

## Requisitos

- macOS Sequoia 15+, Xcode 26.3 Universal, iOS 16.2+
- Projeto Supabase com migration `supabase_auth_rls` aplicada (`npx prisma migrate deploy`)
- Em Auth → Providers: Email ligado; para testes, desative “Confirm email”

## Gerar / abrir

```bash
./scripts/generate-ios-project.sh
open apps/ios/Companion.xcodeproj
```

App Group: `group.com.companion.tamagotchi`

## Estrutura

```
apps/ios/Companion/Services/SupabaseClient.swift  # Auth + PostgREST
apps/ios/Companion/Services/SyncQueue.swift       # offline flush
apps/ios/Companion/Services/NowPlayingService.swift
apps/ios/Shared/MissionCatalog.swift
```
