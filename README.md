# cath-test-app

When a pull request is opened, the GitHub App calls a Lambda. The Lambda submits a `COMMENT` review whose body is `hello`.

## Deploy

Deploy with the `finance` profile in `us-east-1`. Set `ROLE_ARN` to an existing Lambda execution role. The webhook secret is created in `.secrets/webhook-secret` and stored only as a Lambda environment variable.

```bash
aws sso login --profile finance
ROLE_ARN=arn:aws:iam::ACCOUNT/role/NAME ./scripts/deploy.sh
```

## GitHub App

App settings: https://github.com/settings/apps/cath-test-app

1. Set the webhook URL to the `FUNCTION_URL` printed by the deploy script. Set the webhook secret to the value in `.secrets/webhook-secret`.
2. Grant Pull requests Write.
3. Subscribe to the Pull request event.
4. Generate a private key. The App ID is at the top of the same settings page.
5. Keep the key file outside the repo and update the Lambda environment.

```bash
./scripts/set-github-app-env.sh APP_ID /path/to/cath-test-app.pem
```

6. Install the app on `ebcathwang/cath-test-app`.
7. Open a pull request. The app should leave a `hello` review. A pull request opened before setup does not send that event again.
