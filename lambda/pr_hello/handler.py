import base64
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.request

import jwt


def lambda_handler(event, context):
    headers = event.get("headers") or {}
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(body)
    elif isinstance(body, str):
        raw_body = body.encode()
    else:
        raw_body = body

    if not verify_signature(raw_body, header(headers, "x-hub-signature-256")):
        return response(401, {"error": "invalid signature"})

    event_name = header(headers, "x-github-event")
    if event_name == "ping":
        return response(200, {"ok": True})

    payload = json.loads(raw_body.decode() or "{}")
    action = payload.get("action")
    if event_name != "pull_request" or action not in {"opened", "synchronize"}:
        return response(200, {"ignored": True})

    installation_id = payload["installation"]["id"]
    repo = payload["repository"]["full_name"]
    number = payload["pull_request"]["number"]
    token = installation_token(installation_id)
    if action == "opened":
        github_request(
            "POST",
            f"https://api.github.com/repos/{repo}/pulls/{number}/reviews",
            token,
            {"body": "hello", "event": "COMMENT"},
        )
        return response(200, {"reviewed": True})

    sha = payload["pull_request"]["head"]["sha"]
    github_request(
        "POST",
        f"https://api.github.com/repos/{repo}/check-runs",
        token,
        {"name": "cath-test-app", "head_sha": sha, "status": "completed", "conclusion": "success"},
    )
    return response(200, {"checked": True})


def verify_signature(raw_body, signature):
    secret = os.environ.get("GITHUB_WEBHOOK_SECRET", "")
    if not secret or not signature.startswith("sha256="):
        return False
    digest = hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(f"sha256={digest}", signature)


def installation_token(installation_id):
    app_jwt = jwt.encode(
        {
            "iat": int(time.time()) - 60,
            "exp": int(time.time()) + 9 * 60,
            "iss": os.environ["GITHUB_APP_ID"],
        },
        private_key(),
        algorithm="RS256",
    )
    data = github_request(
        "POST",
        f"https://api.github.com/app/installations/{installation_id}/access_tokens",
        app_jwt,
    )
    return data["token"]


def private_key():
    key = os.environ.get("GITHUB_PRIVATE_KEY", "").replace("\\n", "\n").strip()
    if "BEGIN" not in key:
        raise ValueError("GITHUB_PRIVATE_KEY is not configured")
    return key


def github_request(method, url, token, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "cath-test-app",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as result:
            raw = result.read().decode()
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        raise RuntimeError(f"GitHub API {error.code}: {detail}") from error
    return json.loads(raw) if raw else {}


def header(headers, name):
    for key, value in headers.items():
        if key.lower() == name:
            return value or ""
    return ""


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }
