#!/usr/bin/env bash
# Haiku 로 "." 을 보내고, 응답에 실린 5시간 창의 실제 리셋 시각을 state/next_reset 에 적는다.
set -euo pipefail

MODEL="claude-haiku-4-5-20251001"
CLI="$PWD/node_modules/@anthropic-ai/claude-code-linux-x64/claude"
LOG=state/ping-log.md
FALLBACK=$((5 * 3600))   # 응답에 리셋 시각이 없을 때 추정치
RETRY_AFTER=$((15 * 60)) # 실패하면 15분 뒤 재시도

# 토큰은 셸 변수로 옮기고 환경에서 지운다. CLI 프로세스에만 넘긴다.
tok="${CLAUDE_CODE_OAUTH_TOKEN:-}"
unset CLAUDE_CODE_OAUTH_TOKEN
[[ -n "$tok" ]] || { echo "::error::토큰 없음. environment 'usage-ping' 의 secret 과 배포 브랜치 규칙을 확인"; exit 1; }
echo "::add-mask::$tok"

mkdir -p state
[[ -f "$LOG" ]] || printf '# 짬통: 5시간 리셋 핑 기록\n\n| 핑 (KST) | 결과 | 다음 리셋 (KST) | 출처 |\n|---|---|---|---|\n' > "$LOG"
kst() { TZ=Asia/Seoul date -d "@$1" '+%m-%d %H:%M:%S'; }

# 저장소·사용자 설정, CLAUDE.md, .mcp.json 을 하나도 못 읽게 빈 폴더와 빈 HOME 에서 실행한다.
sandbox=$(mktemp -d); trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/home" "$sandbox/cwd"

ping_once() {
  ( cd "$sandbox/cwd" && env -i \
      PATH="/usr/bin:/bin" HOME="$sandbox/home" LANG=C.UTF-8 \
      ${HTTPS_PROXY:+HTTPS_PROXY="$HTTPS_PROXY"} ${SSL_CERT_FILE:+SSL_CERT_FILE="$SSL_CERT_FILE"} \
      CLAUDE_CODE_OAUTH_TOKEN="$tok" \
      DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 DISABLE_AUTOUPDATER=1 \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      "$CLI" -p "." \
        --model "$MODEL" \
        --system-prompt "Reply with a single period." \
        --tools "" \
        --strict-mcp-config \
        --disable-slash-commands \
        --setting-sources "" \
        --no-session-persistence \
        --output-format stream-json --verbose </dev/null 2>/dev/null )
}

result="fail" next="" source=""
for attempt in 1 2 3; do
  now=$(date -u +%s)
  out=$(ping_once) && rc=0 || rc=$?
  info=$(printf '%s\n' "$out" | jq -c 'select(.type=="rate_limit_event") | .rate_limit_info' 2>/dev/null | tail -1 || true)
  status=$(jq -r '.status // empty' <<<"${info:-null}" 2>/dev/null || true)
  reset=$(jq -r '.unifiedWindows.five_hour.resetsAt // (if .rateLimitType=="five_hour" then .resetsAt else empty end) // empty' <<<"${info:-null}" 2>/dev/null || true)
  is_error=$(printf '%s\n' "$out" | jq -r 'select(.type=="result") | .is_error' 2>/dev/null | tail -1 || true)

  if [[ "$status" == "rejected" && "$reset" =~ ^[0-9]+$ ]] && (( reset - now < 15 * 60 )); then
    # 아직 이전 창이 안 끝났다 (시계 오차 등). 리셋 시각까지 기다렸다 다시.
    echo "아직 막힘. 리셋 $(kst "$reset") 까지 기다렸다 재시도 ($attempt/3)"
    sleep $(( reset - now + 3 )); continue
  fi
  if [[ $rc -eq 0 && "$is_error" == "false" ]]; then
    result="ok"
    if [[ "$reset" =~ ^[0-9]+$ ]] && (( reset > now )); then next=$reset source="API"
    else next=$((now + FALLBACK)) source="추정(+5h)"; fi
    break
  fi
  # 실패 이유는 result 메시지 앞부분만 (토큰은 마스킹됨)
  why=$(printf '%s\n' "$out" | jq -r 'select(.type=="result") | .result // empty' 2>/dev/null | tail -1 | tr -d '|\n' | cut -c1-60 || true)
  result="fail(${why:-exit $rc})"
  [[ "$status" == "rejected" && "$reset" =~ ^[0-9]+$ ]] && { next=$reset source="막힘"; break; }
  (( attempt < 3 )) && sleep 30
done
[[ -n "$next" ]] || { next=$(( $(date -u +%s) + RETRY_AFTER )); source="재시도"; }

echo "$next" > state/next_reset
echo "| $(kst "$now") | $result | $(kst "$next") | $source |" >> "$LOG"
echo "핑 결과: $result / 다음 리셋: $(kst "$next") KST ($source)"
{ echo "### 최근 핑"; sed -n '3,4p' "$LOG"; grep '^| [0-9]' "$LOG" | tail -10; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
[[ "$result" == "ok" ]]
