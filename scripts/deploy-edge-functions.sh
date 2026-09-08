#!/usr/bin/env bash
# Deploy IoT + survival Edge Functions to Supabase.
# Requires: supabase login  OR  export SUPABASE_ACCESS_TOKEN=sbp_...
# Token: https://supabase.com/dashboard/account/tokens
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="${SUPABASE_CLI:-$ROOT/.tools/supabase}"
REF="${SUPABASE_PROJECT_REF:-zlsrurqfkhspwbzmqimp}"

if [[ ! -x "$SB" ]]; then
  echo "Missing CLI at $SB — download from https://github.com/supabase/cli/releases"
  exit 1
fi

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  if ! "$SB" projects list &>/dev/null; then
    echo "Not logged in. Run one of:"
    echo "  $SB login"
    echo "  export SUPABASE_ACCESS_TOKEN=sbp_...   # Dashboard → Account → Access Tokens"
    exit 1
  fi
fi

cd "$ROOT"
"$SB" link --project-ref "$REF" || true

for fn in companion-state tick-decay steps-ingest context-ingest; do
  echo "=== deploy $fn ==="
  "$SB" functions deploy "$fn" --project-ref "$REF" --use-api
done

echo "Done. List:"
"$SB" functions list --project-ref "$REF"
