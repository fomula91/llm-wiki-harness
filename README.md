# LLM-WIKI 하네스 (Claude Code 플러그인)

"위키 = LLM 장기 기억" 하네스.
어떤 코드 저장소든 `/llm-wiki-init` 한 번으로, Claude Code 세션이 위키를 기억으로 쓰고 세션 결과를 위키에 남기는 루프가 생긴다: 세션 시작에 최근 로그·열린 과제가 자동 주입되고, 세션이 끝나기 전 작업 기록을 남기도록 훅이 강제한다.

## 설치 (머신당 1회)

이 repo는 Claude Code **플러그인이자 자기 자신의 마켓플레이스**다. Claude Code 안에서:

```
/plugin marketplace add fomula91/llm-wiki-harness
/plugin install llm-wiki-harness@llm-wiki-harness
```

또는 터미널에서:

```bash
claude plugin marketplace add fomula91/llm-wiki-harness
claude plugin install llm-wiki-harness@llm-wiki-harness --scope user
```

설치하면 `/llm-wiki-init` 커맨드가 생긴다 (충돌 시 네임스페이스 형태 `/llm-wiki-harness:llm-wiki-init`).

> 플러그인 없이 쓰려면: `commands/llm-wiki-init.md`를 `~/.claude/commands/`에 복사하거나, repo를 clone해 `install.sh`를 직접 실행해도 된다.

## 사용

하네스를 설치할 코드 저장소에서 Claude Code를 열고:

```
/llm-wiki-init [project-key] [wiki-root]
```

인자를 생략하면 디렉터리 이름·`$WIKI_ROOT`·후보 경로에서 추론하고 필요 시 물어본다. install.sh 실행뿐 아니라 **수동 마무리 단계까지 Claude가 직접 수행한다** — 기존 settings/CLAUDE.md 병합, 검증 단계 표 초안, Context.md 초안, (외부 vault 모드) settings.local.json 생성·위키 index 링크·커밋·푸시.

## 두 가지 설치 모드

`/llm-wiki-init`이 처음에 물어본다. 위키를 어디에 둘 것인가:

| | **repo 내장 (in-repo)** | **외부 vault (add-dir)** |
|---|---|---|
| 위키 위치 | 코드 repo 안 `llm-wiki/` | 중앙 Obsidian vault의 `Projects/<key>/` |
| 버전 관리 | 코드와 함께 커밋 (별도 동기화 없음) | 위키 자체 git (여러 머신·여러 프로젝트 공유) |
| 추가 설정 | 없음 | `additionalDirectories`(add-dir) + 머신별 `WIKI_ROOT` (settings.local.json) |
| Stop 훅 | 코드 변경이 있는데 `log.md`에 오늘 기록이 없으면 경고 | 기록 누락(코드 변경 + 오늘 기록 없음) 또는 위키 미커밋/미푸시 변경이 있으면 경고 |
| 어울리는 경우 | 단일 repo로 완결, 협업자와 위키 공유 | 이미 중앙 vault 운영, 위키를 코드 repo에 노출하기 싫을 때 |
| install.sh | `./install.sh --in-repo <key> <repo>` | `./install.sh <key> <repo> <wiki-root>` |

## 하네스가 하는 일 (두 축)

**코드 repo 쪽** (`hooks/` + `project-side/`)
- `hooks/{lib,session-start,stop}.sh` — 훅 본체. install.sh가 대상 repo의 `.claude/hooks/`로 **치환 없이 그대로** 복사하고, `settings.json`은 그 경로만 호출한다. 프로젝트별 설정(키·모드)은 함께 생성되는 `llm-wiki.conf.sh` 한 파일에만 들어간다 — 모드 분기는 훅 안에 있고 설정 파일이 갈리지 않는다.
- 훅 2개:
  - **SessionStart**: 위키 `log.md` 최신 섹션의 제목들 + `Next-Tasks.md` 열린 과제를 추출해 세션 컨텍스트로 주입 (= 세션이 "지난번까지 무슨 일이 있었는지" 알고 시작)
  - **Stop**: 세션 기록 누락을 exit 2로 경고 → LLM이 세션 작업을 log.md에 기록하고 종료하게 강제 (모드별 감지 방식은 위 표)
- `CLAUDE.guidelines.md` + `wiki-rules.{external,in-repo}.md` + `CLAUDE.verify-todo.md` — install.sh가 모드에 맞게 조립해 `CLAUDE.md` 생성: 공통 행동 지침(Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution) + 위키 연동 규칙 + **검증 단계 TODO 골격**(프로젝트별 작성)
- `settings.local.json.example` — (외부 vault 모드) 머신별 `WIKI_ROOT` env + `additionalDirectories`

**위키 쪽** (`wiki-side/`)
- `project-template/` — 위키 표준 구조 (양쪽 모드 공용 스켈레톤):
  - `index.md`(진입 지도) · `log.md`(시간순 기억) · `Next-Tasks.md`(열린 과제/종료 기록) · `Context.md`(현재 상태 한 장) · `OpenQuestions.md`(미결정 질문) · `Decisions/`(ADR) · `Reference/`(상세 정본) · `Summaries/`(요약층)
- `CLAUDE.md` — 위키 진입 순서·정본 우선순위·쓰기 규칙 (외부 vault 모드만 설치)
- `settings.json` — 위키 vault 안에서 Claude Code 실행 시: SessionStart 자동 `git pull --ff-only`, Stop 자동 commit/push (`$CLAUDE_PROJECT_DIR` 기반이라 머신 무관, 외부 vault 모드만)

## 훅이 파싱하는 형식 계약 (깨면 기억 주입이 빈다)

| 파일 | 계약 |
|---|---|
| `log.md` | 날짜 섹션 `## YYYY-MM-DD`, 항목 `- **제목**: 내용`. 최신이 위. 훅은 최신 섹션의 **제목**만 추출 |
| `Next-Tasks.md` | 열린 과제는 `## 열린 과제` 아래 `### N. 제목`. 훅은 `###` 제목만 추출 |

이 계약은 산문으로만 있지 않다 — `tests/cases/contract.test.sh`가 **실제 템플릿을 실제 파서에 물려** CI에서 강제한다. 템플릿이 드리프트하면 red가 난다.

## 테스트

```bash
bash tests/run.sh          # 훅·설치·형식 계약 회귀 테스트 (bash + git + jq)
```

임시 디렉터리에 가짜 코드 repo와 가짜 위키 vault를 만들고, **실제 배포될 훅 파일과 실제 템플릿**을 그대로 물려 돌린다. 발동해야 할 때 발동하는지뿐 아니라, **발동하면 안 될 때 조용한지**(무관한 vault 변경, 위키 미설치, `jq` 부재)를 같은 비중으로 검사한다 — 오탐이 쌓이면 사용자가 훅을 꺼버리기 때문이다. GitHub Actions에서 Linux·macOS 양쪽으로 돈다.

## 요구사항

- `jq` (SessionStart 기억 주입 훅이 사용 — 없으면 훅이 조용히 건너뛴다)
- 외부 vault 모드: git remote가 설정된 위키 repo. 위키 경로는 머신마다 다르므로 각 머신의 `.claude/settings.local.json`(git 미커밋)에서 `env.WIKI_ROOT`로 지정 — 훅은 `$WIKI_ROOT` → 설치 시 구운 기본 경로 순으로 위키를 찾는다.

## 하네스에 포함하지 않은 것 (프로젝트별로 만들 것)

스택·저장소 구조에 종속되는 것들은 의도적으로 뺐다. 설치 후 프로젝트마다 직접 채운다.

- **검증 단계 표 + 실패 원인 분류표** (CLAUDE.md) — 스택마다 다르다. TODO 골격만 남김. 이것이 하네스의 절반이므로 꼭 채울 것
- **도메인 서브에이전트** (`.claude/agents/` — 백엔드/프론트/리뷰어 등) — 저장소 구조에 종속
- **검증 입구 스크립트** (예: `pnpm verify`, `make check`) — 스택 종속. 단, "공식 검증 입구 하나 + 우회 금지" 패턴 자체는 TODO에 명시
- **프로젝트 지식 문서** (학습 계획, 문제 해결 사례, 측정 리포트 등) — 위키의 내용물이지 하네스가 아님

## 설계 노트

- 코드 repo 쪽 Stop 훅은 자동 커밋하지 **않는다** — LLM이 log.md에 큐레이션된 요약을 쓰고 커밋하게 유도한다(세션 transcript를 원시 덤프하는 방식은 노이즈만 쌓여서 폐기한 운영 경험 반영). 외부 vault 안에서 직접 작업할 때만 auto-commit 훅이 돈다.
- SessionStart 주입은 제목 수준만 — 상세는 세션이 필요할 때 위키 정본으로 내려가서 읽는다 (컨텍스트 절약).
- repo 내장 모드의 Stop 훅은 "코드가 바뀌었는데 오늘 로그가 없다"만 본다 — 위키가 코드와 같은 커밋에 실리므로 push 감시가 필요 없다.
- 훅은 JSON 안에 인라인된 한 줄 셸이 아니라 **별도 `.sh` 파일**로 배포한다. 읽고·디버깅하고·테스트할 수 있어야 하네스의 강제력을 증명할 수 있고, 테스트가 검증하는 파일과 배포본이 바이트 단위로 같아야 그 증명이 유효하다.
- 외부 vault 모드의 Stop 훅은 vault 전체가 아니라 **이 프로젝트의 `Projects/<key>/`만** 미저장 검사한다. vault는 여러 프로젝트가 공유하고 `.obsidian/`은 상시 변하므로, 전체를 보면 무관한 변경으로 매 세션 오탐이 난다.
- 위키 경로의 단일 출처는 `.claude/settings.local.json`의 `env.WIKI_ROOT` 하나다 — 커밋되는 파일에는 머신 절대경로가 들어가지 않는다. 못 찾으면 세션 시작 시 원인을 알려준다.
