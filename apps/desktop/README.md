# Companion Electron — Popup Tamagotchi

Popup frameless no canto da tela. Cérebro local (API embutida / mock) + **sync direto com Supabase** (mesma conta do iPhone).

## Pré-requisitos

- Node.js 20+
- Projeto Supabase com migrations aplicadas (`npx prisma migrate deploy` na raiz)
- Opcional: `npm run dev` na raiz só para mock Express local

## Setup

Na raiz do monorepo:

```bash
npm install
cp apps/desktop/.env.example apps/desktop/.env
```

No `.env` da **raiz** (uma vez):

```bash
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...   # Dashboard → Settings → API → anon public
node scripts/sync-supabase-config.mjs
```

Isso propaga para o desktop e embute no iOS. Usuários finais só usam email/senha.

## Rodar

```bash
npm run dev
```

Sobe o mock local (se necessário) e o Electron. Login: **Config → Conta** (email/senha Supabase).

## Sync PC ↔ iPhone

Mesma `SUPABASE_URL` + anon key + conta. Pet e missões via PostgREST (RLS). **Não** precisa hospedar Express.

## Missões / voz

Rotação diária alinhada ao iOS (`MissionCatalog` / `missionCatalog.ts`): cutucadas, feed, play, chat, tease, visita.

## Variáveis

| Variável | Descrição |
|---|---|
| `SUPABASE_URL` | Projeto Supabase |
| `SUPABASE_ANON_KEY` | Anon key (nunca service role) |
| `API_URL` | Mock Express local (opcional) |
