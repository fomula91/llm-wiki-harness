#!/usr/bin/env bash
# 형식 계약 테스트 — 실제 템플릿과 실제 파서를 맞붙인다.
#
# log.md / Next-Tasks.md 의 형식 계약은 README·wiki-rules.*.md·wiki-side/CLAUDE.md
# 4곳에 산문으로 적혀 있지만, 강제하는 것은 이 파일뿐이다.
# 템플릿이 드리프트하면 기억 주입이 조용히 비므로 여기서 red로 잡는다.
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

repo="$(mk_repo)"
install_hooks "$repo" testproj in-repo
copy_template "$repo/llm-wiki" testproj "$(date +%F)"
export CLAUDE_PROJECT_DIR="$repo"

run_hook "$repo/.claude/hooks/session-start.sh"
assert_rc 0 "배포 템플릿 그대로 exit 0"
assert_json "배포 템플릿에서 유효 JSON이 나온다"

# 파서가 템플릿의 실제 항목을 잡는가 — 여기가 비면 기억 주입이 통째로 빈다
assert_ctx_has "하네스 설치" "log.md 템플릿의 항목 제목이 실제로 추출된다"
assert_ctx_lacks "형식 계약" "log.md 템플릿의 blockquote 설명은 추출되지 않는다"
assert_ctx_lacks "프로젝트 위키 초기화" "제목만 추출하고 본문은 흘리지 않는다"

# 신규 설치 직후 "열린 과제"는 비어 있어야 한다 (버그 #5).
# 템플릿의 작성 예시가 `## 열린 과제` 안에 있으면 가짜 과제가 매 세션 주입된다.
assert_ctx_lacks "(예시)" "신규 설치 직후 가짜 예시 과제가 주입되지 않는다"

open_tasks="$(ctx | sed -n '/^열린 과제:/,$p' | tail -n +2 | tr -d '[:space:]')"
if [ -z "$open_tasks" ]; then
	ok "신규 설치 직후 열린 과제 목록은 비어 있다"
else
	bad "신규 설치 직후 열린 과제 목록은 비어 있다" "실제: $open_tasks"
fi

summary
