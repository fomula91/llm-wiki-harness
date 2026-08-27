#!/usr/bin/env bash
# Stop 훅 (repo 내장 모드) — 강제해야 할 때만 강제하는가
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

new_case() { # new_case <log-date> -> repo 경로. 위키까지 커밋된 깨끗한 상태
	local r
	r="$(mk_repo)"
	install_hooks "$r" testproj in-repo
	copy_template "$r/llm-wiki" testproj "$1"
	write_log "$r/llm-wiki/log.md" "$1" "이전작업"
	git -C "$r" add -A
	git -C "$r" commit -qm wiki
	printf '%s' "$r"
}
OLD=2020-01-01
TODAY="$(date +%F)"

# 깨끗하면 막지 않는다
repo="$(new_case "$OLD")"
export CLAUDE_PROJECT_DIR="$repo"
run_hook "$repo/.claude/hooks/stop.sh"
assert_rc 0 "코드 변경이 없으면 통과시킨다"
assert_out_empty "통과할 때는 아무 말도 하지 않는다"

# 코드가 바뀌었는데 오늘 기록이 없으면 막는다
echo changed >>"$repo/app.txt"
run_hook "$repo/.claude/hooks/stop.sh"
assert_rc 2 "코드 변경 + 오늘 기록 없음 → 막는다"
assert_out_has "log.md" "무엇을 해야 하는지 알려준다"

# 오늘 기록을 남기면 통과
write_log "$repo/llm-wiki/log.md" "$TODAY" "오늘작업"
run_hook "$repo/.claude/hooks/stop.sh"
assert_rc 0 "오늘 기록이 있으면 통과시킨다"

# 위키만 바뀐 경우는 "코드 변경"이 아니다
repo="$(new_case "$OLD")"
export CLAUDE_PROJECT_DIR="$repo"
echo "메모" >>"$repo/llm-wiki/Context.md"
run_hook "$repo/.claude/hooks/stop.sh"
assert_rc 0 "llm-wiki/ 안에서만 바뀌면 막지 않는다"

# untracked 코드 파일만 있어도 코드 변경이다 (커밋 d0b3e32 회귀 고정)
repo="$(new_case "$OLD")"
export CLAUDE_PROJECT_DIR="$repo"
echo new >"$repo/brand-new.txt"
run_hook "$repo/.claude/hooks/stop.sh"
assert_rc 2 "untracked 코드 파일만 있어도 막는다"

# 판단 근거가 없으면 막지 않는다
repo="$(new_case "$OLD")"
export CLAUDE_PROJECT_DIR="$repo"
rm -rf "$repo/.git"
run_hook "$repo/.claude/hooks/stop.sh"
assert_rc 0 "git 저장소가 아니면 막지 않는다"

repo="$(mk_repo)"
install_hooks "$repo" testproj in-repo
export CLAUDE_PROJECT_DIR="$repo"
echo x >>"$repo/app.txt"
run_hook "$repo/.claude/hooks/stop.sh"
assert_rc 0 "위키가 아예 없으면 막지 않는다"

summary
