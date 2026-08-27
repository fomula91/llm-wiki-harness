#!/usr/bin/env bash
# install.sh — 생성물, 기존 파일 보존, 멱등성, 개인 경로 미노출
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

exists() { # exists <path> <desc>
	if [ -e "$1" ]; then ok "$2"; else bad "$2" "없음: $1"; fi
}
file_has() { # file_has <path> <needle> <desc>
	if grep -qF "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3" "$1 에 '$2' 없음"; fi
}
file_lacks() { # file_lacks <path> <needle> <desc>
	if grep -qF "$2" "$1" 2>/dev/null; then bad "$3" "$1 에 '$2' 가 있으면 안 됨"; else ok "$3"; fi
}
valid_json() { # valid_json <path> <desc>
	if jq -e . "$1" >/dev/null 2>&1; then ok "$2"; else bad "$2" "유효 JSON 아님: $1"; fi
}

# ── repo 내장 모드 ──────────────────────────────────────────────────────────
repo="$(mk_repo)"
bash "$ROOT/install.sh" --in-repo testproj "$repo" >/dev/null
for f in lib.sh session-start.sh stop.sh llm-wiki.conf.sh; do
	exists "$repo/.claude/hooks/$f" "in-repo: .claude/hooks/$f 배포"
done
exists "$repo/.claude/settings.json" "in-repo: settings.json 생성"
exists "$repo/CLAUDE.md" "in-repo: CLAUDE.md 생성"
exists "$repo/llm-wiki/log.md" "in-repo: 위키 스켈레톤 생성"
valid_json "$repo/.claude/settings.json" "in-repo: settings.json 이 유효 JSON"
file_has "$repo/.claude/hooks/llm-wiki.conf.sh" 'WIKI_MODE="in-repo"' "in-repo: conf에 모드가 기록된다"
file_has "$repo/.claude/hooks/llm-wiki.conf.sh" 'PROJECT_KEY="testproj"' "in-repo: conf에 키가 기록된다"

# 배포된 훅은 저장소 원본과 바이트 단위로 같아야 한다 (테스트가 배포본을 증명하려면)
if cmp -s "$ROOT/hooks/stop.sh" "$repo/.claude/hooks/stop.sh"; then
	ok "배포된 훅이 저장소 원본과 동일하다 (치환 없음)"
else
	bad "배포된 훅이 저장소 원본과 동일하다 (치환 없음)" "stop.sh 가 다름"
fi

# 멱등성 — 재설치해도 기존 위키 내용을 덮지 않는다
echo "- **사용자가쓴것**: 유지되어야 함" >>"$repo/llm-wiki/log.md"
bash "$ROOT/install.sh" --in-repo testproj "$repo" >/dev/null
file_has "$repo/llm-wiki/log.md" "사용자가쓴것" "재설치가 기존 위키 내용을 덮지 않는다"

# ── 외부 vault 모드 ─────────────────────────────────────────────────────────
repo2="$(mk_repo)"
vault="$(mktemp -d "$TMPROOT/vault-inst.XXXXXX")"
git -C "$vault" init -q -b main
bash "$ROOT/install.sh" testproj "$repo2" "$vault" >/dev/null
exists "$vault/Projects/testproj/index.md" "external: vault에 위키 스켈레톤 생성"
exists "$vault/CLAUDE.md" "external: vault CLAUDE.md 생성"
exists "$vault/.claude/settings.json" "external: vault 자동 동기화 훅 생성"
exists "$repo2/.claude/settings.local.json.example" "external: settings.local.json.example 생성"
file_has "$repo2/.claude/hooks/llm-wiki.conf.sh" 'WIKI_MODE="external"' "external: conf에 모드가 기록된다"
file_has "$repo2/.claude/settings.local.json.example" "$vault" "external: example에는 실제 위키 경로가 들어간다"

# 버그 #3 — 커밋되는 settings.json 에 머신 절대경로가 들어가면 안 된다
file_lacks "$repo2/.claude/settings.json" "$vault" "external: 커밋되는 settings.json 에 위키 경로가 없다"
file_lacks "$repo2/.claude/settings.json" "$HOME" "external: 커밋되는 settings.json 에 홈 경로가 없다"
file_lacks "$repo2/.claude/hooks/llm-wiki.conf.sh" "$HOME" "external: conf.sh 에도 홈 경로가 없다"

# ── 기존 파일 보존 ──────────────────────────────────────────────────────────
repo3="$(mk_repo)"
mkdir -p "$repo3/.claude"
echo '{"__sentinel__":true}' >"$repo3/.claude/settings.json"
echo "기존 프로젝트 지침" >"$repo3/CLAUDE.md"
bash "$ROOT/install.sh" --in-repo testproj "$repo3" >/dev/null
file_has "$repo3/.claude/settings.json" "__sentinel__" "기존 settings.json 을 덮지 않는다"
file_has "$repo3/CLAUDE.md" "기존 프로젝트 지침" "기존 CLAUDE.md 를 덮지 않는다"
exists "$repo3/.claude/settings.harness.json" "충돌 시 settings.harness.json 으로 빼 둔다"
exists "$repo3/CLAUDE.harness.md" "충돌 시 CLAUDE.harness.md 로 빼 둔다"
valid_json "$repo3/.claude/settings.harness.json" "settings.harness.json 이 유효 JSON"

summary
