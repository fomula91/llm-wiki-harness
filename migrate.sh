#!/usr/bin/env bash
# LLM-WIKI 하네스 마이그레이션 (구버전 훅 사본 → 플러그인 훅)
#
#   ./migrate.sh --check [<repo>...]   각 프로젝트의 상태만 보고 (기본: 현재 디렉터리)
#   ./migrate.sh --scan <root>...      하위에서 하네스 프로젝트를 찾아 상태 보고
#   ./migrate.sh <repo>...             실제로 마이그레이션 (settings.json 은 .bak 을 남기고 교체)
#
# 마이그레이션의 위험은 "덜 끝난 채로 멈추는 것"이다. ②까지만 하면 하네스는 꺼져 있고
# 아무 신호도 없다 — 세션은 멀쩡히 돌아가므로 사람은 끝난 줄 안다.
# 그래서 이 스크립트는 절차를 안내하지 않고 끝까지 수행한 뒤 결과 상태를 검증해 보고한다.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

NEW_CONF_REL=".claude/llm-wiki.conf.sh"
OLD_CONF_REL=".claude/hooks/llm-wiki.conf.sh"

# ── 상태 판별 ───────────────────────────────────────────────────────────────
# none    하네스 미설치
# legacy  구버전 사본이 배선된 채 동작 중
# off     사본은 남았는데 settings.json 이 더는 부르지 않음 → 훅이 하나도 안 도는 상태
# current 신버전 (플러그인 훅)
harness_state() { # harness_state <repo>
  local r="$1" s="$1/.claude/settings.json"
  if [ -f "$r/$OLD_CONF_REL" ]; then
    # settings.json 이 아직 사본을 호출하는가. 호출하면 구버전이 그대로 도는 중이고,
    # 아니면 사본만 남아 플러그인 훅까지 물러선(=꺼진) 상태다.
    if [ -f "$s" ] && grep -q '\.claude/hooks/' "$s" 2>/dev/null; then echo legacy; else echo off; fi
  elif [ -f "$r/$NEW_CONF_REL" ]; then
    echo current
  else
    echo none
  fi
}

describe() { # describe <state>
  case "$1" in
  none) echo "하네스 미설치" ;;
  legacy) echo "구버전 — 훅 사본이 동작 중 (마이그레이션 필요)" ;;
  off) echo "⚠️  전환 중 — 훅이 하나도 돌지 않음 (마이그레이션 미완)" ;;
  current) echo "신버전 — 플러그인 훅" ;;
  esac
}

report() { # report <repo>
  local st
  st="$(harness_state "$1")"
  printf '%-8s %s\n         %s\n' "[$st]" "$1" "$(describe "$st")"
}

# ── 스캔 ────────────────────────────────────────────────────────────────────
scan() { # scan <root>
  local f r
  # 두 위치 중 어느 conf.sh 든 있으면 그 프로젝트는 하네스와 관련이 있다.
  while IFS= read -r f; do
    r="${f%/.claude/hooks/llm-wiki.conf.sh}"
    r="${r%/.claude/llm-wiki.conf.sh}"
    printf '%s\n' "$r"
  done < <(find "$1" -name llm-wiki.conf.sh -path '*/.claude/*' 2>/dev/null) | sort -u
}

# ── 마이그레이션 ────────────────────────────────────────────────────────────
migrate_one() { # migrate_one <repo>
  local repo="$1" st key mode wiki bak
  repo="$(cd "$repo" && pwd)"
  st="$(harness_state "$repo")"

  case "$st" in
  none) echo "건너뜀(하네스 미설치): $repo"; return 0 ;;
  current) echo "건너뜀(이미 신버전): $repo"; return 0 ;;
  esac

  echo "── 마이그레이션: $repo  [$st]"

  # 키·모드는 구버전 conf.sh 에서 그대로 가져온다 — 다시 묻지 않는다.
  PROJECT_KEY=""; WIKI_MODE=""
  # shellcheck source=/dev/null
  . "$repo/$OLD_CONF_REL"
  key="$PROJECT_KEY"; mode="${WIKI_MODE:-in-repo}"
  [ -n "$key" ] || { echo "  ✗ 구버전 conf.sh 에서 PROJECT_KEY 를 읽지 못했습니다 — 수동 처리 필요"; return 1; }

  # ① install.sh 재실행
  if [ "$mode" = external ]; then
    wiki="${WIKI_ROOT:-}"
    if [ -z "$wiki" ] && [ -f "$repo/.claude/settings.local.json" ] && command -v jq >/dev/null 2>&1; then
      wiki="$(jq -r '.env.WIKI_ROOT // empty' "$repo/.claude/settings.local.json" 2>/dev/null || true)"
    fi
    [ -n "$wiki" ] && [ -d "$wiki" ] || {
      echo "  ✗ external 모드인데 위키 경로를 찾지 못했습니다."
      echo "    WIKI_ROOT=... ./migrate.sh $repo 로 다시 실행하세요."
      return 1
    }
    bash "$HERE/install.sh" "$key" "$repo" "$wiki" >/dev/null
  else
    bash "$HERE/install.sh" --in-repo "$key" "$repo" >/dev/null
  fi
  echo "  ① conf.sh 생성 (key=$key mode=$mode)"

  # ② settings.json 교체 — 사람이 가장 자주 멈추는 지점이라 자동으로 넘긴다. 원본은 남긴다.
  if [ -f "$repo/.claude/settings.harness.json" ]; then
    bak="$repo/.claude/settings.json.bak"
    [ -f "$repo/.claude/settings.json" ] && cp "$repo/.claude/settings.json" "$bak"
    mv "$repo/.claude/settings.harness.json" "$repo/.claude/settings.json"
    echo "  ② settings.json 교체 (원본: $(basename "$bak"))"
  else
    echo "  ② settings.json 교체 불필요"
  fi

  # ③ 사본 삭제 — ② 뒤에만 안전하다. 순서를 뒤집으면 없는 파일을 호출해 매 세션 에러가 난다.
  rm -rf "$repo/.claude/hooks"
  echo "  ③ 구버전 훅 사본 삭제"

  verify "$repo"
}

# 끝났다고 말하기 전에 실제로 끝났는지 본다.
verify() { # verify <repo>
  local repo="$1" st out
  st="$(harness_state "$repo")"
  if [ "$st" != current ]; then
    echo "  ✗ 검증 실패 — 상태가 '$st' 입니다. $(describe "$st")"
    return 1
  fi
  if grep -q '\.claude/hooks/' "$repo/.claude/settings.json" 2>/dev/null; then
    echo "  ✗ 검증 실패 — settings.json 이 아직 훅 사본을 호출합니다."
    return 1
  fi
  echo "  ✓ 신버전 상태"

  # 훅이 실제로 무언가를 주입하는지까지 본다 (위키가 비어 있으면 주입이 없는 게 정상).
  if command -v jq >/dev/null 2>&1; then
    out="$(CLAUDE_PROJECT_DIR="$repo" bash "$HERE/hooks/session-start.sh" 2>/dev/null || true)"
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
      echo "  ✓ 기억 주입 동작 확인"
    else
      echo "  ℹ 기억 주입 결과가 비어 있습니다 — 위키 log.md 를 확인하세요."
    fi
  fi
}

# ── 인자 처리 ───────────────────────────────────────────────────────────────
[ $# -gt 0 ] || set -- --check .

case "${1:-}" in
--check)
  shift
  [ $# -gt 0 ] || set -- .
  for p in "$@"; do report "$(cd "$p" && pwd)"; done
  ;;
--scan)
  shift
  [ $# -gt 0 ] || { sed -n '2,8p' "$0"; exit 1; }
  found=0
  for root in "$@"; do
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      found=$((found + 1))
      report "$r"
    done < <(scan "$(cd "$root" && pwd)")
  done
  [ "$found" -gt 0 ] || echo "하네스가 설치된 프로젝트를 찾지 못했습니다."
  ;;
-h | --help)
  sed -n '2,8p' "$0"
  ;;
*)
  rc=0
  for p in "$@"; do migrate_one "$p" || rc=1; done
  exit "$rc"
  ;;
esac
