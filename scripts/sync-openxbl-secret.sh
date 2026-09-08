#!/usr/bin/env bash
# Sobe OPENXBL_API_KEY do .env para secrets das Edge Functions.
# Uso: preencha OPENXBL_API_KEY no .env e rode: ./scripts/sync-openxbl-secret.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="${SUPABASE_CLI:-$ROOT/.tools/supabase}"
REF="${SUPABASE_PROJECT_REF:-zlsrurqfkhspwbzmqimp}"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env"
  exit 1
fi

# shellcheck disable=SC1091
set -a
# Carrega só o necessário
eval "$(grep -E '^(SUPABASE_ACCESS_TOKEN|OPENXBL_API_KEY)=' .env | sed 's/\r$//' | sed 's/^/export /')"
set +a

if [[ -z "${OPENXBL_API_KEY:-}" ]]; then
  echo "Cole a key em OPENXBL_API_KEY no .env e rode de novo."
  exit 1
fi
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Defina SUPABASE_ACCESS_TOKEN no .env (Dashboard → Account → Access Tokens)."
  exit 1
fi

"$SB" secrets set "OPENXBL_API_KEY=${OPENXBL_API_KEY}" --project-ref "$REF"
echo "OK — secret OPENXBL_API_KEY atualizado no projeto ${REF}"
