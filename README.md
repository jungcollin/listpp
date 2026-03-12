# ListPP

macOS 메뉴바에서 현재 `LISTEN` 중인 TCP 포트를 확인하고, 해당 프로세스를 종료할 수 있는 간단한 앱입니다.

## 기능

- 메뉴바에 항구 아이콘으로 상태 표시 (포트 개수는 툴팁에서 확인)
- 메뉴를 열 때마다 자동으로 최신 포트 상태 갱신
- `lsof -nP -iTCP -sTCP:LISTEN` 기반 포트 목록 표시
- 포트 번호와 프로세스를 기반으로 서비스명 추정값 표시
- 목록이 길면 기본 15개만 표시하고 `▼ 펼치기 / ▲ 접기` 토글 제공
- 포트별로 소유 프로세스 정보 확인
- 같은 포트/같은 프로세스명(`node` 등) 구분을 위해 PID/서비스/CMD 끝부분 힌트 표시
- 프로세스 구분을 쉽게 하도록 `CMD` 끝부분을 메뉴에 더 길게 표시
- 메뉴에서 `프로세스 재시작` 지원 (`SIGTERM` 후 동일 명령줄 재실행)
- 메뉴에서 바로 `SIGTERM` 전송(프로세스 종료)

## 실행

```bash
swift build
swift run ListPP
```

실행하면 메뉴바에 항구 아이콘이 생기고, 주기적으로(5초) 포트 목록이 갱신됩니다.

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
