# LLM-WIKI 연동 규칙 (외부 vault 모드)

이 프로젝트의 **정본(설계 결정·ADR·측정 결과·과제·로그)은 외부 위키 vault의 `Projects/__PROJECT_KEY__/`다.** repo의 `docs/`가 아니라 위키에 기록한다.

- **세션 시작**: SessionStart 훅이 위키의 최근 로그·열린 과제를 자동 주입한다. 상세가 필요하면 위키 `Projects/__PROJECT_KEY__/index.md`부터 진입한다(전체를 읽지 않는다).
- **세션 종료 전**: 의미 있는 작업을 했으면 위키 `Projects/__PROJECT_KEY__/log.md` 최신 날짜 섹션에 `- **제목**: 내용` 형식으로 기록하고 위키를 커밋·푸시한다. Stop 훅이 미저장 변경을 감지하면 경고한다.
- **과제 관리**: 새 과제는 위키 `Next-Tasks.md`의 `## 열린 과제` 아래 `### N. 제목` + `무엇 → 왜 → 완료 기준`으로 추가하고, 종료되면 종료 기록 표로 옮긴다. (제목 형식은 훅이 파싱하는 계약이다.)
- **설계 결정**: ADR은 위키 `Decisions/NNNN-*.md`로 남긴다.
- **머신별 경로**: 위키 위치는 `.claude/settings.local.json`(git 미커밋)의 `env.WIKI_ROOT`로 지정한다.
