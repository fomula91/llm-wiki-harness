#!/usr/bin/env bash
# 구버전(인라인 셸 훅) → 현행(스크립트 호출) 마이그레이션
#
# 이미 설치한 사용자는 플러그인을 업데이트해도 자기 프로젝트의 훅이 갱신되지 않는다.
# /llm-wiki-init 재실행이 유일한 경로이고, 그때 구버전 인라인 훅을 지우지 않으면
# 훅이 이중 발동한다. 그 제거를 모델의 판단이 아니라 install.sh가 하도록 만든 것을 여기서 고정한다.
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

jqf() { jq -r "$2" "$1" 2>/dev/null; }
expect_eq() { # expect_eq <actual> <expected> <desc>
	if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "실제 '$1' (기대 '$2')"; fi
}

repo="$(mk_repo)"
mkdir -p "$repo/.claude"

# 구버전 하네스가 남긴 형태 + 하네스와 무관한 제3의 훅
cat >"$repo/.claude/settings.json" <<'JSON'
{
  "permissions": { "additionalDirectories": ["/somewhere"] },
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "W=\"$CLAUDE_PROJECT_DIR/llm-wiki\"; grep -m1 '^## [0-9]' \"$W/log.md\"; awk '/^## 열린 과제/' \"$W/Next-Tasks.md\"" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "grep -q \"^## $(date +%F)\" llm-wiki/log.md && exit 0; exit 2" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo 남의훅" } ] }
    ]
  }
}
JSON

bash "$ROOT/install.sh" --in-repo testproj "$repo" >/dev/null
H="$repo/.claude/settings.harness.json"

if [ -f "$H" ]; then ok "병합본 settings.harness.json 이 생성된다"; else bad "병합본 settings.harness.json 이 생성된다" "없음"; fi
if jq -e . "$H" >/dev/null 2>&1; then ok "병합본이 유효 JSON"; else bad "병합본이 유효 JSON" "파싱 실패"; fi

# 원본은 건드리지 않는다
if grep -qF "남의훅" "$repo/.claude/settings.json"; then ok "원본 settings.json 은 그대로 둔다"; else bad "원본 settings.json 은 그대로 둔다" "원본이 바뀜"; fi

# 구버전 인라인 훅이 사라졌는가
expect_eq "$(jqf "$H" '[.hooks.SessionStart[].hooks[].command] | map(select(test("Next-Tasks|awk"))) | length')" 0 \
	"구버전 인라인 SessionStart 훅이 제거된다"
expect_eq "$(jqf "$H" '[.hooks.Stop[].hooks[].command] | map(select(test("date \\+%F"))) | length')" 0 \
	"구버전 인라인 Stop 훅이 제거된다"

# 현행 훅이 정확히 하나씩 붙었는가
expect_eq "$(jqf "$H" '.hooks.SessionStart | length')" 1 "SessionStart 훅 그룹이 정확히 1개"
expect_eq "$(jqf "$H" '.hooks.Stop | length')" 1 "Stop 훅 그룹이 정확히 1개"
if jqf "$H" '.hooks.SessionStart[0].hooks[0].command' | grep -q 'hooks/session-start.sh'; then
	ok "현행 스크립트 호출 훅으로 교체된다"
else bad "현행 스크립트 호출 훅으로 교체된다" "$(jqf "$H" '.hooks.SessionStart[0].hooks[0].command')"; fi

# 하네스와 무관한 것은 살아남는가
expect_eq "$(jqf "$H" '.hooks.PreToolUse[0].hooks[0].command')" "echo 남의훅" "무관한 훅은 보존된다"
expect_eq "$(jqf "$H" '.permissions.additionalDirectories[0]')" "/somewhere" "훅 밖의 설정도 보존된다"

# 이미 마이그레이션된 설정에 다시 돌려도 중복되지 않는다
cp "$H" "$repo/.claude/settings.json"
bash "$ROOT/install.sh" --in-repo testproj "$repo" >/dev/null
expect_eq "$(jqf "$H" '.hooks.SessionStart | length')" 1 "재실행해도 SessionStart 가 중복되지 않는다"
expect_eq "$(jqf "$H" '.hooks.Stop | length')" 1 "재실행해도 Stop 이 중복되지 않는다"
expect_eq "$(jqf "$H" '.hooks.PreToolUse[0].hooks[0].command')" "echo 남의훅" "재실행해도 무관한 훅이 살아남는다"

summary
