#!/usr/bin/env bash
# Stop 훅 — 이번 세션 작업이 위키에 기록됐는지 확인하고, 누락이면 exit 2로 되돌린다.
#
# exit 2 = stderr가 아니라 stdout 메시지를 LLM에게 돌려주고 세션을 잇는다는 뜻.
# 자동 커밋은 하지 않는다 — LLM이 큐레이션된 요약을 직접 쓰게 유도하는 것이 목적이다.
# 판단 근거가 없으면(위키 없음, git 아님) 조용히 exit 0.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HOOK_DIR/lib.sh"

TODAY="$(date +%F)"

W="$(resolve_wiki)" || exit 0
[ -f "$W/log.md" ] || exit 0
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0
git -C "$CLAUDE_PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# ── 1. 코드가 바뀌었는데 오늘 기록이 없는가 (두 모드 공통 강제력) ──────────────
if [ "$WIKI_MODE" = in-repo ]; then
	# 위키가 코드와 같은 트리에 있으므로 위키 자신의 변경은 "코드 변경"에서 뺀다.
	code_dirty="$(git -C "$CLAUDE_PROJECT_DIR" status --porcelain -- . ':(exclude)llm-wiki' 2>/dev/null)"
	wiki_ref="llm-wiki/log.md"
	fix_hint="이번 세션 작업을 log.md에 기록하세요."
else
	code_dirty="$(git -C "$CLAUDE_PROJECT_DIR" status --porcelain 2>/dev/null)"
	wiki_ref="위키 Projects/$PROJECT_KEY/log.md"
	fix_hint="이번 세션 작업을 log.md에 기록하고 위키를 커밋·푸시한 뒤 종료하세요."
fi

if [ -n "$code_dirty" ] && ! grep -q "^## $TODAY" "$W/log.md"; then
	echo "코드 변경이 있는데 $wiki_ref 에 오늘(## $TODAY) 기록이 없습니다. $fix_hint"
	exit 2
fi

# ── 2. external 모드만: 위키가 커밋·푸시되지 않았는가 ─────────────────────────
[ "$WIKI_MODE" = external ] || exit 0

vault="$(resolve_vault)" || exit 0
[ -d "$vault/.git" ] || exit 0

# dirty 검사는 이 프로젝트의 위키 경로로만 좁힌다. vault는 여러 프로젝트가 공유하고
# .obsidian/workspace.json 같은 파일이 상시 변하므로, 전체를 보면 매 세션 오탐이 난다.
dirty="$(git -C "$vault" status --porcelain -- "Projects/$PROJECT_KEY" 2>/dev/null)"
# 반면 push는 vault 단위라 전체 기준이 맞다. upstream이 없으면 빈 결과 → 통과.
unpushed="$(git -C "$vault" log --oneline '@{u}..HEAD' 2>/dev/null)"

[ -z "$dirty" ] && [ -z "$unpushed" ] && exit 0

echo "위키에 저장 안 된 변경이 있습니다. Projects/$PROJECT_KEY/log.md 기록을 커밋·푸시한 뒤 종료하세요."
exit 2
