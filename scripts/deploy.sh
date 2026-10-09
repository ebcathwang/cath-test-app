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

ROLE_ARN="$(aws iam list-roles --output json | python3 -c '
import json, sys
data = json.load(sys.stdin)
matches = []
for role in data.get("Roles", []):
    doc = role.get("AssumeRolePolicyDocument", {})
    statements = doc.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]
    for statement in statements:
        service = statement.get("Principal", {}).get("Service", [])
        if isinstance(service, str):
            service = [service]
        if "lambda.amazonaws.com" in service:
            matches.append((role["RoleName"], role["Arn"]))
            break
preferred = [item for item in matches if "lambda" in item[0].lower()]
chosen = preferred or matches
if not chosen:
    sys.exit(2)
if len(chosen) > 1:
    print("candidate roles:", ", ".join(name for name, _ in chosen), file=sys.stderr)
print(chosen[0][1])
')"

echo "Using role $ROLE_ARN"

ENV_FILE="$ROOT/build/environment.json"
EXISTING_CONFIG="$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --output json 2>/dev/null || true)"
python3 - "$ENV_FILE" "$WEBHOOK_SECRET" "$EXISTING_CONFIG" <<'PY'
import json, sys
path, secret, existing = sys.argv[1:]
app_id = "pending"
private_key = "pending"
if existing.strip():
    variables = json.loads(existing).get("Environment", {}).get("Variables", {})
    current_key = variables.get("GITHUB_PRIVATE_KEY", "")
    if "BEGIN" in current_key:
        app_id = variables.get("GITHUB_APP_ID", app_id)
        private_key = current_key
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

if aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME"
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --role "$ROLE_ARN" \
    --runtime python3.12 \
    --handler handler.lambda_handler \
    --timeout 15 \
    --memory-size 256 \
    --environment "file://$ENV_FILE" >/dev/null
else
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
echo "WEBHOOK_SECRET=$WEBHOOK_SECRET"
