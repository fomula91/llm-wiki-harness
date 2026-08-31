#!/usr/bin/env bash
# LLM-WIKI 하네스 설치 스크립트
#
# 외부 vault 모드 (위키가 코드 밖 Obsidian vault, add-dir로 연결):
#   ./install.sh <project-key> <code-repo-path> <wiki-root>
# repo 내장 모드 (위키가 코드 repo 안 llm-wiki/, 코드와 함께 커밋):
#   ./install.sh --in-repo <project-key> <code-repo-path>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

MODE=external
if [ "${1:-}" = "--in-repo" ]; then MODE=in-repo; shift; fi

if { [ "$MODE" = external ] && [ $# -ne 3 ]; } || { [ "$MODE" = in-repo ] && [ $# -ne 2 ]; }; then
  sed -n '2,8p' "$0"; exit 1
fi

KEY="$1"
REPO="$(cd "$2" && pwd)"
WIKI=""
[ "$MODE" = external ] && WIKI="$(cd "$3" && pwd)"
TODAY="$(date +%F)"

command -v jq >/dev/null || echo "⚠️  jq가 없습니다. SessionStart 기억 주입 훅이 jq를 사용합니다 — 'brew install jq' 권장."

# sed 치환값 이스케이프: 구분자 |, 백슬래시, & (치환문에서 매치 전체로 확장된다)
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() { # render <src> <dst>
  sed -e "s|__PROJECT_KEY__|$(sed_escape "$KEY")|g" \
      -e "s|__WIKI_ROOT_DEFAULT__|$(sed_escape "$WIKI")|g" \
      -e "s|__DATE__|$(sed_escape "$TODAY")|g" "$1" > "$2"
  echo "  생성: $2"
}

# CLAUDE.md 는 세션의 **매 턴** 다시 전송된다 — 여기서 100토큰은 30턴 세션에서 3,000토큰이다.
# 그래서 크기를 설치 때 눈에 보이게 만들고 상한을 둔다.
CLAUDE_MD_BUDGET=1500

# 대략의 토큰 추정: ASCII 4바이트당 1토큰, 그 외(한글 등) 3바이트당 1토큰.
# 정확한 토크나이저가 아니라 "커졌는지"를 보는 눈금이다 — 문자 단위 처리는 BSD/GNU awk 에서
# 멀티바이트 동작이 갈리므로, 어디서나 같은 값이 나오도록 바이트만 센다.
estimate_tokens() { # estimate_tokens <file>
  local total ascii
  total=$(wc -c <"$1")
  ascii=$(LC_ALL=C tr -dc '\000-\177' <"$1" | wc -c)
  echo $(( ascii / 4 + (total - ascii) / 3 ))
}

render_claude_md() { # render_claude_md <rules-variant> <dst>
  { cat "$HERE/project-side/CLAUDE.guidelines.md"; printf '\n---\n\n'; \
    cat "$HERE/project-side/$1"; printf '\n---\n\n'; \
    cat "$HERE/project-side/CLAUDE.verify-todo.md"; } \
    | sed -e "s|__PROJECT_KEY__|$(sed_escape "$KEY")|g" -e "s|__DATE__|$(sed_escape "$TODAY")|g" > "$2"
  local n; n=$(estimate_tokens "$2")
  echo "  생성: $2  (컨텍스트 예산 ~${n}/${CLAUDE_MD_BUDGET}토큰 — 매 턴 전송됨)"
  if [ "$n" -gt "$CLAUDE_MD_BUDGET" ]; then
    echo "  ⚠️  CLAUDE.md가 예산을 넘습니다. 상세 설명은 위키로 옮기고 여기엔 링크만 남기세요."
  fi
}

copy_skeleton() { # copy_skeleton <dst-dir>
  local DST="$1"
  mkdir -p "$DST/Decisions" "$DST/Reference" "$DST/Summaries"
  for f in index.md log.md Next-Tasks.md Context.md OpenQuestions.md \
           Decisions/0000-adr-template.md Reference/README.md Summaries/README.md; do
    if [ -e "$DST/$f" ]; then
      echo "  건너뜀(이미 존재): $DST/$f"
    else
      render "$HERE/wiki-side/project-template/$f" "$DST/$f"
    fi
  done
}

# 훅 본체는 프로젝트로 복사하지 않는다 — 플러그인 안에서 그대로 실행된다(hooks/hooks.json).
# 프로젝트에 남는 것은 이 설정 파일 하나뿐이고, 그 존재가 "여기 하네스가 설치됨"의 표식이다.
# 사본이 없으므로 플러그인을 업데이트하면 모든 프로젝트가 즉시 최신 훅을 쓴다.
write_conf() { # write_conf <dst .claude dir>
  mkdir -p "$1"
  cat > "$1/llm-wiki.conf.sh" <<EOF
# LLM-WIKI 하네스 설정 — install.sh가 생성한다. 플러그인 훅이 읽는 유일한 설정 파일이며,
# 이 파일이 있어야 훅이 이 프로젝트에서 동작한다(없으면 훅은 조용히 빠진다).
# 위키 경로는 여기 두지 않는다: 머신별 경로의 단일 출처는 .claude/settings.local.json 의 env.WIKI_ROOT.
PROJECT_KEY="$KEY"
WIKI_MODE="$MODE"

# 세션 시작에 주입할 최대 건수. 주입은 그 세션의 매 턴 다시 전송되므로 상한이 곧 비용 상한이다.
# 넘치는 만큼은 "…외 N건"으로 알리고, 세션이 필요할 때 위키를 직접 읽는다.
INJECT_MAX_LOG=10
INJECT_MAX_TASKS=8
EOF
  echo "  생성: $1/llm-wiki.conf.sh"
}

# 구버전(0.4.0 이하)이 프로젝트에 심어 둔 훅 사본. 지우지는 않는다 —
# 그 사본을 가리키는 settings.json 을 사용자가 아직 교체하지 않았을 수 있고,
# 없는 파일을 호출하면 매 세션 에러가 난다. 교체 후 지우도록 안내만 한다.
legacy_hooks_dir() { # legacy_hooks_dir <repo>
  [ -f "$1/.claude/hooks/llm-wiki.conf.sh" ] || [ -f "$1/.claude/hooks/session-start.sh" ]
}

# 프로젝트 settings.json 에 남아 있는 llm-wiki 훅을 알아보는 마커.
# 0.2.0 이전의 인라인 셸과 0.5.0 이전의 스크립트 사본 호출을 모두 잡는다 —
# 훅은 이제 플러그인이 제공하므로 둘 다 걷어내기만 하면 된다.
HARNESS_HOOK_RE='llm-wiki|Next-Tasks\.md|log\.md|\.claude/hooks/(session-start|stop)\.sh'

count_harness_hooks() { # count_harness_hooks <settings.json>
  jq --arg re "$HARNESS_HOOK_RE" '
    [ (.hooks // {}) | to_entries[] | .value[]? | (.hooks // [])[]?
      | select((.command // "") | test($re)) ] | length
  ' "$1" 2>/dev/null || echo 0
}

# 기존 settings.json에서 llm-wiki 훅을 걷어내고 생성물 읽기 차단을 더한 완성본을 만든다.
# 다른 훅과 다른 최상위 키는 그대로 보존한다.
merge_settings() { # merge_settings <existing> <out>
  jq -s --arg re "$HARNESS_HOOK_RE" '
    def is_harness: (.command // "") | test($re);
    .[0] as $cur | .[1] as $new |
    (($cur.hooks // {}) | with_entries(
       .value |= ( map(.hooks |= map(select(is_harness | not)))
                 | map(select(((.hooks // []) | length) > 0)) )
     ) | with_entries(select((.value | length) > 0))) as $clean |
    $cur
    # 훅 엔트리는 더하지 않는다 — 훅은 이제 플러그인이 제공한다(hooks/hooks.json).
    # 구버전이 남긴 호출만 걷어내고, 그래서 비게 된 이벤트 키는 지운다.
    | (if ($clean | length) > 0 then .hooks = $clean else del(.hooks) end)
    # 생성물 읽기 차단은 합집합으로 더한다 — 사용자가 추가한 deny 규칙을 지우지 않는다.
    | .permissions = ( (.permissions // {})
      | .deny = ( ((.deny // []) + ($new.permissions.deny // [])) | unique ) )
  ' "$1" "$HERE/project-side/settings.json" > "$2"
}

if [ "$MODE" = external ]; then
  [ -d "$WIKI/.git" ] || echo "⚠️  $WIKI 가 git repo가 아닙니다. 자동 pull/push·미저장 감지 훅은 git 기반입니다."

  echo "── 1. 위키 쪽: Projects/$KEY/ 스켈레톤"
  copy_skeleton "$WIKI/Projects/$KEY"

  echo "── 2. 위키 쪽: CLAUDE.md + 자동 pull/push 훅"
  if [ -e "$WIKI/CLAUDE.md" ]; then
    echo "  건너뜀(이미 존재): $WIKI/CLAUDE.md — 필요하면 wiki-side/CLAUDE.md와 수동 병합"
  else
    cp "$HERE/wiki-side/CLAUDE.md" "$WIKI/CLAUDE.md"; echo "  생성: $WIKI/CLAUDE.md"
  fi
  mkdir -p "$WIKI/.claude"
  if [ -e "$WIKI/.claude/settings.json" ]; then
    echo "  건너뜀(이미 존재): $WIKI/.claude/settings.json — 필요하면 wiki-side/settings.json과 수동 병합"
  else
    cp "$HERE/wiki-side/settings.json" "$WIKI/.claude/settings.json"; echo "  생성: $WIKI/.claude/settings.json"
  fi
  RULES=wiki-rules.external.md
else
  echo "── 1. repo 내장 위키: llm-wiki/ 스켈레톤"
  copy_skeleton "$REPO/llm-wiki"
  RULES=wiki-rules.in-repo.md
fi

echo "── 3. 코드 repo 쪽: 설정 + CLAUDE.md"
mkdir -p "$REPO/.claude"
write_conf "$REPO/.claude"
if [ -e "$REPO/.claude/settings.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    OLD_N="$(count_harness_hooks "$REPO/.claude/settings.json")"
    merge_settings "$REPO/.claude/settings.json" "$REPO/.claude/settings.harness.json"
    echo "  생성: $REPO/.claude/settings.harness.json"
    if [ "${OLD_N:-0}" -gt 0 ]; then
      echo "  ⚠️  settings.json의 llm-wiki 훅 ${OLD_N}개를 제거한 결과입니다 — 훅은 이제 플러그인이 제공합니다."
    else
      echo "  ⚠️  settings.json이 이미 있어 병합 결과를 별도 파일로 만들었습니다."
    fi
    echo "     llm-wiki 외의 훅과 설정은 그대로 보존됩니다 — 확인 후 settings.json으로 교체하세요."
  else
    cp "$HERE/project-side/settings.json" "$REPO/.claude/settings.harness.json"
    echo "  ⚠️  jq가 없어 자동 병합을 못 했습니다 — settings.harness.json을 참고해 수동 병합하세요."
  fi
else
  cp "$HERE/project-side/settings.json" "$REPO/.claude/settings.json"
  echo "  생성: $REPO/.claude/settings.json"
fi
if [ "$MODE" = external ]; then
  render "$HERE/project-side/settings.local.json.example" "$REPO/.claude/settings.local.json.example"
fi
if [ -e "$REPO/CLAUDE.md" ]; then
  render_claude_md "$RULES" "$REPO/CLAUDE.harness.md"
  echo "  ⚠️  CLAUDE.md가 이미 있어 CLAUDE.harness.md로 생성 — '연동 규칙' 섹션을 수동 병합하세요."
else
  render_claude_md "$RULES" "$REPO/CLAUDE.md"
fi

echo ""
echo "✅ 설치 완료: $KEY ($MODE 모드)"
echo ""
echo "ℹ️  훅 본체는 플러그인 안에서 실행됩니다 — 프로젝트에는 llm-wiki.conf.sh 만 남습니다."
echo "   앞으로는 플러그인만 업데이트하면 모든 프로젝트가 최신 훅을 씁니다."
if legacy_hooks_dir "$REPO"; then
  echo ""
  echo "⚠️  구버전 훅 사본이 남아 있습니다: $REPO/.claude/hooks/"
  echo "   이 디렉터리가 남아 있는 동안 플러그인 훅은 물러섭니다(이중 발동 방지) — 즉 지금은 훅이 돌지 않습니다."
  echo "   다음 한 줄이 나머지를 순서대로 처리하고 결과를 검증합니다:"
  echo "       bash $HERE/migrate.sh $REPO"
  echo "   손으로 한다면: ① settings.json을 병합본으로 교체 → ② .claude/hooks/ 삭제 (순서 필수)."
  echo "   자세한 내용: $HERE/MIGRATION.md"
fi
echo ""
echo "ℹ️  settings.json 의 permissions.deny 가 생성물(node_modules·dist·build·coverage·.next·.cache)"
echo "   읽기를 막아 컨텍스트 낭비를 줄입니다. 이 프로젝트에서 읽어야 하는 경로가 있으면 지우세요."
echo ""
echo "남은 수동 단계:"
if [ "$MODE" = external ]; then
  cat <<EOF
1. $REPO/.claude/settings.local.json.example 을 settings.local.json 으로 복사
   (머신별 WIKI_ROOT env + additionalDirectories — git 커밋 안 됨. 다른 머신에서는 경로만 수정)
   ※ 이 파일이 없으면 훅이 위키를 찾지 못하고 세션 시작 시 경고만 뜹니다.
2. $REPO/CLAUDE.md 의 "검증 단계" TODO 섹션을 이 프로젝트에 맞게 작성
3. 위키 $WIKI/Projects/$KEY/Context.md 채우기 + 루트 index.md에 프로젝트 링크 추가
4. 위키 변경 커밋·푸시 (다른 머신과 동기화)
EOF
else
  cat <<EOF
1. $REPO/CLAUDE.md 의 "검증 단계" TODO 섹션을 이 프로젝트에 맞게 작성
2. $REPO/llm-wiki/Context.md 채우기
3. llm-wiki/ 와 .claude/ 를 코드와 함께 커밋
EOF
fi
