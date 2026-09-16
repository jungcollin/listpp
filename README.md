# ListPP

macOS 메뉴바에서 현재 `LISTEN` 중인 TCP 포트를 한눈에 보고, **어떤 프로젝트/도구가 그 포트를 쓰는지** 확인한 뒤 대시보드에서 프로세스를 정리할 수 있는 작은 앱입니다.

코딩 중에 남은 Node/Vite/Next/Python 서버를 찾아 끄는 것이 주 용도입니다. 메뉴바 팝오버는 프로젝트 서버 요약과 **Stop**만 보여주고, **Open**으로 카드형 대시보드를 엽니다.

## 기능

- 메뉴바에 항구 아이콘과 현재 LISTEN 개수 표시
- 5초마다, 그리고 팝오버를 열 때마다 포트 목록 갱신
- 컴팩트 메뉴바 팝오버: 프로젝트 서버를 먼저 보여 주고, 항목별 **Stop**, Refresh / Open / Quit
- **Open**으로 별도 대시보드 창을 앞으로 가져옴
- 대시보드 기본 보기: **Projects** (로컬 프로젝트 서버). All / Other로 시스템 리스너까지 확인
- Newest / Port 정렬, 프로젝트·도구·경로 텍스트 필터
- `lsof -nP -iTCP -sTCP:LISTEN` 기반 포트 목록 + 같은 PID의 `cwd` (`lsof -d cwd`)
- 같은 포트를 여러 프로세스가 쓰는 경우 강조 표시
- 대시보드에서 `프로세스 재시작` (`SIGTERM` 후 동일 명령줄을 **원래 작업 디렉터리**에서 재실행)
- 팝오버와 대시보드 모두에서 `SIGTERM` 전송 (**Stop**이 기본 정리 동작)

## Identity 필드 읽는 법

카드/팝오버의 큰 이름은 더 이상 `node` 나 `/etc/services` 이름이 아닙니다.

| 표시 | 의미 |
| --- | --- |
| **제목** | `~/Project/{work,etc,artifacts}/프로젝트` 폴더명. 없으면 cwd 폴더, 도구명, 마지막에 프로세스명 |
| **도구 배지** | argv에서 인식한 프레임워크/런타임 (`Vite`, `Next.js`, `Uvicorn`, `Python`, …) |
| **경로** | 프로세스 작업 디렉터리 (`lsof` cwd). 홈은 `~`로 줄여 표시. `work · ~/Project/work/…` 처럼 버킷도 함께 보여 줌 |
| **identity 줄** | `Vite · node · PID 19170 · collin` — 도구, 실제 프로세스, PID, 사용자 |
| **Command** | `ps`에서 읽은 전체 명령줄 (접힌 상태로 참고용) |

예시 (같은 `node` 프로세스라도 이렇게 갈라집니다):

- `4296  fluff_cut_salong_astra  [Vite]` → `~/Project/work/fluff_cut_salong_astra`
- `3000  token_poor  [Next.js]` → `~/Project/work/token_poor`
- `ControlCenter`, `rapportd`, Figma, Aside, Codex 같은 시스템/툴은 **Other**

**Projects** 로 치는 조건:

1. cwd 또는 명령줄 경로가 `~/Project/…` 아래이거나
2. Vite / Next.js / Uvicorn 등 로컬 개발 서버로 인식되고, `/System`·`/Applications` 같은 시스템 경로가 아닌 경우

`python`/`node` 처럼 일반적인 이름만 있고 `~/Project` 밖에 있으면 Other로 둡니다. 필터에 `vite`, `token_poor`, `4296` 등을 치면 바로 찾을 수 있습니다.

`/etc/services` 추정값(`hbci`, `commplex-main` 등)은 더 이상 카드 제목으로 쓰지 않습니다. postgres/redis처럼 명령으로 알 수 있는 서비스는 도구 배지로 보여 줍니다.

## 실행

macOS에서:

```bash
swift build
swift run ListPP
```

실행하면 메뉴바에 항구 아이콘이 생기고, 주기적으로(5초) 포트 목록이 갱신됩니다. 아이콘을 누르면 프로젝트 서버 요약 팝오버가 열리고, **Open**으로 대시보드를 띄웁니다.

Linux CI나 비-macOS 환경에서는 AppKit/SwiftUI가 없어 `swift build` / `swift run`이 동작하지 않습니다.

## 앱 번들(.app) 생성

```bash
./scripts/build_app.sh
open dist/ListPP.app
```

`dist/ListPP.app`을 실행하면 일반 macOS 앱처럼 동작합니다.
빌드 시 `scripts/generate_icon.swift`로 커스텀 앱 아이콘을 생성해 `.app`에 포함합니다.
기본으로 ad-hoc 서명을 수행합니다(로컬 테스트용).

Developer ID로 서명하려면:

```bash
LISTPP_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
```

무경고 배포(다른 맥에서 경고 없이 실행)는 `Developer ID 서명 + Apple 공증(notarization)`이 필요합니다.

## 로그인 자동 실행(수동)

시스템 알림(백그라운드 항목 추가)을 피하려면 앱에서 자동 등록하지 않고, macOS 설정에서 직접 추가하세요.

1. `시스템 설정 > 일반 > 로그인 항목` 열기
2. `로그인 항목`의 `+` 버튼 클릭
3. `dist/ListPP.app` 선택

## 참고

- 다른 사용자 소유 프로세스 종료는 권한 문제로 실패할 수 있습니다.
- 시스템 보호 영역 프로세스는 종료가 제한될 수 있습니다.
- 프로젝트 라벨은 `~/Project` 아래 두 단계(`work/fluff_cut_salong_astra`)까지 사용합니다. 다른 트리에 있는 앱은 폴더명/도구명으로만 구분합니다.
- cwd를 못 읽는 프로세스는 명령줄에 있는 `~/Project/…` 절대 경로로 프로젝트를 추정합니다.
- 재시작은 `ps` 명령줄 + 스캔한 cwd 기반이라, 원래의 환경변수/런처가 다르면 동일하게 올라오지 않을 수 있습니다.
- Stop은 확인 없이 `SIGTERM`을 보냅니다. Restart만 확인 알림을 띄웁니다.
