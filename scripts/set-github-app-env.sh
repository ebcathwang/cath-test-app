#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 APP_ID PATH_TO_PEM" >&2
  exit 1
fi

PROFILE="${AWS_PROFILE:-finance}"
REGION="${AWS_REGION:-us-east-1}"
FUNCTION_NAME="${FUNCTION_NAME:-cath-test-app-pr-hello}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ID="$1"
PEM_PATH="$2"
SECRET_FILE="$ROOT/.secrets/webhook-secret"
ENV_FILE="$ROOT/build/environment.json"

if [[ ! -s "$SECRET_FILE" ]]; then
  echo "missing $SECRET_FILE; deploy first" >&2
  exit 1
fi
if [[ ! -s "$PEM_PATH" ]]; then
  echo "missing private key $PEM_PATH" >&2
  exit 1
fi

mkdir -p "$ROOT/build"
python3 - "$ENV_FILE" "$APP_ID" "$PEM_PATH" "$SECRET_FILE" <<'PY'
import json, sys
path, app_id, pem_path, secret_path = sys.argv[1:]
with open(pem_path) as handle:
    private_key = handle.read().strip()
with open(secret_path) as handle:
    secret = handle.read().strip()
with open(path, "w") as handle:
    json.dump(
        {
            "Variables": {
                "GITHUB_APP_ID": app_id,
                "GITHUB_WEBHOOK_SECRET": secret,
                "GITHUB_PRIVATE_KEY": private_key,
            }
        },
        handle,
    )
PY

AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="$REGION" \
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "file://$ENV_FILE" >/dev/null

echo "Updated $FUNCTION_NAME environment in $REGION"
