---
description: LLM-WIKI 하네스를 현재 프로젝트에 설치 (위키 기억 훅 + 위키 문서 스켈레톤 — repo 내장 / 외부 vault 선택)
argument-hint: [project-key] [wiki-root]
---

현재 코드 저장소에 LLM-WIKI 하네스를 설치하라. 하네스는 두 축이다: ① 코드 repo 훅(SessionStart에 위키 기억 주입, Stop에 기록 누락/미저장 감지) ② 위키 문서 스켈레톤(index·log·Next-Tasks·Context·OpenQuestions·Decisions·Reference·Summaries). 아래 단계를 순서대로 수행한다.

## 0. 보일러플레이트 위치 확인

다음 순서로 찾고, 처음 발견된 것을 쓴다:

1. 이 커맨드가 플러그인으로 설치된 경우 플러그인 루트(이 파일 기준 `../`)에 install.sh가 있다
2. `$LLM_WIKI_HARNESS` 환경변수가 가리키는 디렉터리
3. `~/Desktop/LLM-WIKI/llm-wiki-harness`
4. `~/.claude/llm-wiki-harness`
5. 없으면 `git clone https://github.com/fomula91/llm-wiki-harness ~/.claude/llm-wiki-harness`

git repo면 `git pull --ff-only`로 최신화한다(실패해도 그대로 진행).

## 1. 설치 모드 선택 (사용자에게 질문)

AskUserQuestion으로 위키를 어디에 둘지 묻는다:

- **repo 내장 (in-repo)**: 위키가 코드 repo 안 `llm-wiki/`에 생기고 코드와 함께 커밋된다. 별도 vault·git 동기화·add-dir·머신별 경로 설정이 전부 불필요. 단일 저장소로 완결되길 원하거나 협업자와 위키를 공유하고 싶을 때.
- **외부 vault (add-dir)**: 위키가 코드 밖 중앙 Obsidian vault의 `Projects/<key>/`에 생기고 자체 git으로 여러 머신·여러 프로젝트가 공유한다. `additionalDirectories`(add-dir)로 읽기 영역에 연결하고 머신별 `WIKI_ROOT`를 settings.local.json에 둔다. 이미 중앙 vault를 운영 중이거나 위키를 코드 repo에 노출하고 싶지 않을 때.

## 2. 입력 결정

- **project-key**: `$1`이 있으면 그것. 없으면 현재 디렉터리 이름을 기본값으로 제안하고 사용자에게 확인받는다.
- **wiki-root** (외부 vault 모드만): `$2` → `$WIKI_ROOT` 환경변수 → `~/Desktop/LLM-WIKI/` 아래에서 `Projects/` 디렉터리를 가진 git repo 탐색 → 그래도 못 찾으면 사용자에게 위키 vault 경로를 질문한다.
- 현재 디렉터리가 git 저장소인지 확인한다. 아니면 사용자에게 알리고 중단한다.

## 3. 설치 실행

```bash
# repo 내장 모드
bash <boilerplate>/install.sh --in-repo <project-key> <현재 repo 루트>
# 외부 vault 모드
bash <boilerplate>/install.sh <project-key> <현재 repo 루트> <wiki-root>
```

출력을 확인한다. 기존 파일은 덮어쓰지 않고 건너뛰거나 `*.harness.*`로 옆에 생성된다.

## 4. 병합 처리 (기존 설정이 있던 경우만)

- `.claude/settings.harness.json`이 생겼으면: 기존 `.claude/settings.json`에 hooks(SessionStart/Stop)를 병합하고 harness 파일을 삭제한다. 기존 훅은 유지하고 배열에 추가한다.
- `CLAUDE.harness.md`가 생겼으면: 기존 `CLAUDE.md`에 "LLM-WIKI 연동 규칙" 섹션과 (없다면) "검증 단계" 골격을 추가 병합하고 harness 파일을 삭제한다. 기존 내용은 건드리지 않는다.

## 5. 마무리 (install.sh가 안내한 수동 단계를 직접 수행)

공통:

1. `CLAUDE.md`의 "검증 단계" TODO — 저장소를 훑어(package.json scripts·Makefile·CI 워크플로) **변경 종류 → 실행할 검증** 표 초안을 작성하고 사용자에게 검토받는다. 공식 검증 입구 명령이 없으면 그 사실을 알린다.
2. 위키 `Context.md`를 저장소 README·구조를 근거로 초안 작성한다 (무엇을 만드는가 / 스택·구조 / 지금 단계).
3. 사용자에게 알린다: **훅은 다음 세션 시작부터 적용된다** (지금 세션은 재시작 필요).

repo 내장 모드 추가:

4. `llm-wiki/`와 `.claude/`를 코드와 함께 커밋한다 (커밋 여부는 사용자에게 확인).

외부 vault 모드 추가:

4. `.claude/settings.local.json.example`을 `.claude/settings.local.json`으로 복사한다. 이미 있으면 `env.WIKI_ROOT`와 `permissions.additionalDirectories`(위키 경로)만 병합한다. 이 파일이 git에 커밋되지 않는지 확인한다(.gitignore).
5. 위키 루트 `index.md`에 프로젝트 링크를 추가한다.
6. 위키를 커밋·푸시한다 (커밋 메시지 예: `harness: <key> 프로젝트 초기화`).

## 주의

- 어떤 기존 파일도 덮어쓰지 마라. 충돌은 병합으로 푼다.
- `log.md`·`Next-Tasks.md`의 형식 계약(`## YYYY-MM-DD` / `- **제목**:` / `## 열린 과제` / `### N.`)은 훅이 파싱한다 — 템플릿 형식을 유지하라.
