#!/usr/bin/env bash
# 다음 리셋 시각까지 기다린다. 토큰이 없는 단계에서 실행된다.
# state/next_reset (epoch 초) 은 지난 핑이 API 응답에서 받아 적어 둔 실제 리셋 시각이다.
set -euo pipefail

MAX_WAIT=$((335 * 60))   # job 제한(6시간) 안에서 기다릴 수 있는 최대치
GRACE=3                  # 리셋 직후 몇 초 여유

out=${GITHUB_OUTPUT:-/dev/null}
mkdir -p state
now=$(date -u +%s)
next=$(cat state/next_reset 2>/dev/null || echo 0)
[[ "$next" =~ ^[0-9]+$ ]] || next=0

if [[ "${FORCE:-false}" == "true" || "$next" -eq 0 ]]; then
  due=$now
else
  due=$((next + GRACE))
fi

wait_s=$((due - now))
if (( wait_s > MAX_WAIT )); then
  echo "다음 리셋($(TZ=Asia/Seoul date -d "@$next" '+%m-%d %H:%M:%S KST'))까지 너무 멀어서 다음 실행에 맡김"
  echo "skip=true" >> "$out"
  exit 0
fi

if (( wait_s > 0 )); then
  echo "리셋 $(TZ=Asia/Seoul date -d "@$due" '+%m-%d %H:%M:%S KST') 까지 ${wait_s}초 대기"
  sleep "$wait_s"
fi
echo "skip=false" >> "$out"
