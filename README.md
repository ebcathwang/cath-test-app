# cath-test-app

PR이 열리면 GitHub App이 Lambda를 호출하고, 그 PR 대화에 `hello`를 남깁니다.

## 배포

`finance` 프로필로 `us-east-1`에 배포합니다. Webhook secret은 `.secrets/webhook-secret`에 생성되고 Lambda 환경변수에만 들어갑니다.

```bash
aws sso login --profile finance
./scripts/deploy.sh
```

## GitHub App 설정

앱 설정 페이지: https://github.com/settings/apps/cath-test-app

1. Webhook URL에 `https://yb4mdguz5u6y4tj2ctatcnhvqa0rmwnw.lambda-url.us-east-1.on.aws/` 를 넣습니다. Webhook secret에는 `.secrets/webhook-secret` 값을 넣습니다.
2. 권한은 Pull requests를 Read, Issues를 Write로 둡니다.
3. 구독 이벤트는 Pull request만 켭니다.
4. Private key를 생성합니다. App ID는 같은 설정 페이지 위에 있습니다.
5. 키 파일을 리포 밖에 두고 Lambda 환경변수를 갱신합니다.

```bash
./scripts/set-github-app-env.sh APP_ID /path/to/cath-test-app.pem
```

6. 앱을 `ebcathwang/cath-test-app`에 설치합니다.
7. 설치가 끝난 뒤 PR을 열면 대화에 `hello`가 달려야 합니다. 설정 전에 연 PR에는 이벤트가 다시 오지 않습니다.
