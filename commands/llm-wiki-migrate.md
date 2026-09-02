---
description: LLM-WIKI 하네스를 구버전(훅 사본)에서 현행(플러그인 훅)으로 마이그레이션 — 상태 점검 후 수행
argument-hint: [repo-or-scan-root]
---

이 프로젝트(또는 `$1`이 가리키는 곳)의 LLM-WIKI 하네스를 현행 방식으로 넘겨라.

배경: 0.5.0 이전에는 훅 스크립트가 프로젝트 `.claude/hooks/`로 복사됐고 `settings.json`이 그 사본을 호출했다. 지금은 훅이 플러그인 안에서 실행되고, 프로젝트에는 `.claude/llm-wiki.conf.sh` 하나만 남는다. 상세는 하네스 저장소의 `MIGRATION.md`.

**핵심 위험**: 마이그레이션을 절반만 하면 훅이 하나도 돌지 않는 `off` 상태가 되는데, 세션은 멀쩡히 진행되므로 아무도 눈치채지 못한다. **반드시 상태가 `current`임을 확인하고 끝낸다.**

## 0. 하네스 저장소 위치 확인

`/llm-wiki-init`과 같은 순서로 찾는다: 플러그인 루트(이 파일 기준 `../`) → `$LLM_WIKI_HARNESS` → `~/Desktop/LLM-WIKI/llm-wiki-harness` → `~/.claude/llm-wiki-harness`. git repo면 `git pull --ff-only`로 최신화한다(실패해도 진행).

## 1. 상태 점검 (먼저, 반드시)

```bash
bash <harness>/migrate.sh --check <repo>
```

`$1`이 디렉터리이고 그 안에 여러 저장소가 있을 법하면 스캔한다:

```bash
bash <harness>/migrate.sh --scan <root>
```

결과를 사용자에게 그대로 보여준다. 상태별로:

- `none` — 하네스 미설치. 마이그레이션할 것이 없다. 설치를 원하는지 물어보고 원하면 `/llm-wiki-init`을 안내한다.
- `current` — 이미 현행. 할 일 없음을 알리고 끝낸다.
- `legacy` / `off` — 아래로 진행한다. `off`는 **지금 훅이 하나도 돌지 않는 상태**임을 사용자에게 분명히 알린다.
- `inline` — 0.2.0 이전이라 키·모드가 어디에도 없어 **추론**한다. `--check`가 보여준 추론값(`key=` / `mode=` / `wiki=`)을 사용자에게 그대로 보여주고 **맞는지 확인받은 뒤**에만 `--yes`로 실행한다. 틀리면 `PROJECT_KEY=... WIKI_MODE=... [WIKI_ROOT=...] bash <harness>/migrate.sh --yes <repo>`.

## 2. 수행

여러 개면 대상 목록을 사용자에게 보여주고 확인받은 뒤 실행한다.

```bash
bash <harness>/migrate.sh <repo>...         # legacy / off
bash <harness>/migrate.sh --yes <repo>...   # inline (추론값 확인을 받은 뒤에만)
```

이 스크립트가 순서대로 처리한다: ① `install.sh` 재실행(키·모드는 기존 conf.sh에서 읽음) → ② `settings.json` 교체(원본은 `.bak`) → ③ `.claude/hooks/` 삭제 → ④ 결과 검증.

**external 모드에서 위키 경로를 못 찾아 멈추면** 추측해서 넘기지 마라. `.claude/settings.local.json`이 있는지 확인하고, 없으면 사용자에게 위키 vault 경로를 물어 `WIKI_ROOT=<경로> bash <harness>/migrate.sh <repo>`로 다시 실행한다.

## 3. 확인 후 보고

```bash
bash <harness>/migrate.sh --check <repo>
```

`current`가 아니면 **끝났다고 말하지 마라.** 출력을 그대로 보여주고 무엇이 남았는지 설명한다.

사용자에게 알릴 것:

- 상태 변화 (`legacy`/`off` → `current`)
- `settings.json.bak`이 남았다는 것 (문제 없으면 지워도 된다)
- **훅은 다음 세션 시작부터 적용된다** — 지금 세션은 재시작 필요
- 앞으로는 프로젝트별 재실행이 필요 없고 `/plugin update`만 하면 된다는 것

## 주의

- `settings.json` 교체는 `migrate.sh`가 한다. 직접 편집하지 마라 — 무관한 훅·설정 보존과 `permissions.deny` 합집합이 이미 처리돼 있다.
- `.claude/hooks/`를 `settings.json` 교체보다 **먼저 지우지 마라.** 없는 파일을 호출해 매 세션 에러가 난다. (`migrate.sh`는 순서를 지킨다.)
- 위키 내용(`llm-wiki/`, vault의 `Projects/<key>/`)은 이 작업에서 건드리지 않는다.
- 마이그레이션은 프로젝트당 한 번뿐이다. 이미 `current`인 곳에 다시 돌려도 안전하지만 아무 일도 하지 않는다.
