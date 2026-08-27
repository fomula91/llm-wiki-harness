#!/usr/bin/env bash
# Stop 훅 (외부 vault 모드) — 기록 누락 + 위키 미저장 감지, 그리고 오탐 금지
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

OLD=2020-01-01
TODAY="$(date +%F)"

new_case() { # new_case <log-date> — repo/vault 를 전역에 세팅
	repo="$(mk_repo)"
	vault="$(mk_vault testproj)"
	install_hooks "$repo" testproj external
	write_log "$vault/Projects/testproj/log.md" "$1" "이전작업"
	git -C "$vault" add -A
	git -C "$vault" commit -qm log
	git -C "$vault" push -q
	export CLAUDE_PROJECT_DIR="$repo" WIKI_ROOT="$vault"
	HOOK="$repo/.claude/hooks/stop.sh"
}

# 코드 변경 + 오늘 기록 없음 → 막는다
new_case "$OLD"
echo changed >>"$repo/app.txt"
run_hook "$HOOK"
assert_rc 2 "코드 변경 + 오늘 기록 없음 → 막는다"

# 오늘 기록을 남기면(커밋·푸시까지) 통과
new_case "$TODAY"
echo changed >>"$repo/app.txt"
run_hook "$HOOK"
assert_rc 0 "오늘 기록이 있고 위키가 저장돼 있으면 통과시킨다"

# 위키의 이 프로젝트 경로가 미커밋이면 막는다
new_case "$TODAY"
echo "추가" >>"$vault/Projects/testproj/log.md"
run_hook "$HOOK"
assert_rc 2 "Projects/<key> 미커밋 변경 → 막는다"

# 커밋했지만 푸시 안 했으면 막는다
new_case "$TODAY"
echo "추가" >>"$vault/Projects/testproj/log.md"
git -C "$vault" add -A && git -C "$vault" commit -qm unpushed
run_hook "$HOOK"
assert_rc 2 "푸시 안 된 커밋 → 막는다"

# ── 오탐 금지 (버그 #1) ──────────────────────────────────────────────────────
# vault는 여러 프로젝트가 공유하고 .obsidian/ 은 상시 변한다.
# 이 프로젝트와 무관한 변경으로 매 세션 경고가 뜨면 사용자는 훅을 꺼버린다.
new_case "$TODAY"
mkdir -p "$vault/.obsidian" "$vault/Projects/other"
echo '{}' >"$vault/.obsidian/workspace.json"
echo "다른 프로젝트 노트" >"$vault/Projects/other/note.md"
run_hook "$HOOK"
assert_rc 0 "vault의 무관한 경로만 dirty하면 막지 않는다"
assert_out_empty "무관한 변경에는 아무 말도 하지 않는다"

# upstream이 없어도 크래시하지 않는다
new_case "$TODAY"
git -C "$vault" branch --unset-upstream 2>/dev/null
git -C "$vault" remote remove origin 2>/dev/null
run_hook "$HOOK"
assert_rc 0 "upstream 미설정이면 push 검사를 건너뛴다"

# 위키를 못 찾으면 막지 않는다
new_case "$TODAY"
export WIKI_ROOT=/nonexistent
echo changed >>"$repo/app.txt"
run_hook "$HOOK"
assert_rc 0 "위키를 못 찾으면 막지 않는다"

summary
