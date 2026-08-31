#!/usr/bin/env bash
# SessionStart 훅 — 위키의 최근 로그 제목 + 열린 과제를 세션 컨텍스트로 주입한다.
#
# 제목 수준만 주입하고 상세는 넣지 않는다. 세션이 필요할 때 위키 정본으로 내려가 읽는다.
# 주입된 내용은 그 세션의 매 턴 다시 전송되므로 건수에도 상한을 둔다 (lib.sh 의 INJECT_MAX_*).
# 어떤 실패 경로든 exit 0 — 기억 주입이 없다고 세션이 막혀서는 안 된다.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HOOK_DIR/lib.sh"

# 하네스를 설치하지 않은 프로젝트 — 플러그인 훅은 모든 프로젝트에서 돌므로 여기서 빠진다.
harness_installed || exit 0

# jq가 없으면 유효한 훅 JSON을 만들 수 없다. 깨진 출력을 뱉느니 조용히 빠진다.
command -v jq >/dev/null 2>&1 || exit 0

if ! W="$(resolve_wiki)"; then
	# external 모드에서 못 찾은 건 설정 실수일 가능성이 높다 — 무음 대신 원인을 알려준다.
	# (in-repo 모드는 위키가 없는 게 정상적인 미설치 상태이므로 조용히 넘어간다.)
	if [ "$WIKI_MODE" = external ]; then
		printf '%s' '{"systemMessage":"⚠️ LLM-WIKI: 위키를 찾지 못했습니다 — .claude/settings.local.json 의 env.WIKI_ROOT 를 확인하세요."}'
	fi
	exit 0
fi

if [ "$WIKI_MODE" = external ]; then
	REF="위키 Projects/$PROJECT_KEY/"
else
	REF="llm-wiki/"
fi

D="$(extract_log_date "$W/log.md")"
R="$(extract_log_titles "$W/log.md" | cap_lines "$INJECT_MAX_LOG" "$REF"log.md)"
O="$(extract_open_tasks "$W/Next-Tasks.md" | cap_lines "$INJECT_MAX_TASKS" "$REF"Next-Tasks.md)"

printf '[%s 위키 기억 — 상세 정본은 %s 참조]\n\n최근 작업 로그(%s):\n%s\n\n열린 과제:\n%s' \
	"$PROJECT_KEY" "$REF" "$D" "$R" "$O" |
	jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
