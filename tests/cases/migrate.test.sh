#!/usr/bin/env bash
# migrate.sh — 상태 판별과 자동 마이그레이션
#
# 마이그레이션의 실패 모드는 "덜 끝난 채 멈추는 것"이다. 그 중간 상태(off)는 훅이
# 하나도 돌지 않는데 세션은 멀쩡해서 사람이 알아채지 못한다. 그래서 여기서 검사하는 것은
# "잘 끝나는가"만이 아니라 **덜 끝난 상태를 상태로 부를 수 있는가**다.
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

M="$ROOT/migrate.sh"

state_is() { # state_is <repo> <expected> <desc>
	local got
	got="$(bash "$M" --check "$1" | head -n1 | sed -E 's/^\[([a-z]+)\].*/\1/')"
	if [ "$got" = "$2" ]; then ok "$3"; else bad "$3" "상태 '$got' (기대 '$2')"; fi
}

# ── 1. 상태 판별 4종 ────────────────────────────────────────────────────────
plain="$(mk_repo)"
state_is "$plain" none "하네스 없는 저장소를 none 으로 본다"

cur="$(mk_repo)"
install_conf "$cur" testproj in-repo
state_is "$cur" current "신버전 프로젝트를 current 로 본다"

leg="$(mk_legacy_repo testproj)"
state_is "$leg" legacy "구버전 사본이 배선돼 있으면 legacy"

# settings.json 만 교체하고 사본을 안 지운 상태 = 훅이 하나도 안 도는 구간
half="$(mk_legacy_repo testproj)"
install_conf "$half" testproj in-repo
echo '{"permissions":{"deny":[]}}' >"$half/.claude/settings.json"
state_is "$half" off "사본은 남았는데 호출이 없으면 off (훅이 하나도 안 돎)"

# off 상태가 눈에 띄는 문구로 보고되는가 — 조용히 지나가면 이 상태의 의미가 없다
case "$(bash "$M" --check "$half")" in
*"훅이 하나도 돌지 않음"*) ok "off 상태를 명시적으로 경고한다" ;;
*) bad "off 상태를 명시적으로 경고한다" "$(bash "$M" --check "$half")" ;;
esac

# ── 2. 실제 마이그레이션 ────────────────────────────────────────────────────
mkdir -p "$leg/llm-wiki"
printf '# Log\n\n## %s\n- **기존기록**: 본문\n' "$(date +%F)" >"$leg/llm-wiki/log.md"
out="$(bash "$M" "$leg" 2>&1)"
case "$out" in *"✓ 신버전 상태"*) ok "마이그레이션이 스스로 결과를 검증한다" ;;
*) bad "마이그레이션이 스스로 결과를 검증한다" "$out" ;; esac
state_is "$leg" current "legacy → current 로 넘어간다"

if [ -d "$leg/.claude/hooks" ]; then
	bad "구버전 사본 디렉터리를 지운다" "아직 있음"
else ok "구버전 사본 디렉터리를 지운다"; fi
if [ -f "$leg/.claude/settings.json.bak" ]; then
	ok "교체 전 settings.json 을 .bak 으로 남긴다"
else bad "교체 전 settings.json 을 .bak 으로 남긴다" "없음"; fi

# 남의 설정은 살아남고, 사본 호출은 사라진다
if [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$leg/.claude/settings.json")" = "echo 남의훅" ]; then
	ok "무관한 훅은 마이그레이션 후에도 보존된다"
else bad "무관한 훅은 마이그레이션 후에도 보존된다" "$(jq -c '.hooks' "$leg/.claude/settings.json")"; fi
if grep -q '\.claude/hooks/' "$leg/.claude/settings.json"; then
	bad "settings.json 에서 사본 호출이 사라진다" "아직 있음"
else ok "settings.json 에서 사본 호출이 사라진다"; fi

# install.sh 가 곁들여 만든 파일을 알리는가 — 말 안 하면 프로젝트에 파일이 조용히 는다
lo="$(mk_legacy_repo leftover)"
mkdir -p "$lo/llm-wiki"; printf '# Log\n\n## %s\n- **x**: y\n' "$(date +%F)" >"$lo/llm-wiki/log.md"
echo "기존 프로젝트 지침" >"$lo/CLAUDE.md"
case "$(bash "$M" "$lo" 2>&1)" in
*"함께 생성됨"*CLAUDE.harness.md*) ok "곁들여 생성된 파일을 알린다" ;;
*) bad "곁들여 생성된 파일을 알린다" "$(bash "$M" "$lo" 2>&1 | tail -3)" ;;
esac
if grep -q "기존 프로젝트 지침" "$lo/CLAUDE.md"; then ok "기존 CLAUDE.md 는 그대로 둔다"
else bad "기존 CLAUDE.md 는 그대로 둔다" "덮어써짐"; fi

# 인계가 실제로 일어났는가 — 플러그인 훅이 이 프로젝트에서 주입한다
export CLAUDE_PROJECT_DIR="$leg"
run_hook "$HOOKS/session-start.sh"
assert_ctx_has "기존기록" "마이그레이션 후 플러그인 훅이 기억을 주입한다"

# ── 3. 멱등성과 건너뛰기 ────────────────────────────────────────────────────
out="$(bash "$M" "$leg" 2>&1)"
case "$out" in *"이미 신버전"*) ok "이미 신버전이면 건너뛴다" ;;
*) bad "이미 신버전이면 건너뛴다" "$out" ;; esac
out="$(bash "$M" "$plain" 2>&1)"
case "$out" in *"하네스 미설치"*) ok "하네스 없는 저장소는 건드리지 않는다" ;;
*) bad "하네스 없는 저장소는 건드리지 않는다" "$out" ;; esac

# off 상태도 복구된다 (여기서 못 고치면 이 상태에 빠진 사람이 갈 곳이 없다)
mkdir -p "$half/llm-wiki"
printf '# Log\n\n## %s\n- **반쯤**: 본문\n' "$(date +%F)" >"$half/llm-wiki/log.md"
bash "$M" "$half" >/dev/null 2>&1 || true
state_is "$half" current "off 상태도 마이그레이션으로 복구된다"

# ── 4. 스캔 ─────────────────────────────────────────────────────────────────
# 여러 프로젝트에 흩어진 하네스를 찾아야 "어디가 낡았는지"를 사람이 셀 수 있다.
nest="$(mktemp -d "$TMPROOT/scan.XXXXXX")"
a="$(mk_legacy_repo aaa)"; b="$(mk_repo)"; install_conf "$b" bbb in-repo
mv "$a" "$nest/a"; mv "$b" "$nest/b"
mkdir -p "$nest/c"   # 하네스와 무관한 디렉터리
scanned="$(bash "$M" --scan "$nest")"
case "$scanned" in *"$nest/a"*) ok "스캔이 구버전 프로젝트를 찾는다" ;;
*) bad "스캔이 구버전 프로젝트를 찾는다" "$scanned" ;; esac
case "$scanned" in *"$nest/b"*) ok "스캔이 신버전 프로젝트도 함께 보고한다" ;;
*) bad "스캔이 신버전 프로젝트도 함께 보고한다" "$scanned" ;; esac
case "$scanned" in *"$nest/c"*) bad "무관한 디렉터리는 보고하지 않는다" "$scanned" ;;
*) ok "무관한 디렉터리는 보고하지 않는다" ;; esac

# ── 5. external 모드 ────────────────────────────────────────────────────────
# 위키 경로는 커밋되지 않는 settings.local.json 에만 있다. 마이그레이션은 그걸 찾아 써야 하고,
# 없으면 추측하지 말고 멈춰야 한다 (엉뚱한 경로로 위키를 새로 만들면 더 나쁘다).
ext="$(mk_legacy_repo extproj external)"
vault="$(mk_vault extproj)"
printf '{"env":{"WIKI_ROOT":"%s"}}\n' "$vault" >"$ext/.claude/settings.local.json"
bash "$M" "$ext" >/dev/null 2>&1 || true
state_is "$ext" current "external 모드는 settings.local.json 의 WIKI_ROOT 를 쓴다"

ext2="$(mk_legacy_repo extproj2 external)"
if bash "$M" "$ext2" >/dev/null 2>&1; then
	bad "위키 경로를 못 찾으면 실패로 끝난다" "성공으로 끝남"
else ok "위키 경로를 못 찾으면 실패로 끝난다"; fi
case "$(bash "$M" "$ext2" 2>&1 || true)" in *WIKI_ROOT*) ok "무엇을 주면 되는지 알려준다" ;;
*) bad "무엇을 주면 되는지 알려준다" "$(bash "$M" "$ext2" 2>&1 || true)" ;; esac

# ── 6. 0.2.0 이전(인라인) 세대 ──────────────────────────────────────────────
# 이 세대는 conf.sh 가 없어 파일명으로는 찾을 수 없다. 실제로 사용자 머신의 프로젝트
# 5개가 전부 이 세대였고 --scan 이 "찾지 못했습니다"라고 답했다 — 그 누락을 여기서 고정한다.
inl="$(mk_inline_repo demo-inline)"
state_is "$inl" inline "인라인 훅만 있어도 하네스로 인식한다 (conf.sh 없음)"

case "$(bash "$M" --check "$inl")" in
*"key=demo-inline"*"mode=in-repo"*) ok "인라인 세대의 키·모드를 추론해 보여준다" ;;
*) bad "인라인 세대의 키·모드를 추론해 보여준다" "$(bash "$M" --check "$inl")" ;;
esac

# 스캔이 찾아야 한다 (여기가 이번 결함의 핵심)
nest2="$(mktemp -d "$TMPROOT/scan2.XXXXXX")"
i2="$(mk_inline_repo scanned-inline)"; mv "$i2" "$nest2/i"
case "$(bash "$M" --scan "$nest2")" in
*"$nest2/i"*) ok "스캔이 인라인 세대를 찾는다" ;;
*) bad "스캔이 인라인 세대를 찾는다" "$(bash "$M" --scan "$nest2")" ;;
esac

# 추론값으로는 확인 없이 진행하지 않는다 — 키를 잘못 짚으면 엉뚱한 위키가 생긴다
if bash "$M" "$inl" >/dev/null 2>&1; then
	bad "확인 없이는 인라인 마이그레이션을 진행하지 않는다" "성공으로 끝남"
else ok "확인 없이는 인라인 마이그레이션을 진행하지 않는다"; fi
if [ -f "$inl/.claude/llm-wiki.conf.sh" ]; then
	bad "거부했으면 아무것도 바꾸지 않는다" "conf.sh 가 생김"
else ok "거부했으면 아무것도 바꾸지 않는다"; fi

# --yes 면 진행하고, 인라인 훅이 사라진다
bash "$M" --yes "$inl" >/dev/null 2>&1 || true
state_is "$inl" current "--yes 면 인라인 → current 로 넘어간다"
if grep -q 'Next-Tasks\.md' "$inl/.claude/settings.json" 2>/dev/null; then
	bad "인라인 훅이 settings.json 에서 제거된다" "아직 있음"
else ok "인라인 훅이 settings.json 에서 제거된다"; fi
if [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$inl/.claude/settings.json")" = "echo 남의훅" ]; then
	ok "인라인 마이그레이션도 무관한 훅을 보존한다"
else bad "인라인 마이그레이션도 무관한 훅을 보존한다" "$(jq -c '.hooks' "$inl/.claude/settings.json")"; fi

# external 인라인: 위키 경로가 훅 안에 하드코딩돼 있던 시절 → 거기서 되찾아야 한다
vault2="$(mk_vault extinline)"
exi="$(mk_inline_repo extinline external "$vault2")"
case "$(bash "$M" --check "$exi")" in
*"mode=external"*"wiki=$vault2"*) ok "external 인라인은 훅에 박힌 경로에서 vault 를 되찾는다" ;;
*) bad "external 인라인은 훅에 박힌 경로에서 vault 를 되찾는다" "$(bash "$M" --check "$exi")" ;;
esac
bash "$M" --yes "$exi" >/dev/null 2>&1 || true
state_is "$exi" current "external 인라인도 current 로 넘어간다"

# 구버전 훅은 위키 경로를 자기 안에 하드코딩해 뒀지만 현행 훅은 $WIKI_ROOT 만 본다.
# 마이그레이션이 그 값을 심어 두지 않으면 하네스가 조용히 죽는다 (실사용에서 실제로 겪음).
loc="$exi/.claude/settings.local.json"
if [ "$(jq -r '.env.WIKI_ROOT // empty' "$loc" 2>/dev/null)" = "$vault2" ]; then
	ok "external 마이그레이션이 settings.local.json 에 WIKI_ROOT 를 심는다"
else bad "external 마이그레이션이 settings.local.json 에 WIKI_ROOT 를 심는다" "$(cat "$loc" 2>/dev/null)"; fi

# 실제 세션 조건(그 WIKI_ROOT)에서 주입이 되는가 — 심어 놓고 안 도는 것이 가장 나쁘다
WIKI_ROOT="$(jq -r '.env.WIKI_ROOT' "$loc")"; export WIKI_ROOT
export CLAUDE_PROJECT_DIR="$exi"
run_hook "$HOOKS/session-start.sh"
assert_ctx_has "하네스 설치" "심어 둔 WIKI_ROOT 로 실제 주입이 된다"
# 이후 추론 테스트가 이 값을 주워 엉뚱한 vault 를 고르지 않도록 되돌린다
unset WIKI_ROOT

# 기존 settings.local.json 의 다른 설정은 보존한다
exi2="$(mk_inline_repo keepext external "$(mk_vault keepext)")"
mkdir -p "$exi2/.claude"
echo '{"env":{"OTHER":"keep"},"permissions":{"additionalDirectories":["/somewhere"]}}' >"$exi2/.claude/settings.local.json"
bash "$M" --yes "$exi2" >/dev/null 2>&1 || true
loc2="$exi2/.claude/settings.local.json"
if [ "$(jq -r '.env.OTHER // empty' "$loc2" 2>/dev/null)" = keep ] &&
	[ -n "$(jq -r '.env.WIKI_ROOT // empty' "$loc2" 2>/dev/null)" ]; then
	ok "settings.local.json 의 기존 env·경로 설정을 보존하며 WIKI_ROOT 만 더한다"
else bad "settings.local.json 의 기존 env·경로 설정을 보존하며 WIKI_ROOT 만 더한다" "$(cat "$loc2" 2>/dev/null)"; fi
if [ "$(jq -r '[.permissions.additionalDirectories[] | select(. == "/somewhere")] | length' "$loc2")" = 1 ]; then
	ok "기존 additionalDirectories 항목이 남는다"
else bad "기존 additionalDirectories 항목이 남는다" "$(jq -c '.permissions' "$loc2")"; fi

# conf.sh 는 생겼는데 인라인 훅이 남은 절반 상태 = 이중 발동 → inline 으로 잡아 다시 처리한다
dup="$(mk_inline_repo dup-inline)"
install_conf "$dup" dup-inline in-repo
state_is "$dup" inline "conf.sh 가 있어도 인라인 훅이 남았으면 current 로 보지 않는다"

summary
