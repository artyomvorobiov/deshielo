#!/usr/bin/env bash
# Запускает чистый PocketBase с миграциями и хуками сообщества, прогоняет тесты API и останавливает сервер.
#   server/tests/run.sh [путь к pocketbase]
set -euo pipefail
cd "$(dirname "$0")/../.."
PB="${1:-${POCKETBASE:-pocketbase}}"
PORT="${PB_PORT:-8090}"
DATA="$(mktemp -d)"
"$PB" serve --http "127.0.0.1:$PORT" --dir "$DATA" \
  --migrationsDir server/pb_migrations --hooksDir server/pb_hooks > "$DATA/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true; rm -rf "$DATA"' EXIT
STATUS=0
PB_URL="http://127.0.0.1:$PORT" python3 server/tests/test_api.py || STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  echo "--- журнал сервера ---"
  cat "$DATA/server.log"
fi
exit "$STATUS"
