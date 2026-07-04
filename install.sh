#!/usr/bin/env bash
# LLM-WIKI 하네스 보일러플레이트 설치 스크립트
# 사용법: ./install.sh <project-key> <code-repo-path> <wiki-root>
#   project-key    위키 Projects/ 아래 디렉터리명 (예: my-app)
#   code-repo-path 코드 저장소 절대경로 (예: ~/Desktop/code/my-app)
#   wiki-root      위키 vault 절대경로 (예: ~/Desktop/LLM-WIKI/JACOB-LLM-WIKI)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

if [ $# -ne 3 ]; then
  sed -n '2,6p' "$0"; exit 1
fi

KEY="$1"
REPO="$(cd "$2" && pwd)"
WIKI="$(cd "$3" && pwd)"
TODAY="$(date +%F)"

command -v jq >/dev/null || echo "⚠️  jq가 없습니다. SessionStart 기억 주입 훅이 jq를 사용합니다 — 'brew install jq' 권장."
[ -d "$WIKI/.git" ] || echo "⚠️  $WIKI 가 git repo가 아닙니다. 자동 pull/push·미저장 감지 훅은 git 기반입니다."

render() { # render <src> <dst>
  sed -e "s|__PROJECT_KEY__|$KEY|g" \
      -e "s|__WIKI_ROOT_DEFAULT__|$WIKI|g" \
      -e "s|__DATE__|$TODAY|g" "$1" > "$2"
  echo "  생성: $2"
}

echo "── 1. 위키 쪽: Projects/$KEY/ 스켈레톤"
DST="$WIKI/Projects/$KEY"
mkdir -p "$DST/Decisions" "$DST/Reference" "$DST/Summaries"
for f in index.md log.md Next-Tasks.md Context.md OpenQuestions.md \
         Decisions/0000-adr-template.md Reference/README.md Summaries/README.md; do
  if [ -e "$DST/$f" ]; then
    echo "  건너뜀(이미 존재): $DST/$f"
  else
    render "$HERE/wiki-side/project-template/$f" "$DST/$f"
  fi
done

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

echo "── 3. 코드 repo 쪽: 훅 + CLAUDE.md"
mkdir -p "$REPO/.claude"
if [ -e "$REPO/.claude/settings.json" ]; then
  render "$HERE/project-side/settings.json" "$REPO/.claude/settings.harness.json"
  echo "  ⚠️  settings.json이 이미 있어 settings.harness.json으로 생성 — hooks 블록을 수동 병합하세요."
else
  render "$HERE/project-side/settings.json" "$REPO/.claude/settings.json"
fi
render "$HERE/project-side/settings.local.json.example" "$REPO/.claude/settings.local.json.example"
if [ -e "$REPO/CLAUDE.md" ]; then
  render "$HERE/project-side/CLAUDE.base.md" "$REPO/CLAUDE.harness.md"
  echo "  ⚠️  CLAUDE.md가 이미 있어 CLAUDE.harness.md로 생성 — 'LLM-WIKI 연동 규칙' 섹션을 수동 병합하세요."
else
  render "$HERE/project-side/CLAUDE.base.md" "$REPO/CLAUDE.md"
fi

cat <<EOF

✅ 설치 완료: $KEY

남은 수동 단계:
1. $REPO/.claude/settings.local.json.example 을 settings.local.json 으로 복사
   (머신별 WIKI_ROOT env + additionalDirectories — git 커밋 안 됨. 다른 머신에서는 경로만 수정)
2. $REPO/CLAUDE.md 의 "검증 단계" TODO 섹션을 이 프로젝트에 맞게 작성
3. 위키 $WIKI/Projects/$KEY/Context.md 채우기 + 루트 index.md에 프로젝트 링크 추가
4. 위키 변경 커밋·푸시 (다른 머신과 동기화)
EOF
