# ListPP

macOS 메뉴바에서 현재 `LISTEN` 중인 TCP 포트를 한눈에 보고, 대시보드에서 프로세스를 관리할 수 있는 작은 앱입니다.

메뉴바 팝오버는 요약과 빠른 동작만 보여주고, **Open**으로 카드형 대시보드 창을 엽니다.

## 기능

- 메뉴바에 항구 아이콘과 현재 LISTEN 개수 표시
- 5초마다, 그리고 팝오버를 열 때마다 포트 목록 갱신
- 컴팩트 메뉴바 팝오버: 요약, 상위 항목, Refresh / Open / Quit, 항목별 Stop / Restart
- **Open**으로 별도 대시보드 창을 앞으로 가져옴 (헤더 + 마지막 갱신 시각 + Refresh)
- 대시보드에서 포트/프로세스/PID/사용자/서비스 힌트/엔드포인트/명령줄을 카드로 표시
- 대시보드에서 Newest / Port 정렬, 텍스트 필터
- `lsof -nP -iTCP -sTCP:LISTEN` 기반 포트 목록
- 포트 번호와 프로세스명을 기반으로 서비스명 추정
- 같은 포트를 여러 프로세스가 쓰는 경우 강조 표시
- 팝오버와 대시보드 모두에서 `프로세스 재시작` (`SIGTERM` 후 동일 명령줄 재실행)
- 팝오버와 대시보드 모두에서 `SIGTERM` 전송 (Stop)

## 실행

macOS에서:

```bash
swift build
swift run ListPP
```

실행하면 메뉴바에 항구 아이콘이 생기고, 주기적으로(5초) 포트 목록이 갱신됩니다. 아이콘을 누르면 요약 팝오버가 열리고, **Open**으로 대시보드를 띄웁니다.

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
- 서비스명은 `/etc/services`와 프로세스명 기반의 추정값이라 실제 앱/비즈니스 서비스명과 다를 수 있습니다.
- 재시작은 `ps`에서 읽은 명령줄 기반이라, 원래의 환경변수/작업 경로/런처가 다르면 동일하게 올라오지 않을 수 있습니다.
- Stop은 확인 없이 `SIGTERM`을 보냅니다. Restart만 확인 알림을 띄웁니다.
