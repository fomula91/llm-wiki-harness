# 마이그레이션 지침서 — 구버전(훅 사본) → 0.5.0(플러그인 훅)

> 요약: `./migrate.sh --scan ~/projects` 로 낡은 프로젝트를 찾고, `./migrate.sh <repo>` 로 넘긴다.
> 플러그인 안에서라면 `/llm-wiki-migrate` 한 줄이면 된다. 아래는 그게 무엇을 하는지와, 손으로 할 때의 순서다.

## 무엇이 바뀌었나

**0.5.0 이전**: `/llm-wiki-init`이 훅 스크립트를 프로젝트의 `.claude/hooks/`로 **복사**하고, `settings.json`이 그 사본을 호출했다. 사본이므로 플러그인을 업데이트해도 갱신되지 않았고, 프로젝트마다 재실행해야 했다.

**0.5.0부터**: 훅은 플러그인 안에서 실행된다(`hooks/hooks.json` → `${CLAUDE_PLUGIN_ROOT}`). 프로젝트에 남는 것은 `.claude/llm-wiki.conf.sh` 하나이고, **그 파일의 존재가 "여기 하네스가 설치됨"의 표식**이다. 이후로는 플러그인만 업데이트하면 모든 프로젝트가 최신 훅을 쓴다.

**이 마이그레이션은 프로젝트마다 한 번만 하면 된다. 그 뒤로는 다시 할 일이 없다.**

## 프로젝트의 네 가지 상태

`./migrate.sh --check <repo>` 가 이 중 하나를 말해준다.

| 상태 | 표식 | 훅이 도는가 |
|---|---|---|
| `none` | conf.sh 가 어느 쪽에도 없음 | — (하네스 미설치) |
| `legacy` | `.claude/hooks/llm-wiki.conf.sh` + settings.json이 사본을 호출 | 구버전 사본이 돎 |
| **`off`** | 사본은 남았는데 settings.json이 더는 호출하지 않음 | **아무것도 안 돎** |
| `current` | `.claude/llm-wiki.conf.sh` 만 | 플러그인 훅 |

### `off` 가 이 문서의 존재 이유다

마이그레이션을 절반만 하면 이 상태가 된다. **훅이 하나도 돌지 않는데 세션은 멀쩡히 진행된다** — 기억 주입도 없고 기록 강제도 없지만 에러 하나 안 난다. 그래서 사람은 끝난 줄 알고, 몇 주 뒤에야 "요즘 위키가 안 쌓이네"로 알아챈다.

`migrate.sh`가 절차를 안내하는 대신 끝까지 수행하고 결과 상태를 검증해 보고하는 이유가 이것이다.

> 왜 사본이 남아 있으면 플러그인 훅이 안 도는가: 두 벌이 함께 돌면 기억이 두 번 주입되고 Stop이 이중으로 막는다. 그래서 플러그인 훅은 `.claude/hooks/llm-wiki.conf.sh`를 발견하면 스스로 물러선다. 조용한 이중 발동보다 잠깐 꺼지는 편이 낫다는 판단이고, 그 대가로 `off` 상태가 생겼다.

## 하는 법

### 여러 프로젝트를 한 번에

```bash
./migrate.sh --scan ~/projects ~/work      # 어디가 낡았는지 먼저 본다
./migrate.sh ~/projects/foo ~/projects/bar # 넘긴다
```

`--scan`은 하위에서 `.claude/llm-wiki.conf.sh`(양쪽 위치)를 가진 디렉터리를 찾아 상태와 함께 보고한다. 아무것도 건드리지 않는다.

### 한 프로젝트

```bash
./migrate.sh /path/to/repo
```

순서대로 이렇게 한다.

1. **`install.sh` 재실행** — 키·모드는 구버전 `conf.sh`에서 그대로 읽는다(다시 묻지 않는다). `.claude/llm-wiki.conf.sh` 생성.
2. **`settings.json` 교체** — install.sh가 만든 `settings.harness.json`(사본 호출을 걷어내고 `permissions.deny`를 더한 완성본)을 적용한다. 원본은 `settings.json.bak`으로 남는다.
3. **`.claude/hooks/` 삭제** — 여기서 플러그인 훅이 인계받는다.
4. **검증** — 상태가 `current`인지, `settings.json`에 사본 호출이 남지 않았는지, 훅이 실제로 기억을 주입하는지 확인해 보고한다.

`external` 모드는 `install.sh`에 위키 경로가 필요하다. `.claude/settings.local.json`의 `env.WIKI_ROOT`에서 읽고, 없으면 **추측하지 않고 멈춘다**(엉뚱한 경로에 위키를 새로 만드는 쪽이 더 나쁘다). 그때는 이렇게 준다.

```bash
WIKI_ROOT=/path/to/vault ./migrate.sh /path/to/repo
```

### 손으로 할 때

자동화를 쓰지 않겠다면 **순서가 중요하다.**

1. `/llm-wiki-init` 재실행
2. `.claude/settings.harness.json` 내용 확인 → `settings.json`으로 교체
3. **그다음** `.claude/hooks/` 삭제

2번 전에 3번을 하면 `settings.json`이 없는 파일을 호출해 매 세션 에러가 난다. 그리고 3번을 빼먹으면 위의 `off` 상태에 갇힌다 — 반드시 `./migrate.sh --check`로 `current`를 확인하고 끝낸다.

## 되돌리기

`migrate.sh`가 지우는 것은 `.claude/hooks/`(하네스가 소유한 사본)뿐이고, `settings.json`은 `.bak`으로 남는다. 되돌리려면:

```bash
cd /path/to/repo
mv .claude/settings.json.bak .claude/settings.json   # 사본 호출이 되살아난다
git checkout .claude/hooks                            # 사본이 커밋돼 있었다면
```

사본을 커밋한 적이 없다면 하네스 저장소의 `llm-wiki-harness--v0.4.0` 태그에서 꺼낼 수 있다. 다만 되돌릴 이유는 거의 없다 — 구버전으로 남으면 앞으로의 모든 업데이트를 프로젝트마다 손으로 받아야 한다.

## 자주 걸리는 것

| 증상 | 원인 | 조치 |
|---|---|---|
| 마이그레이션 후 기억 주입이 없다 | 위키 `log.md`에 최신 날짜 섹션이 없다 | 정상. `log.md`를 확인한다 |
| `off`에서 안 벗어난다 | `.claude/hooks/`가 남아 있다 | `./migrate.sh <repo>` 재실행 |
| external 모드가 멈춘다 | `settings.local.json`이 없다(git 미커밋이라 머신마다 만들어야 함) | `WIKI_ROOT=... ./migrate.sh <repo>` |
| 매 세션 "no such file" 에러 | 순서를 뒤집어 사본을 먼저 지웠다 | `settings.json`을 `.bak`에서 되돌리거나 `./migrate.sh` 재실행 |
| 훅이 아예 안 돈다 | 이 머신에 플러그인이 없다 | `/plugin install llm-wiki-harness@llm-wiki-harness` |

## 관련 문서

- [README](README.md) — 하네스 전체 구조, 두 설치 모드, 컨텍스트 비용 규율
- `tests/cases/migrate.test.sh` — 위 상태 판별과 절차를 CI에서 고정하는 회귀 테스트
