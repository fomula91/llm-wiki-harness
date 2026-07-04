# LLM-WIKI 하네스 보일러플레이트

realtime-wait에서 검증된 "위키 = LLM 장기 기억" 하네스에서 **프로젝트 공통 부분만** 추출한 보일러플레이트.
어떤 코드 저장소든 이걸 적용하면, Claude Code 세션이 위키를 기억으로 쓰고 세션 결과를 위키에 남기는 루프가 생긴다.

## 하네스가 하는 일 (두 축)

**코드 repo 쪽** (`project-side/`)
- `settings.json` — 훅 2개:
  - **SessionStart**: 위키 `Projects/<key>/log.md` 최신 섹션의 제목들 + `Next-Tasks.md` 열린 과제를 추출해 세션 컨텍스트로 주입 (= 세션이 "지난번까지 무슨 일이 있었는지" 알고 시작)
  - **Stop**: 위키에 커밋 안 된 변경/미푸시 커밋이 있으면 exit 2로 경고 → LLM이 세션 작업을 log.md에 기록·커밋·푸시하고 종료하게 강제
- `CLAUDE.base.md` — 공통 행동 지침(Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution) + 위키 연동 규칙 + **검증 단계 TODO 골격**(프로젝트별 작성)
- `settings.local.json.example` — 머신별 `WIKI_ROOT` env + `additionalDirectories`(위키를 읽기 영역에 포함)

**위키 쪽** (`wiki-side/`)
- `project-template/` — `Projects/<key>/` 표준 구조:
  - `index.md`(진입 지도) · `log.md`(시간순 기억) · `Next-Tasks.md`(열린 과제/종료 기록) · `Context.md`(현재 상태 한 장) · `OpenQuestions.md`(미결정 질문) · `Decisions/`(ADR) · `Reference/`(상세 정본) · `Summaries/`(요약층)
- `CLAUDE.md` — 위키 진입 순서·정본 우선순위·쓰기 규칙 (다중 프로젝트 일반형)
- `settings.json` — 위키 안에서 Claude Code 실행 시: SessionStart 자동 `git pull --ff-only`, Stop 자동 commit/push (`$CLAUDE_PROJECT_DIR` 기반이라 머신 무관)

## 훅이 파싱하는 형식 계약 (깨면 기억 주입이 빈다)

| 파일 | 계약 |
|---|---|
| `log.md` | 날짜 섹션 `## YYYY-MM-DD`, 항목 `- **제목**: 내용`. 최신이 위. 훅은 최신 섹션의 **제목**만 추출 |
| `Next-Tasks.md` | 열린 과제는 `## 열린 과제` 아래 `### N. 제목`. 훅은 `###` 제목만 추출 |

## 적용 방법

### 방법 1: Claude Code에서 `/llm-wiki-init` (권장)

머신당 1회, 슬래시 커맨드를 등록한다:

```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/fomula91/llm-wiki-harness/main/commands/llm-wiki-init.md \
  -o ~/.claude/commands/llm-wiki-init.md
```

이후 아무 코드 저장소에서 Claude Code를 열고:

```
/llm-wiki-init [project-key] [wiki-root]
```

인자를 생략하면 디렉터리 이름·`$WIKI_ROOT`·후보 경로에서 추론하고 필요 시 물어본다. 보일러플레이트가 로컬에 없으면 이 repo를 자동 clone한다. install.sh 실행뿐 아니라 **수동 마무리 단계까지 Claude가 직접 수행한다** — 기존 settings/CLAUDE.md 병합, settings.local.json 생성, 검증 단계 표 초안, Context.md 초안, 위키 index 링크·커밋·푸시.

### 방법 2: install.sh 직접 실행

```bash
./install.sh <project-key> <code-repo-path> <wiki-root>
# 예: ./install.sh my-app ~/Desktop/code/my-app ~/Desktop/LLM-WIKI/JACOB-LLM-WIKI
```

기존 파일은 덮어쓰지 않는다 — `settings.json`/`CLAUDE.md`가 이미 있으면 `*.harness.*`로 옆에 생성하고 수동 병합을 안내한다.
설치 후 남은 수동 단계는 스크립트가 마지막에 출력한다 (settings.local.json 복사, 검증 단계 작성, Context.md 채우기 등).

## 요구사항 / 머신별 경로

- `jq` (SessionStart 기억 주입 훅이 사용), git remote가 설정된 위키 repo
- 위키 경로는 머신마다 다르다: 각 머신의 코드 repo `.claude/settings.local.json`(git 미커밋)에서 `env.WIKI_ROOT`로 지정한다. 훅은 `$WIKI_ROOT` → 설치 시 구운 기본 경로 순으로 위키를 찾는다.

## 의도적으로 뺀 것 (프로젝트 고유 하네스)

realtime-wait에는 있지만 공통이 아니라서 뺐다. 새 프로젝트에서 필요해지면 각자 만든다.

- **검증 단계 표 + 실패 원인 분류표** (CLAUDE.md) — 스택마다 다르다. `CLAUDE.base.md`에 TODO 골격만 남김. 이것이 하네스의 절반이므로 꼭 채울 것
- **도메인 서브에이전트** (`.claude/agents/` — worker-dev, frontend-dev, reviewer 등) — 저장소 구조에 종속
- **검증 입구 스크립트** (`pnpm verify`, check:env, corepack 핀) — 스택 종속. 단, "공식 검증 입구 하나 + 우회 금지" 패턴 자체는 CLAUDE.base.md TODO에 명시
- **프로젝트 지식 문서** (Study-Plan, Problem-Solving, 부하 테스트 등) — 내용물이지 하네스가 아님

## 설계 노트

- 코드 repo 쪽 Stop 훅은 자동 커밋하지 **않는다** — LLM이 log.md에 큐레이션된 요약을 쓰고 커밋하게 유도한다(원시 transcript 덤프는 노이즈였다는 realtime-wait 운영 경험 반영). 위키 안에서 직접 작업할 때만 auto-commit 훅이 돈다.
- SessionStart 주입은 제목 수준만 — 상세는 세션이 필요할 때 위키 정본으로 내려가서 읽는다 (컨텍스트 절약).
