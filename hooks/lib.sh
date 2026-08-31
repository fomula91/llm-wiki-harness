#!/usr/bin/env bash
# LLM-WIKI 하네스 — 훅 공용 라이브러리
#
# 이 파일은 install.sh가 대상 repo의 .claude/hooks/ 로 **치환 없이 그대로** 복사한다.
# 테스트가 검증하는 파일과 배포되는 파일이 바이트 단위로 같아야 테스트가 실제 배포본을
# 증명하므로, 이 스크립트들에는 __PLACEHOLDER__를 쓰지 않는다.
# 프로젝트별 설정은 같은 디렉터리의 llm-wiki.conf.sh 하나에만 있다.
#
# 훅은 어떤 경우에도 세션을 망가뜨리면 안 된다 — 판단 근거가 없으면 조용히 exit 0.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
[ -f "$HOOK_DIR/llm-wiki.conf.sh" ] && . "$HOOK_DIR/llm-wiki.conf.sh"

PROJECT_KEY="${PROJECT_KEY:-}"
WIKI_MODE="${WIKI_MODE:-in-repo}"

# 세션 시작 주입은 그 세션의 **매 턴** 다시 전송된다 — 한 번의 비용이 아니다.
# 위키가 커질수록 주입이 무한정 자라지 않도록 상한을 둔다. 프로젝트별 조정은 llm-wiki.conf.sh.
INJECT_MAX_LOG="${INJECT_MAX_LOG:-10}"
INJECT_MAX_TASKS="${INJECT_MAX_TASKS:-8}"

# 위키 vault 루트 (external 모드 전용). 머신별 경로의 단일 출처는 $WIKI_ROOT —
# .claude/settings.local.json(git 미커밋)의 env로 주입된다. 커밋되는 파일에는 경로가 없다.
resolve_vault() {
	[ "$WIKI_MODE" = external ] || return 1
	[ -n "${WIKI_ROOT:-}" ] || return 1
	[ -d "$WIKI_ROOT/Projects/$PROJECT_KEY" ] || return 1
	printf '%s' "$WIKI_ROOT"
}

# 이 프로젝트의 위키 디렉터리. 못 찾으면 1.
resolve_wiki() {
	local vault
	if [ "$WIKI_MODE" = external ]; then
		vault="$(resolve_vault)" || return 1
		printf '%s' "$vault/Projects/$PROJECT_KEY"
	else
		[ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 1
		[ -d "$CLAUDE_PROJECT_DIR/llm-wiki" ] || return 1
		printf '%s' "$CLAUDE_PROJECT_DIR/llm-wiki"
	fi
}

# ── 형식 계약 파서 ──────────────────────────────────────────────────────────
# 아래 세 함수가 log.md / Next-Tasks.md 의 형식 계약을 실제로 정의한다.
# 계약 문구는 README·wiki-rules.*.md·wiki-side/CLAUDE.md 에도 산문으로 있지만,
# 강제하는 것은 이 파서와 tests/cases/contract.test.sh 다.

# log.md 최신 날짜 섹션의 헤더 (`## YYYY-MM-DD`)
extract_log_date() { # <log.md>
	grep -m1 '^## [0-9]' "$1" 2>/dev/null
}

# log.md 최신 날짜 섹션의 항목 제목만 (`- **제목**: 내용` → `- 제목`).
# 두 번째 날짜 섹션을 만나면 멈춘다 — 최신 것만 주입한다.
extract_log_titles() { # <log.md>
	awk '/^## [0-9]/{c++} c==1{print} c==2{exit}' "$1" 2>/dev/null |
		grep '^- \*\*' |
		sed -E 's/^- \*\*([^*]+)\*\*.*/- \1/'
}

# Next-Tasks.md 의 `## 열린 과제` 아래 `### N. 제목` 만.
# 다음 `## ` 섹션(종료 기록)을 만나면 멈추고, blockquote(`> `)로 시작하는
# 형식 설명은 `^### ` 에 걸리지 않으므로 자연히 제외된다.
extract_open_tasks() { # <Next-Tasks.md>
	awk '/^## 열린 과제/{f=1;next} /^## /{f=0} f&&/^### /{print}' "$1" 2>/dev/null |
		sed -E 's/^### /- /'
}

# 목록을 <max>줄로 자르고, 잘렸으면 무엇을 읽어야 나머지가 있는지 한 줄로 알린다.
# 잘린 사실을 숨기면 세션이 "이게 전부"라고 오해한다 — 줄이되 속이지 않는다.
cap_lines() { # cap_lines <max> <더 읽을 곳> ; 목록은 stdin
	local max="$1" ref="$2" body n
	body="$(cat)"
	[ -n "$body" ] || return 0
	n="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
	if [ "$n" -le "$max" ]; then
		printf '%s\n' "$body"
		return 0
	fi
	printf '%s\n' "$body" | head -n "$max"
	printf -- '- …외 %d건 — 필요하면 %s 를 직접 읽는다\n' "$((n - max))" "$ref"
}
