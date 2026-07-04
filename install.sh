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

render() { # render <src> <dst>
  sed -e "s|__PROJECT_KEY__|$KEY|g" \
      -e "s|__WIKI_ROOT_DEFAULT__|$WIKI|g" \
      -e "s|__DATE__|$TODAY|g" "$1" > "$2"
  echo "  생성: $2"
}

render_claude_md() { # render_claude_md <rules-variant> <dst>
  { cat "$HERE/project-side/CLAUDE.guidelines.md"; printf '\n---\n\n'; \
    cat "$HERE/project-side/$1"; printf '\n---\n\n'; \
    cat "$HERE/project-side/CLAUDE.verify-todo.md"; } \
    | sed -e "s|__PROJECT_KEY__|$KEY|g" -e "s|__DATE__|$TODAY|g" > "$2"
  echo "  생성: $2"
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
  SETTINGS_SRC="$HERE/project-side/settings.json"
  RULES=wiki-rules.external.md
else
  echo "── 1. repo 내장 위키: llm-wiki/ 스켈레톤"
  copy_skeleton "$REPO/llm-wiki"
  SETTINGS_SRC="$HERE/project-side/settings.in-repo.json"
  RULES=wiki-rules.in-repo.md
fi

echo "── 3. 코드 repo 쪽: 훅 + CLAUDE.md"
mkdir -p "$REPO/.claude"
if [ -e "$REPO/.claude/settings.json" ]; then
  render "$SETTINGS_SRC" "$REPO/.claude/settings.harness.json"
  echo "  ⚠️  settings.json이 이미 있어 settings.harness.json으로 생성 — hooks 블록을 수동 병합하세요."
else
  render "$SETTINGS_SRC" "$REPO/.claude/settings.json"
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
echo "남은 수동 단계:"
if [ "$MODE" = external ]; then
  cat <<EOF
1. $REPO/.claude/settings.local.json.example 을 settings.local.json 으로 복사
   (머신별 WIKI_ROOT env + additionalDirectories — git 커밋 안 됨. 다른 머신에서는 경로만 수정)
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
