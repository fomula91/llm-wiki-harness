#!/usr/bin/env bash
# 구버전(인라인 셸 훅) → 현행(스크립트 호출) 마이그레이션
#
# 훅은 이제 플러그인이 제공한다. 프로젝트 settings.json 에 남은 구버전 호출
# (0.2.0 이전의 인라인 셸, 0.5.0 이전의 스크립트 사본)을 걷어내지 않으면 훅이 이중 발동한다.
# 그 제거를 모델의 판단이 아니라 install.sh 가 하도록 만든 것을 여기서 고정한다.
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
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/stop.sh\"" } ] }
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
expect_eq "$(jqf "$H" '[(.hooks.SessionStart // [])[].hooks[].command] | map(select(test("Next-Tasks|awk"))) | length')" 0 \
	"구버전 인라인 SessionStart 훅이 제거된다"
expect_eq "$(jqf "$H" '[(.hooks.Stop // [])[].hooks[].command] | map(select(test("date \\+%F"))) | length')" 0 \
	"구버전 인라인 Stop 훅이 제거된다"

# 0.5.0 식 훅 사본 호출도 걷어낸다
expect_eq "$(jqf "$H" '[.hooks.SessionEnd // [] | .[].hooks[].command] | length')" 0 \
	"구버전 스크립트 사본 호출도 제거된다"

# 훅은 플러그인이 제공하므로 프로젝트에는 하나도 다시 붙지 않는다
expect_eq "$(jqf "$H" '.hooks.SessionStart // [] | length')" 0 "SessionStart 훅이 다시 붙지 않는다"
expect_eq "$(jqf "$H" '.hooks.Stop // [] | length')" 0 "Stop 훅이 다시 붙지 않는다"
# 비게 된 이벤트 키는 남기지 않는다 (빈 배열이 굴러다니면 다음 병합이 헷갈린다)
expect_eq "$(jqf "$H" '.hooks | has("Stop")')" false "비게 된 이벤트 키는 지운다"

# 하네스와 무관한 것은 살아남는가
expect_eq "$(jqf "$H" '.hooks.PreToolUse[0].hooks[0].command')" "echo 남의훅" "무관한 훅은 보존된다"
expect_eq "$(jqf "$H" '.permissions.additionalDirectories[0]')" "/somewhere" "훅 밖의 설정도 보존된다"

# 이미 마이그레이션된 설정에 다시 돌려도 결과가 같다 (멱등)
cp "$H" "$repo/.claude/settings.json"
bash "$ROOT/install.sh" --in-repo testproj "$repo" >/dev/null
expect_eq "$(jqf "$H" '.hooks.SessionStart // [] | length')" 0 "재실행해도 훅이 되살아나지 않는다"
expect_eq "$(jqf "$H" '.hooks.PreToolUse[0].hooks[0].command')" "echo 남의훅" "재실행해도 무관한 훅이 살아남는다"

summary
