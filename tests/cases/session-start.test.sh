#!/usr/bin/env bash
# SessionStart 훅 — 파싱 정확도와 "조용히 실패" 경로
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

repo="$(mk_repo)"
install_hooks "$repo" testproj in-repo
H="$repo/.claude/hooks"
export CLAUDE_PROJECT_DIR="$repo"
mkdir -p "$repo/llm-wiki"

# 두 날짜 섹션 + blockquote 설명 + 본문이 있는 로그
cat >"$repo/llm-wiki/log.md" <<'EOF'
# Log

> **형식 계약**: 항목은 `- **제목**: 내용`.
- **블록쿼트밖가짜**: 첫 날짜 섹션 앞의 항목

## 2026-08-27
- **최신작업**: 아주 긴 본문 내용이 여기 들어간다
- **최신작업둘**: 본문

## 2026-08-01
- **오래된작업**: 본문
EOF

cat >"$repo/llm-wiki/Next-Tasks.md" <<'EOF'
# 다음 과제

> 형식: `## 열린 과제` 아래 `### N. 제목`

## 열린 과제

### 1. 살아있는과제
무엇 → 왜 → 완료 기준

## 종료 기록

### 9. 끝난과제
EOF

run_hook "$H/session-start.sh"
assert_rc 0 "정상 경로는 exit 0"
assert_json "출력이 유효한 훅 JSON"
assert_ctx_has "최신작업" "최신 날짜 섹션의 제목을 주입한다"
assert_ctx_has "최신작업둘" "최신 섹션의 항목을 모두 주입한다"
assert_ctx_lacks "오래된작업" "이전 날짜 섹션은 주입하지 않는다"
assert_ctx_lacks "아주 긴 본문" "제목만 뽑고 본문은 흘리지 않는다"
assert_ctx_lacks "블록쿼트밖가짜" "첫 날짜 섹션 앞의 항목은 주입하지 않는다"
assert_ctx_has "살아있는과제" "열린 과제를 주입한다"
assert_ctx_lacks "끝난과제" "종료 기록 섹션의 ### 은 주입하지 않는다"
assert_ctx_lacks "형식:" "blockquote 형식 설명은 주입하지 않는다"

# 날짜 섹션이 하나도 없는 로그 — 깨지지 않아야 한다
printf '# Log\n\n아직 기록 없음\n' >"$repo/llm-wiki/log.md"
run_hook "$H/session-start.sh"
assert_rc 0 "빈 로그에도 exit 0"
assert_json "빈 로그에도 유효 JSON"

# 위키가 없으면 무음
rm -rf "$repo/llm-wiki"
run_hook "$H/session-start.sh"
assert_rc 0 "위키 없으면 exit 0"
assert_out_empty "위키 없으면 아무것도 출력하지 않는다"

# jq가 없으면 깨진 출력 대신 무음 (버그 #2).
# jq만 빠진 PATH를 만든다 — PATH를 통째로 비우면 dirname이 없어서 다른 이유로 죽는다.
mkdir -p "$repo/llm-wiki" && printf '# Log\n\n## 2026-08-27\n- **x**: y\n' >"$repo/llm-wiki/log.md"
nojq="$(mktemp -d "$TMPROOT/nojq.XXXXXX")"
ln -s "$(command -v dirname)" "$nojq/dirname"
run_hook_with_path "$nojq" "$H/session-start.sh"
assert_rc 0 "jq 없으면 exit 0"
assert_out_empty "jq 없으면 깨진 출력을 뱉지 않는다"

# external 모드에서 WIKI_ROOT 미설정 → 무음이 아니라 진단 (버그 #3 후속)
repo2="$(mk_repo)"
install_hooks "$repo2" testproj external
export CLAUDE_PROJECT_DIR="$repo2"
unset WIKI_ROOT
run_hook "$repo2/.claude/hooks/session-start.sh"
assert_rc 0 "external 모드에서 위키를 못 찾아도 exit 0"
assert_out_has "WIKI_ROOT" "위키를 못 찾으면 원인을 알려준다"
assert_json "진단 메시지도 유효 JSON"

summary
