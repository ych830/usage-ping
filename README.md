# usage-ping

Claude 5시간 사용량 창이 리셋되는 **그 순간**에 Haiku 4.5로 `.` 한 번을 보내서, 다음 창이 바로 시작되게 한다.

## 동작

1. 핑을 보내면 API 응답(`rate_limit_event`)에 **실제 5시간 창 리셋 시각**이 실려 온다. 그 값을 `state/next_reset`에 적어 둔다.
2. 워크플로는 매시간 하나씩 시작된다. 앞 실행이 아직 기다리는 중이면 대기열에서 차례를 기다린다.
3. 차례가 온 실행은 적어 둔 리셋 시각 + 3초까지 잠들었다가 핑한다. GitHub 스케줄이 늦어져도 핑 시각은 밀리지 않는다.
4. 혹시 아직 막혀 있으면(시계 오차 등) 응답의 리셋 시각까지 기다렸다 다시 보낸다. 실패하면 15분 뒤 재시도한다.

처음 한 번은 바로 핑한다. 그때 이미 창이 열려 있었다면 응답에 그 창의 리셋 시각이 오므로, 다음 핑부터 정확히 맞춰진다.

**짬통:** 핑 기록은 Actions cache 의 `state/ping-log.md`에 쌓이고, 핑한 실행의 **Summary** 탭에 최근 10건이 표로 나온다.

## 보안

| 위험 | 막는 방법 |
|---|---|
| 다른 브랜치·PR·포크가 토큰을 읽음 | `usage-ping` **environment secret** + 배포 브랜치를 `main`으로 제한. pull_request 트리거 없음. 이 저장소의 `main`이 아니면 job이 아예 안 돈다 |
| 토큰이 다른 프로그램에 노출 | 토큰은 마지막 `Ping` 단계에만 들어가고, 그 안에서도 바로 환경변수에서 지운 뒤 CLI 프로세스에만 넘긴다. 설치·대기 단계에는 없다 |
| 로그에 토큰이 찍힘 | `::add-mask::`로 가림. CLI 출력은 로그에 안 찍고, 실패 이유만 60자로 남김 |
| 워크플로가 저장소를 변조 | `GITHUB_TOKEN`은 `contents: read`만 |
| 액션·패키지 바꿔치기 | 액션은 커밋 해시로 고정. CLI는 `package-lock.json`의 sha512로 npm이 받기 전에 검증. **설치 스크립트는 실행 안 함** (`--ignore-scripts`) |
| 저장소 파일이 CLI를 조종 | CLI를 **빈 폴더 + 빈 HOME + 최소 환경변수**로 실행. 툴·MCP·훅·설정·CLAUDE.md·슬래시 명령 전부 꺼짐 (훅·MCP·CLAUDE.md를 일부러 심어서 하나도 안 도는 것 확인함) |
| 불필요한 외부 통신 | 텔레메트리·오류 보고·자동 업데이트·부가 트래픽 끔. Anthropic API만 호출 |

> `--bare` 옵션은 일부러 쓰지 않는다. bare 모드는 OAuth 토큰을 아예 읽지 않아서 핑이 항상 실패한다.

## 설정 (한 번만)

1. **저장소를 Public으로:** Settings → General → Danger Zone → Change visibility. Free 계정은 public이어야 environment secret을 쓸 수 있고, Actions도 무제한이다.
2. **Environment:** Settings → Environments → New environment → `usage-ping`
   - Deployment branches and tags → **Selected branches and tags** → `main` 추가
   - Environment secrets → `CLAUDE_CODE_OAUTH_TOKEN` = PC에서 `claude setup-token` 실행 결과
   - 저장소 secret(Settings → Secrets → Actions)에는 **아무것도 넣지 않는다**
3. **Actions 설정:** Settings → Actions → General
   - Actions permissions → **Allow ych830, and select non-ych830, actions and reusable workflows** → **Allow actions created by GitHub**만 체크
   - Fork pull request workflows → **Require approval for all external contributors**
   - Workflow permissions → **Read repository contents and packages permissions**, "Allow GitHub Actions to create and approve pull requests" 끔
4. **main 보호:** Settings → Rules → Rulesets → New branch ruleset → 대상 `main` → **Restrict deletions**, **Block force pushes** 체크
5. **계정 2단계 인증** 켜기

설정 후 Actions 탭 → usage-ping → **Run workflow**로 첫 핑을 바로 보낸다. Summary에 `ok`와 `API` 출처가 찍히면 성공.

## 운영

- **끄기:** Actions 탭 → usage-ping → ⋯ → Disable workflow
- **토큰 폐기:** claude.ai 설정에서 무효화. 의심되면 바로 폐기하고 `claude setup-token`으로 새로 발급해 secret만 바꾸면 된다.
- **60일 규칙:** public 저장소는 60일간 커밋이 없으면 예약 실행이 꺼진다. GitHub가 미리 메일을 보내니 Enable 버튼만 누르면 된다.
- **CLI 업데이트:** `package.json`의 버전을 올리고 `npm install --package-lock-only --ignore-scripts`로 lockfile 재생성 후 커밋.
- 정상일 때 Actions 목록에 "취소됨(cancelled)" 실행이 자주 보인다. 대기열에 하나만 남기고 나머지를 GitHub가 정리한 것이라 문제 없다.
