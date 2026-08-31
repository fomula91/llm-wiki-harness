#!/usr/bin/env bash
# SessionStart 훅 — 파싱 정확도와 "조용히 실패" 경로
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

repo="$(mk_repo)"
install_conf "$repo" testproj in-repo
H="$HOOKS"
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
install_conf "$repo2" testproj external
export CLAUDE_PROJECT_DIR="$repo2"
unset WIKI_ROOT
run_hook "$HOOKS/session-start.sh"
assert_rc 0 "external 모드에서 위키를 못 찾아도 exit 0"
assert_out_has "WIKI_ROOT" "위키를 못 찾으면 원인을 알려준다"
assert_json "진단 메시지도 유효 JSON"

# ── 하네스를 설치하지 않은 프로젝트 ────────────────────────────────────────
# 훅은 이제 플러그인 소속이라 사용자의 **모든** 프로젝트에서 실행된다.
# conf.sh 가 없으면 그 프로젝트는 하네스와 무관하므로 아무 흔적도 남기면 안 된다.
# 여기가 깨지면 무관한 프로젝트마다 잡음이 뜨고 사용자는 플러그인을 꺼버린다.
bare="$(mk_repo)"
mkdir -p "$bare/llm-wiki"
printf '# Log\n\n## 2026-08-27\n- **남의로그**: 본문\n' >"$bare/llm-wiki/log.md"
export CLAUDE_PROJECT_DIR="$bare"
run_hook "$HOOKS/session-start.sh"
assert_rc 0 "하네스 미설치 프로젝트에서 exit 0"
assert_out_empty "하네스 미설치 프로젝트에서는 아무것도 주입하지 않는다"

# ── 마이그레이션 도중: 구버전 훅 사본이 아직 배선돼 있는 프로젝트 ──────────
# settings.json 이 그 사본을 계속 호출 중일 수 있다. 두 벌이 함께 돌면 기억이
# 두 번 주입되므로 플러그인 훅은 물러서고, 사본을 지우면 인계받는다.
mig="$(mk_repo)"
install_conf "$mig" testproj in-repo
mkdir -p "$mig/llm-wiki" "$mig/.claude/hooks"
printf '# Log\n\n## 2026-08-27\n- **이중주입후보**: 본문\n' >"$mig/llm-wiki/log.md"
printf 'PROJECT_KEY="testproj"\nWIKI_MODE="in-repo"\n' >"$mig/.claude/hooks/llm-wiki.conf.sh"
export CLAUDE_PROJECT_DIR="$mig"
run_hook "$HOOKS/session-start.sh"
assert_rc 0 "구버전 사본이 남아 있어도 exit 0"
assert_out_empty "구버전 사본이 배선돼 있으면 플러그인 훅은 물러선다"

rm -rf "$mig/.claude/hooks"
run_hook "$HOOKS/session-start.sh"
assert_ctx_has "이중주입후보" "사본을 지우면 플러그인 훅이 인계받는다"

summary
