# Claude Battery

macOS 메뉴바에서 **Claude 사용 한도**를 포켓몬 HP바 스타일로 보여주는 개인용 위젯.

- 세션(5시간) / 주간(7일) / 주간 Fable 한도 중 원하는 걸 추적 (기본값: 세션, 위젯 클릭으로 전환)
- 남은 %에 따라 표정이 바뀌는 도트 클로드 캐릭터 (건강 → 지침 → 아픔 → 기절)
- "포켓몬센터까지 남은 시간"(=한도 리셋 시각) ↔ 상태 대사가 부드럽게 번갈아 표시
- IDE extension과 **같은 데이터 소스**(`/api/oauth/usage`)라 값이 정확함
- 외부 의존성 없음 (Swift 표준 라이브러리 + 번들 픽셀 폰트만 사용)

---

## 1. 설치 (새 노트북 포함)

**요구 사항**
- macOS 13+
- Xcode Command Line Tools (`swiftc`) — 없으면 설치 스크립트가 안내함
- 이 맥에서 **Claude Code에 로그인**돼 있어야 함 (CLI가 Keychain에 저장한 OAuth 토큰을 그대로 읽어서 씀)

**설치 방법**: `ClaudeBattery` 폴더를 통째로 새 노트북에 복사한 뒤:

```bash
cd ClaudeBattery
./install.sh
```

`install.sh`가 하는 일 (5단계):
1. `swiftc` 존재 확인 (없으면 Command Line Tools 설치 안내 후 종료 — 설치 후 재실행)
2. 이전에 떠 있던 인스턴스 정지 (재빌드 시 파일 잠김 방지)
3. **이 맥에 맞게** 바이너리 빌드 (Intel/Apple Silicon 자동 대응 — 아키텍처 지정 없이 로컬 컴파일)
4. 로그인 자동 시작 등록 (`~/Library/LaunchAgents/`에 **현재 사용자 경로로** LaunchAgent 생성 — 하드코딩 경로 없음)
5. 실행

첫 실행 때 **"Keychain 접근을 허용하시겠습니까"** 팝업이 뜨면 **"항상 허용"**을 누르세요. (Claude Code 로그인 토큰을 읽기 위함이며, 토큰을 외부로 전송하지 않습니다 — 아래 "동작 원리" 참고.)

설치가 끝나면 메뉴바 오른쪽에 클로드 HP 위젯이 뜹니다.

---

## 2. 일상적으로 쓰는 명령어

| 하고 싶은 것 | 명령어 |
|---|---|
| 코드 수정 후 반영 | `cd ~/ClaudeBattery && ./build.sh && launchctl kickstart -k gui/$(id -u)/com.jay.ClaudeBattery` |
| 지금 당장 새로고침 | 메뉴바 위젯 클릭 → "지금 새로고침" |
| 추적할 한도 바꾸기 (세션/주간/Fable) | 메뉴바 위젯 클릭 → 원하는 항목 클릭 (✓ 표시로 확인, 재시작해도 유지됨) |
| 앱이 도는지 확인 | `pgrep -x ClaudeBattery` |
| 완전히 제거 | `cd ~/ClaudeBattery && ./uninstall.sh` |

> `build.sh`만 실행하면 바이너리만 새로 만들 뿐 **실행 중인 인스턴스는 안 바뀝니다.** 화면에 반영하려면 꼭 `launchctl kickstart -k …`까지 같이 실행하세요.
> 만약 앱이 켜져 있는 상태에서 `build.sh`가 `mkdir: ... Operation not permitted`로 실패하면, 먼저 `pkill -x ClaudeBattery`로 끄고 다시 빌드하세요.

---

## 3. 목 모드 (Mock Mode) — 네트워크 요청 없이 UI만 테스트

디자인/애니메이션/레이아웃을 다듬을 때마다 실제 API를 부르면 짧은 시간에 호출이 몰려 **HTTP 429(요청 과다)**로 막힐 수 있습니다. 목 모드는 **가짜 데이터를 실제와 동일한 렌더링 경로로 흘려보내면서 네트워크 호출을 한 번도 하지 않습니다.**

```bash
cd ~/ClaudeBattery && ./build.sh
CLAUDEBATTERY_MOCK=1 ./build/ClaudeBattery.app/Contents/MacOS/ClaudeBattery
```

- 메뉴바에 **진짜와 동일하게** 위젯이 뜨고 애니메이션(bob·깜빡임)·크로스페이드·클릭으로 한도 전환까지 **전부 실제처럼 동작**합니다.
- "지금 새로고침"을 눌러도 네트워크 대신 같은 가짜 데이터를 다시 그립니다.
- `fetchUsage()`(진짜 API 호출)는 이 모드에서 **절대 호출되지 않습니다** — 429 걱정 없이 얼마든지 재실행해도 됩니다.

**세션 사용률을 바꿔가며 표정/색을 보고 싶을 때**:

```bash
CLAUDEBATTERY_MOCK=1 CLAUDEBATTERY_MOCK_PERCENT=85 ./build/ClaudeBattery.app/Contents/MacOS/ClaudeBattery
```

`85` 대신 0~100 사이 숫자를 넣으면 그 사용률(그 표정·색)로 바로 뜹니다.

| 사용률 (`CLAUDEBATTERY_MOCK_PERCENT`) | 표정 |
|---|---|
| 0~50 | 건강 (초록) |
| 51~80 | 지침 (주황) |
| 81~99 | 아픔 (빨강) |
| 100 | 기절 (회색조, X눈) |

**주의**: 목 모드는 터미널에서 직접 실행하는 임시 테스트용입니다. launchd(자동시작)엔 등록되지 않고, 터미널을 닫거나 `pkill -x ClaudeBattery`하면 꺼집니다. 테스트가 끝나면 실제 앱을 다시 켜세요:

```bash
launchctl load -w ~/Library/LaunchAgents/com.jay.ClaudeBattery.plist
```

**정적 이미지로만 빠르게 훑어보고 싶을 때** (여러 상태를 한 PNG에 쌓아서 보여줌, 창을 띄우지 않고 파일로 저장):

```bash
CLAUDEBATTERY_DUMP=/tmp/preview.png ./build/ClaudeBattery.app/Contents/MacOS/ClaudeBattery
open /tmp/preview.png
```

---

## 4. 제거

```bash
cd ~/ClaudeBattery && ./uninstall.sh
```

로그인 자동 시작 등록을 지우고 앱을 종료합니다. 소스 폴더 자체는 안 지워지니, 완전히 없애려면 폴더도 수동 삭제하세요.

---

## 5. 설정 조절 (`src/main.swift` 상단 근처)

| 상수 | 위치 | 의미 | 참고 |
|---|---|---|---|
| `REFRESH_SECONDS` | 파일 상단 | 사용량 조회 주기(초) | **너무 짧으면 HTTP 429**가 날 수 있음. 240초(4분) 이상 권장 |
| `MAX_BACKOFF` | 파일 상단 | 429 발생 시 최대 백오프(초) | 기본 1800(30분) |
| `TIME_HOLD` / `FLAVOR_HOLD` | AppDelegate 안 | 리셋 시간 ↔ 대사 각각 표시 시간(초) | |
| `CROSSFADE` | AppDelegate 안 | 스왑 전환 시간(초) | |
| `spriteNameGap` / `gap` / `flavorGap` | `buildImage` 안 | 위젯 내부 요소 간격(pt) | |

수정 후엔 "2. 일상적으로 쓰는 명령어"의 재빌드 명령으로 반영.

---

## 6. 동작 원리

- `GET https://api.anthropic.com/api/oauth/usage`
  - 헤더: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`
  - 토큰: macOS Keychain 항목 `Claude Code-credentials` (없으면 `~/.claude/.credentials.json`으로 폴백) — Claude Code CLI가 로그인할 때 이미 저장해 둔 바로 그 토큰을 읽기만 함
- 응답의 `limits[]`에서 세션/주간/Fable 한도의 `percent`, `resets_at`를 읽어 표시
- 기본 추적 대상은 **세션(5시간)**. 위젯 클릭 시 다른 한도로 전환 가능하며 선택은 `UserDefaults`에 저장돼 재시작 후에도 유지됨
- 429가 오면 지수 백오프로 자동 대기 후 복구하며, 대기 중엔 위젯이 회색 게이지 + "졸고 있다" 대사로 바뀜 (데이터 유무와 무관하게 항상 위젯 UI로 표시, 텍스트 폴백 없음)
