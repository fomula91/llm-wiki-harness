# CLAUDE.md — 위키 참조 규칙

이 위키는 **프로젝트 지식 베이스**다. 프로젝트별 정본은 `Projects/<프로젝트>/` 아래에 있다.

## 진입 순서
이 위키를 참조할 때 전체를 읽지 마라. 다음 순서로 진입한다.

1. 루트 `index.md` → `Projects/<프로젝트>/index.md` 로 지도를 잡는다.
2. 최근 변화가 필요하면 `log.md`(루트 또는 프로젝트) 상단만 읽는다.
3. 구현 컨텍스트는 `Projects/<프로젝트>/Context.md`를 우선 읽는다.
4. 상세 정본은 `Projects/<프로젝트>/Reference/` — 필요할 때만 내려가고, 기본 컨텍스트로 통째로 읽지 않는다.

## 정본 우선순위 (충돌 시 위가 이긴다)
1. `index.md` / `Projects/<프로젝트>/index.md` — 진입 지도
2. `log.md` — 가장 최근 변경 흐름 (최신성 기준)
3. `Projects/<프로젝트>/Decisions/` (ADR) · `Summaries/` · `Reference/`
4. `Concepts/` — 프로젝트 간 재사용 개념

## 쓰기 규칙
- 출처가 있는 정식 문서(`Reference/`·`Decisions/` 등)는 frontmatter에 `source:`(원본 repo/URL/경로 + 시점)를 적어 추적성을 남긴다.
- `log.md`는 최신 날짜가 위. 항목은 `- **제목**: 내용` 형식 — 코드 repo의 SessionStart 훅이 이 형식을 파싱한다.
- `Next-Tasks.md`의 열린 과제는 `## 열린 과제` 아래 `### N. 제목` — 역시 훅 파싱 계약이다.
- 자동 commit/push 훅(`.claude/settings.json`의 SessionStart/Stop)은 이 위키 안에서 Claude Code를 실행할 때만 동작한다. 코드 repo 세션에서는 LLM이 log.md 기록 후 직접 커밋·푸시한다.
