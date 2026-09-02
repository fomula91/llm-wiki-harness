#!/usr/bin/env bash
# LLM-WIKI 하네스 마이그레이션 (구버전 훅 사본 → 플러그인 훅)
#
#   ./migrate.sh --check [<repo>...]   각 프로젝트의 상태만 보고 (기본: 현재 디렉터리)
#   ./migrate.sh --scan <root>...      하위에서 하네스 프로젝트를 찾아 상태 보고
#   ./migrate.sh <repo>...             실제로 마이그레이션 (settings.json 은 .bak 을 남기고 교체)
#   ./migrate.sh --yes <repo>...       위와 같되, 키·모드를 추론해야 하는 구세대도 확인 없이 진행
#
# 마이그레이션의 위험은 "덜 끝난 채로 멈추는 것"이다. ②까지만 하면 하네스는 꺼져 있고
# 아무 신호도 없다 — 세션은 멀쩡히 돌아가므로 사람은 끝난 줄 안다.
# 그래서 이 스크립트는 절차를 안내하지 않고 끝까지 수행한 뒤 결과 상태를 검증해 보고한다.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

NEW_CONF_REL=".claude/llm-wiki.conf.sh"
OLD_CONF_REL=".claude/hooks/llm-wiki.conf.sh"

# 0.2.0 이전 세대는 conf.sh 가 아예 없고 훅이 settings.json 안에 한 줄 셸로 박혀 있다.
# 파일 존재만으로 판정하면 이 세대가 통째로 "미설치"로 보이므로 훅 문자열도 본다.
# 패턴은 install.sh 의 제거용 정규식보다 좁게 잡는다 — 여기서는 오탐이 남의 프로젝트를
# 건드리는 결과로 이어지므로, 이 하네스에만 쓰이는 두 문자열로만 판단한다.
INLINE_RE='llm-wiki|Next-Tasks\.md'

hook_commands() { # hook_commands <repo> — settings.json 의 모든 훅 커맨드
	local s="$1/.claude/settings.json"
	[ -f "$s" ] || return 0
	if command -v jq >/dev/null 2>&1; then
		jq -r '(.hooks // {}) | to_entries[] | .value[]? | (.hooks // [])[]? | .command // empty' "$s" 2>/dev/null
	else
		cat "$s"
	fi
}

has_inline_hooks() { # has_inline_hooks <repo>
	hook_commands "$1" | grep -Eq "$INLINE_RE"
}

# ── 상태 판별 ───────────────────────────────────────────────────────────────
# none    하네스 미설치
# inline  0.2.0 이전 — 훅이 settings.json 안에 한 줄 셸로 박혀 있음 (conf.sh 없음)
# legacy  0.2.0~0.4.0 — 훅 사본이 배선된 채 동작 중
# off     사본은 남았는데 settings.json 이 더는 부르지 않음 → 훅이 하나도 안 도는 상태
# current 신버전 (플러그인 훅)
#
# 인라인을 가장 먼저 본다: conf.sh 가 이미 생겼는데 인라인 훅도 남아 있으면 두 벌이
# 돌기 때문에, 그 절반만 끝난 상태도 inline 으로 묶어 같은 처리를 받게 한다.
harness_state() { # harness_state <repo>
  local r="$1" s="$1/.claude/settings.json"
  if has_inline_hooks "$r"; then
    echo inline
  elif [ -f "$r/$OLD_CONF_REL" ]; then
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
  inline) echo "0.2.0 이전 — 훅이 settings.json 에 인라인 (마이그레이션 필요, 키·모드 추론)" ;;
  legacy) echo "구버전 — 훅 사본이 동작 중 (마이그레이션 필요)" ;;
  off) echo "⚠️  전환 중 — 훅이 하나도 돌지 않음 (마이그레이션 미완)" ;;
  current) echo "신버전 — 플러그인 훅" ;;
  esac
}

# 인라인 세대에는 PROJECT_KEY 도 WIKI_MODE 도 적혀 있지 않다. 훅 문자열과 위키에서 되찾는다.
# 추론이므로 결과를 반드시 사람에게 보여주고, 확인 없이는 진행하지 않는다.
INF_KEY=""; INF_MODE=""; INF_WIKI=""
infer_target() { # infer_target <repo>
  local repo="$1" cmds key d
  INF_KEY=""; INF_MODE=""; INF_WIKI=""
  cmds="$(hook_commands "$repo")"

  # external 이면 훅에 위키 경로가 박혀 있고 그 안에 Projects/<key> 가 들어 있다.
  key="$(printf '%s' "$cmds" | sed -nE 's|.*Projects/([A-Za-z0-9._-]+).*|\1|p' | head -n1)"
  if [ -n "$key" ]; then
    INF_KEY="$key"; INF_MODE=external
    INF_WIKI="${WIKI_ROOT:-}"
    if [ -z "$INF_WIKI" ] && [ -f "$repo/.claude/settings.local.json" ] && command -v jq >/dev/null 2>&1; then
      INF_WIKI="$(jq -r '.env.WIKI_ROOT // empty' "$repo/.claude/settings.local.json" 2>/dev/null || true)"
    fi
    # 훅에 나열된 후보 경로 중 실제로 이 프로젝트의 위키를 가진 것을 고른다.
    if [ -z "$INF_WIKI" ]; then
      while IFS= read -r d; do
        if [ -d "$d/Projects/$key" ]; then INF_WIKI="$d"; break; fi
      done < <(printf '%s' "$cmds" | tr ' \t";' '\n' | grep '^/' | sort -u)
    fi
    return 0
  fi

  # in-repo 이면 위키가 repo 안에 있고, 템플릿이 '# <key> — Index' 를 남겨 뒀다.
  INF_MODE=in-repo
  INF_KEY="$(sed -nE '1s/^# (.+) — Index$/\1/p' "$repo/llm-wiki/index.md" 2>/dev/null | head -n1)"
  [ -n "$INF_KEY" ] || INF_KEY="$(basename "$repo")"
}

report() { # report <repo>
  local st
  st="$(harness_state "$1")"
  printf '%-8s %s\n         %s\n' "[$st]" "$1" "$(describe "$st")"
  if [ "$st" = inline ]; then
    infer_target "$1"
    printf '         추론: key=%s mode=%s%s\n' "$INF_KEY" "$INF_MODE" \
      "$([ "$INF_MODE" = external ] && printf ' wiki=%s' "${INF_WIKI:-<못 찾음>}")"
  fi
}

# ── 스캔 ────────────────────────────────────────────────────────────────────
scan() { # scan <root>
  local f r
  {
    # 0.2.0 이후: 두 위치 중 어느 conf.sh 든 있으면 하네스와 관련이 있다.
    while IFS= read -r f; do
      r="${f%/.claude/hooks/llm-wiki.conf.sh}"
      r="${r%/.claude/llm-wiki.conf.sh}"
      printf '%s\n' "$r"
    done < <(find "$1" -name llm-wiki.conf.sh -path '*/.claude/*' 2>/dev/null)

    # 0.2.0 이전: conf.sh 라는 파일이 없다. settings.json 안의 훅 문자열로만 찾을 수 있다 —
    # 파일명만 훑으면 이 세대가 통째로 안 보인다(실제로 그렇게 놓쳤다).
    while IFS= read -r f; do
      r="${f%/.claude/settings.json}"
      has_inline_hooks "$r" && printf '%s\n' "$r"
    done < <(find "$1" -path '*/.claude/settings.json' -not -path '*/node_modules/*' 2>/dev/null)
  } | sort -u
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

  if [ "$st" = inline ]; then
    # 0.2.0 이전에는 키도 모드도 어디에도 적혀 있지 않다 — 되찾아서 쓰되, 추론이므로
    # 확인 없이는 진행하지 않는다. 키를 잘못 짚으면 엉뚱한 위키에 스켈레톤이 생긴다.
    infer_target "$repo"
    key="$INF_KEY"; mode="$INF_MODE"; wiki="$INF_WIKI"
    echo "  추론: key=$key mode=$mode${wiki:+ wiki=$wiki}"
    if [ "$ASSUME_YES" != 1 ]; then
      echo "  ✗ 추론값으로 진행하려면 확인이 필요합니다."
      echo "    맞으면: ./migrate.sh --yes $repo"
      echo "    다르면: PROJECT_KEY=<키> WIKI_MODE=<in-repo|external> [WIKI_ROOT=<경로>] ./migrate.sh --yes $repo"
      return 1
    fi
    # 사용자가 명시한 값이 있으면 추론을 덮는다.
    key="${PROJECT_KEY:-$key}"; mode="${WIKI_MODE:-$mode}"
  else
    # 0.2.0~0.4.0 은 구버전 conf.sh 에 키·모드가 적혀 있다 — 다시 묻지 않는다.
    PROJECT_KEY=""; WIKI_MODE=""
    # shellcheck source=/dev/null
    . "$repo/$OLD_CONF_REL"
    key="$PROJECT_KEY"; mode="${WIKI_MODE:-in-repo}"
    wiki=""
    [ -n "$key" ] || { echo "  ✗ 구버전 conf.sh 에서 PROJECT_KEY 를 읽지 못했습니다 — 수동 처리 필요"; return 1; }
  fi

  # ① install.sh 재실행
  if [ "$mode" = external ]; then
    [ -n "$wiki" ] || wiki="${WIKI_ROOT:-}"
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
  if has_inline_hooks "$repo"; then
    echo "  ✗ 검증 실패 — settings.json 에 인라인 llm-wiki 훅이 남아 플러그인 훅과 이중 발동합니다."
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
ASSUME_YES=0
if [ "${1:-}" = "--yes" ]; then ASSUME_YES=1; shift; fi

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
