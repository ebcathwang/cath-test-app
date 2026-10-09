#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-finance}"
REGION="${AWS_REGION:-us-east-1}"
FUNCTION_NAME="${FUNCTION_NAME:-cath-test-app-pr-hello}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/lambda/pr_hello"
BUILD="$ROOT/build/pr_hello"
ZIP="$ROOT/build/pr_hello.zip"
SECRET_FILE="$ROOT/.secrets/webhook-secret"

export AWS_PROFILE="$PROFILE"
export AWS_DEFAULT_REGION="$REGION"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$ROOT/.secrets" "$ROOT/build"

PACK_VENV="$ROOT/build/pack-venv"
python3 -m venv "$PACK_VENV"
"$PACK_VENV/bin/pip" install --upgrade pip
"$PACK_VENV/bin/pip" install \
  --no-compile \
  --platform manylinux2014_aarch64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  --target "$BUILD" \
  -r "$SRC/requirements.txt"
cp "$SRC/handler.py" "$BUILD/handler.py"
rm -f "$ZIP"
python3 - "$BUILD" "$ZIP" <<'PY'
import os, sys, zipfile
build, zip_path = sys.argv[1:]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
    for dirpath, _, filenames in os.walk(build):
        for name in filenames:
            full = os.path.join(dirpath, name)
            archive.write(full, os.path.relpath(full, build))
PY

if [[ ! -s "$SECRET_FILE" ]]; then
  openssl rand -hex 32 > "$SECRET_FILE"
fi
WEBHOOK_SECRET="$(tr -d '[:space:]' < "$SECRET_FILE")"

if [[ -z "${ROLE_ARN:-}" ]]; then
  echo "Set ROLE_ARN to the Lambda execution role" >&2
  exit 1
fi
echo "Using role $ROLE_ARN"

ENV_FILE="$ROOT/build/environment.json"

if aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP" >/dev/null
else
  python3 - "$ENV_FILE" "$WEBHOOK_SECRET" <<'PY'
import json, sys
path, secret = sys.argv[1:]
with open(path, "w") as handle:
    json.dump(
        {
            "Variables": {
                "GITHUB_APP_ID": "pending",
                "GITHUB_WEBHOOK_SECRET": secret,
                "GITHUB_PRIVATE_KEY": "pending",
            }
        },
        handle,
    )
PY
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --architectures arm64 \
    --handler handler.lambda_handler \
    --role "$ROLE_ARN" \
    --timeout 15 \
    --memory-size 256 \
    --zip-file "fileb://$ZIP" \
    --environment "file://$ENV_FILE" >/dev/null
fi

aws lambda wait function-updated --function-name "$FUNCTION_NAME"

if ! aws lambda get-function-url-config --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  aws lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE >/dev/null
fi

aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id FunctionURLAllowPublicAccess \
  --action lambda:InvokeFunctionUrl \
  --principal "*" \
  --function-url-auth-type NONE >/dev/null 2>&1 || true

aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id FunctionURLAllowPublicInvoke \
  --action lambda:InvokeFunction \
  --principal "*" \
  --invoked-via-function-url >/dev/null 2>&1 || true

FUNCTION_URL="$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --query FunctionUrl --output text)"
echo "FUNCTION_URL=$FUNCTION_URL"
echo "Webhook secret is in $SECRET_FILE"
