#!/usr/bin/env bash
# 전체 테스트 러너 — 의존성: bash, git, jq
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v jq >/dev/null || { echo "jq가 필요합니다 (brew install jq)"; exit 1; }
command -v git >/dev/null || { echo "git이 필요합니다"; exit 1; }

rm -rf "$ROOT/tests/.tmp"
mkdir -p "$ROOT/tests/.tmp"

failed=0
for case_file in "$ROOT"/tests/cases/*.test.sh; do
	printf '\n\033[1m%s\033[0m\n' "$(basename "$case_file")"
	bash "$case_file" || failed=$((failed + 1))
done

rm -rf "$ROOT/tests/.tmp"

printf '\n'
if [ "$failed" -eq 0 ]; then
	printf '\033[32m전체 통과\033[0m\n'
else
	printf '\033[31m실패한 케이스 파일: %d\033[0m\n' "$failed"
fi
exit "$failed"
