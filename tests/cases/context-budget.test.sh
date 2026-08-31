#!/usr/bin/env bash
# 컨텍스트 비용 규율 — 주입 상한, CLAUDE.md 예산, 생성물 읽기 차단
#
# 이 세 가지는 "세면 알 수 있는 것"이라 산문 규칙으로 두면 조용히 드리프트한다.
# 주입과 CLAUDE.md는 세션의 **매 턴** 다시 전송되므로, 커지면 비용이 턴 수만큼 곱해진다.
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

# ── 1. SessionStart 주입 상한 ───────────────────────────────────────────────
repo="$(mk_repo)"
install_conf "$repo" testproj in-repo
export CLAUDE_PROJECT_DIR="$repo"
mkdir -p "$repo/llm-wiki"

# 로그 항목 25건, 열린 과제 20건 — 상한(10/8)을 크게 넘긴다
{
	printf '# Log\n\n## 2026-08-27\n'
	for i in $(seq 1 25); do printf -- '- **로그%02d**: 본문\n' "$i"; done
} >"$repo/llm-wiki/log.md"
{
	printf '# 다음 과제\n\n## 열린 과제\n\n'
	for i in $(seq 1 20); do printf -- '### %d. 과제%02d\n' "$i" "$i"; done
} >"$repo/llm-wiki/Next-Tasks.md"

run_hook "$HOOKS/session-start.sh"
assert_rc 0 "상한을 넘겨도 exit 0"
assert_json "상한을 넘겨도 유효 JSON"
assert_ctx_has "로그01" "상한 안의 로그는 주입된다"
assert_ctx_has "로그10" "상한 경계(10번째)까지 주입된다"
assert_ctx_lacks "로그11" "상한을 넘는 로그는 주입하지 않는다"
assert_ctx_has "과제08" "상한 경계(8번째) 과제까지 주입된다"
assert_ctx_lacks "과제09" "상한을 넘는 과제는 주입하지 않는다"
# 잘린 사실을 숨기면 세션이 "이게 전부"라고 오해한다
assert_ctx_has "…외 15건" "잘린 로그 건수를 알려준다"
assert_ctx_has "…외 12건" "잘린 과제 건수를 알려준다"
assert_ctx_has "llm-wiki/log.md" "나머지를 어디서 읽는지 알려준다"

# 상한 이하면 안내 줄이 붙지 않는다 (오탐 방지)
write_log "$repo/llm-wiki/log.md" 2026-08-27 짧은로그
printf '# 다음 과제\n\n## 열린 과제\n\n### 1. 짧은과제\n' >"$repo/llm-wiki/Next-Tasks.md"
run_hook "$HOOKS/session-start.sh"
assert_ctx_has "짧은로그" "상한 이하면 그대로 주입된다"
assert_ctx_lacks "…외" "상한 이하면 잘림 안내를 붙이지 않는다"

# 프로젝트가 conf.sh 로 상한을 조정할 수 있다
printf 'PROJECT_KEY="testproj"\nWIKI_MODE="in-repo"\nINJECT_MAX_LOG=2\n' \
	>"$repo/.claude/llm-wiki.conf.sh"
{
	printf '# Log\n\n## 2026-08-27\n'
	for i in 1 2 3 4; do printf -- '- **조정%02d**: 본문\n' "$i"; done
} >"$repo/llm-wiki/log.md"
run_hook "$HOOKS/session-start.sh"
assert_ctx_has "조정02" "conf.sh 의 상한이 적용된다"
assert_ctx_lacks "조정03" "conf.sh 의 상한을 넘으면 잘린다"

# ── 2. 생성되는 CLAUDE.md 의 컨텍스트 예산 ──────────────────────────────────
# install.sh 가 직접 계산해 출력한 값을 그대로 읽는다 — 추정 로직을 테스트가 복제하면
# 둘이 갈라져 "테스트만 통과"하는 상태가 생긴다.
budget="$(grep -m1 '^CLAUDE_MD_BUDGET=' "$ROOT/install.sh" | cut -d= -f2)"

check_budget() { # check_budget <설치 출력> <모드 이름>
	local n
	n="$(printf '%s' "$1" | sed -n 's/.*컨텍스트 예산 ~\([0-9]*\)\/.*/\1/p' | head -n1)"
	if [ -z "$n" ]; then
		bad "$2: install.sh 가 CLAUDE.md 토큰 추정을 보고한다" "출력에 예산 줄 없음"
		return
	fi
	ok "$2: install.sh 가 CLAUDE.md 토큰 추정을 보고한다 (~$n)"
	if [ "$n" -le "$budget" ]; then
		ok "$2: 하네스가 배포하는 CLAUDE.md 가 예산($budget) 안에 있다"
	else
		bad "$2: 하네스가 배포하는 CLAUDE.md 가 예산($budget) 안에 있다" \
			"~$n 토큰 — 상세를 위키로 옮기고 링크만 남길 것"
	fi
}

repo_b="$(mk_repo)"
check_budget "$(bash "$ROOT/install.sh" --in-repo testproj "$repo_b")" "in-repo"

repo_c="$(mk_repo)"
vault_c="$(mktemp -d "$TMPROOT/vault-budget.XXXXXX")"
git -C "$vault_c" init -q -b main
check_budget "$(bash "$ROOT/install.sh" testproj "$repo_c" "$vault_c")" "external"

# ── 3. 생성물 읽기 차단 ─────────────────────────────────────────────────────
deny() { jq -r '.permissions.deny // [] | join(" ")' "$1" 2>/dev/null; }
case "$(deny "$repo_b/.claude/settings.json")" in
*node_modules*) ok "새 settings.json 에 생성물 읽기 차단이 들어간다" ;;
*) bad "새 settings.json 에 생성물 읽기 차단이 들어간다" "deny: $(deny "$repo_b/.claude/settings.json")" ;;
esac

# 기존 deny 규칙은 지우지 않고 합집합으로 더한다
repo_d="$(mk_repo)"
mkdir -p "$repo_d/.claude"
echo '{"permissions":{"deny":["Read(./secrets/**)"]}}' >"$repo_d/.claude/settings.json"
bash "$ROOT/install.sh" --in-repo testproj "$repo_d" >/dev/null
merged="$(deny "$repo_d/.claude/settings.harness.json")"
case "$merged" in
*secrets*) ok "사용자가 넣은 deny 규칙을 보존한다" ;;
*) bad "사용자가 넣은 deny 규칙을 보존한다" "deny: $merged" ;;
esac
case "$merged" in
*node_modules*) ok "병합 시 하네스 deny 규칙도 더해진다" ;;
*) bad "병합 시 하네스 deny 규칙도 더해진다" "deny: $merged" ;;
esac

# 재실행이 같은 규칙을 중복으로 쌓지 않는다
cp "$repo_d/.claude/settings.harness.json" "$repo_d/.claude/settings.json"
bash "$ROOT/install.sh" --in-repo testproj "$repo_d" >/dev/null
n_dup="$(jq -r '[.permissions.deny[] | select(. == "Read(./node_modules/**)")] | length' \
	"$repo_d/.claude/settings.harness.json" 2>/dev/null)"
if [ "$n_dup" = 1 ]; then
	ok "재실행해도 deny 규칙이 중복되지 않는다"
else
	bad "재실행해도 deny 규칙이 중복되지 않는다" "node_modules 규칙 ${n_dup}개"
fi

summary
