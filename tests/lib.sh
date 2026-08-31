#!/usr/bin/env bash
# 테스트 공용 — assert 헬퍼 + 픽스처 빌더
#
# 훅은 플러그인 안에서 실행되므로($HOOKS) 테스트도 사본을 만들지 않고 그 파일을 그대로
# 돌린다 — 검증 대상과 배포본이 같은 파일이라 드리프트할 여지가 없다.
# 프로젝트에는 실제 배포와 똑같이 .claude/llm-wiki.conf.sh 하나만 심는다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 플러그인이 실행하는 바로 그 훅 (${CLAUDE_PLUGIN_ROOT}/hooks). 케이스 파일들이 쓴다 —
# shellcheck 은 파일 단위로 보므로 여기서는 미사용으로 보인다.
# shellcheck disable=SC2034
HOOKS="$ROOT/hooks"
TMPROOT="$ROOT/tests/.tmp"
mkdir -p "$TMPROOT"

PASS=0
FAIL=0
OUT=""
RC=0

ok() {
	PASS=$((PASS + 1))
	printf '  \033[32m✓\033[0m %s\n' "$1"
}
bad() {
	FAIL=$((FAIL + 1))
	printf '  \033[31m✗\033[0m %s\n      %s\n' "$1" "$2"
}

# ── assert ──────────────────────────────────────────────────────────────────
run_hook() { # run_hook <script-path> — 호출 전에 필요한 env를 export 해 둘 것
	OUT="$(bash "$1" 2>/dev/null)"
	RC=$?
}

# 특정 도구가 없는 PATH로 훅을 돌린다 (무음 실패 경로 검증용).
# bash 자체는 절대경로로 넘긴다 — PATH를 갈아끼우면 bash도 못 찾는다.
run_hook_with_path() { # run_hook_with_path <path-value> <script-path>
	OUT="$(PATH="$1" "$(command -v bash)" "$2" 2>/dev/null)"
	RC=$?
}

assert_rc() { # assert_rc <expected> <desc>
	if [ "$RC" = "$1" ]; then ok "$2"; else bad "$2" "exit $RC (기대 $1)"; fi
}
assert_out_has() { # assert_out_has <needle> <desc>
	case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2" "출력에 '$1' 없음 — 실제: ${OUT:-(빈 출력)}" ;; esac
}
assert_out_lacks() { # assert_out_lacks <needle> <desc>
	case "$OUT" in *"$1"*) bad "$2" "출력에 '$1' 가 있으면 안 됨" ;; *) ok "$2" ;; esac
}
assert_out_empty() { # assert_out_empty <desc>
	if [ -z "$OUT" ]; then ok "$1"; else bad "$1" "출력이 비어야 하는데 있음: $OUT"; fi
}
assert_json() { # assert_json <desc>
	if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then ok "$1"; else bad "$1" "유효 JSON 아님: ${OUT:-(빈 출력)}"; fi
}
# 주입될 additionalContext 본문만 꺼낸다
ctx() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
assert_ctx_has() { # assert_ctx_has <needle> <desc>
	local c; c="$(ctx)"
	case "$c" in *"$1"*) ok "$2" ;; *) bad "$2" "주입 컨텍스트에 '$1' 없음 — 실제:\n$c" ;; esac
}
assert_ctx_lacks() { # assert_ctx_lacks <needle> <desc>
	local c; c="$(ctx)"
	case "$c" in *"$1"*) bad "$2" "주입 컨텍스트에 '$1' 가 있으면 안 됨 — 실제:\n$c" ;; *) ok "$2" ;; esac
}

# ── 픽스처 ──────────────────────────────────────────────────────────────────
_git_init() { # _git_init <dir>
	git -C "$1" init -q -b main
	git -C "$1" config user.email test@example.com
	git -C "$1" config user.name test
}

mk_repo() { # mk_repo -> 경로 출력. 커밋된 가짜 코드 repo
	local d
	d="$(mktemp -d "$TMPROOT/repo.XXXXXX")"
	_git_init "$d"
	echo code >"$d/app.txt"
	git -C "$d" add -A
	git -C "$d" commit -qm init
	printf '%s' "$d"
}

# 하네스가 설치된 프로젝트를 만든다 = conf.sh 하나를 심는다.
# 이 파일의 존재가 훅에게 "여기서 동작하라"는 유일한 신호다.
install_conf() { # install_conf <repo> <key> <mode>
	mkdir -p "$1/.claude"
	printf 'PROJECT_KEY="%s"\nWIKI_MODE="%s"\n' "$2" "$3" >"$1/.claude/llm-wiki.conf.sh"
}

# 실제 템플릿을 렌더해 위키 디렉터리를 만든다 (계약 테스트의 근거)
copy_template() { # copy_template <dst> [key] [date]
	local dst="$1" key="${2:-testproj}" date="${3:-$(date +%F)}" f
	mkdir -p "$dst/Decisions" "$dst/Reference" "$dst/Summaries"
	for f in index.md log.md Next-Tasks.md Context.md OpenQuestions.md; do
		sed -e "s|__PROJECT_KEY__|$key|g" -e "s|__DATE__|$date|g" \
			"$ROOT/wiki-side/project-template/$f" >"$dst/$f"
	done
}

mk_vault() { # mk_vault <key> -> 경로 출력. upstream(bare remote)까지 붙은 위키 vault
	local d bare
	d="$(mktemp -d "$TMPROOT/vault.XXXXXX")"
	bare="$(mktemp -d "$TMPROOT/bare.XXXXXX")"
	git -C "$bare" init -q --bare -b main
	_git_init "$d"
	copy_template "$d/Projects/$1" "$1"
	git -C "$d" add -A
	git -C "$d" commit -qm init
	git -C "$d" remote add origin "$bare"
	git -C "$d" push -q -u origin main
	printf '%s' "$d"
}

# 0.4.0 시절 레이아웃의 프로젝트를 만든다 — 훅 사본 + 그것을 부르는 settings.json.
# 사본의 내용은 중요하지 않다: 마이그레이션은 파일의 **존재**와 settings.json 의 호출로
# 상태를 판단하고, 이 사본을 실행하지 않는다. 그래서 자리만 채운다
# (실제 구버전 파일을 git 에서 꺼내면 태그를 안 받는 CI 체크아웃에서 조용히 달라진다).
mk_legacy_repo() { # mk_legacy_repo <key> [mode] -> 경로 출력
	local d f key="$1" mode="${2:-in-repo}"
	d="$(mk_repo)"
	mkdir -p "$d/.claude/hooks"
	for f in lib.sh session-start.sh stop.sh; do
		printf '#!/usr/bin/env bash\n# 0.4.0 시절 훅 사본 (테스트 픽스처 — 실행되지 않는다)\nexit 0\n' \
			>"$d/.claude/hooks/$f"
	done
	printf 'PROJECT_KEY="%s"\nWIKI_MODE="%s"\n' "$key" "$mode" >"$d/.claude/hooks/llm-wiki.conf.sh"
	cat >"$d/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh\"" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/stop.sh\"" } ] } ],
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo 남의훅" } ] } ]
  }
}
JSON
	printf '%s' "$d"
}

summary() { # 각 케이스 파일 끝에서 호출
	printf '  → %d passed, %d failed\n' "$PASS" "$FAIL"
	[ "$FAIL" -eq 0 ]
}

# log.md 를 명시적 날짜/제목으로 다시 쓴다 (Stop 훅 날짜 판정 테스트용)
write_log() { # write_log <log.md> <date> <title>
	printf '# Log\n\n## %s\n- **%s**: 내용\n' "$2" "$3" >"$1"
}
