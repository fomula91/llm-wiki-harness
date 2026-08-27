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
