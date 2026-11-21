# grow-up (전설키우기)

현실의 목표와 습관을 기록하면 신수가 함께 성장하는 Flutter 앱입니다. 할 일을 정리하고, 작은 실천을 쌓고, 그 기록으로 게임을 진행할 수 있습니다. Android와 웹을 같은 코드로 만듭니다.

## 처음 쓰는 사람을 위한 흐름

1. 목표를 만들고 하루에 할 수 있는 행동을 **MINI·MORE·MAX**로 나눕니다. 작은 행동부터 시작해도 됩니다.
2. 오늘의 행동이나 별도의 할 일을 완료합니다. 실천 기록은 달력과 주간 기록에서 다시 볼 수 있습니다.
3. 기록으로 성장한 신수를 확인하고, 훈련이나 숲길 전투를 진행합니다.

로그인 없이도 기기 저장 기록과 게임의 일부 기능을 사용할 수 있습니다. 기록을 다른 기기로 옮기려면 **기록 → 백업**에서 JSON 파일을 내보낸 뒤 새 기기에서 가져오세요. 앱 삭제 또는 기기 초기화 전에 백업하지 않은 로컬 기록은 복구할 수 없습니다. 계정과 서버 게임 기능은 별도의 Supabase 설정이 필요합니다.

## 주요 기능

| 영역 | 할 수 있는 일 |
| --- | --- |
| 목표·실천 | 최대 5개 목표, MINI·MORE·MAX 행동, 선택형 로드맵, 날짜별 기록 수정과 휴식 |
| 할 일 | 일회성·반복 일정, 알림, 중요도·태그·검색, 미루기와 한 회차 쉬기 |
| 돌아보기 | 실천 달력, 주간 흐름, 날짜별 메모, JSON 백업·가져오기 |
| 게임 | 신수 성장·편성, 훈련, 숲길 탐색·전투, 계정 기반 파견·뽑기·보상 |
| 계정 | 이메일 로그인, 할 일·메모 및 목표·실천 기록의 **수동** 동기화 |

서버 게임과 동기화는 빌드 옵션 및 서버 마이그레이션이 적용된 환경에서 사용할 수 있습니다. 기기 게임 진행과 계정 게임 진행은 현재 별도 기록이며, 동기화는 자동으로 실행되지 않습니다. AI 로드맵 요청과 외부 계정 삭제 페이지는 아직 공개 사용 흐름에 연결되지 않았습니다. 현재 구현 상태와 남은 작업은 [TODO.md](TODO.md), 최근 검증 내역은 [작업 기록](docs/PROGRESS.md)을 보세요.

## 로컬에서 실행하기

**준비물:** Flutter SDK 3.47 이상, 해당 플랫폼 도구(Android SDK 또는 Chrome). 이 저장소는 Dart SDK `^3.13.7`을 사용합니다.

```powershell
flutter pub get
flutter run -d chrome
```

Android에서 실행하려면 기기 또는 에뮬레이터를 연결하고 `flutter devices`로 ID를 확인한 다음 실행합니다.

```powershell
flutter devices
flutter run -d <기기-ID>
```

위 명령은 별도 계정 설정 없이 로컬 기능을 확인하는 시작 방법입니다. 계정 기능을 사용하려면 [Supabase 설정 안내](docs/AUTH_SETUP.md)에 따라 프로젝트를 준비하고, 공개 URL과 **publishable key**를 로컬 설정 파일에 입력합니다.

```powershell
Copy-Item flutter_defines.example.env flutter_defines.env
# flutter_defines.env의 두 값을 본인 Supabase 프로젝트의 공개 값으로 수정
flutter run -d chrome --dart-define-from-file=flutter_defines.env
```

`flutter_defines.env`는 Git에서 제외됩니다. 서버 비밀 키, OpenAI API 키, 서명 키는 이 파일이나 Flutter 앱에 넣지 마세요. 게임 서버와 동기화를 켜는 빌드 옵션·DB 적용 순서는 [게임 서버 설정](docs/GAME_SERVER_SETUP.md), [목표 동기화](docs/GOAL_SYNC_DESIGN.md), [할 일·메모 동기화](docs/DAILY_SYNC_DESIGN.md)에 있습니다.

## 확인과 빌드

```powershell
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

웹 결과물은 `build/web/`, Android 디버그 APK는 `build/app/outputs/flutter-apk/`에 생성됩니다. 이 폴더와 배포용 APK·ZIP은 Git에 넣지 않습니다. 정식 배포용 서명·앱 ID·계정 삭제 흐름에는 추가 설정과 검증이 필요합니다. [출시 준비 기록](docs/RELEASE_PREP_2026_11_15.md)을 참고하세요.

## 프로젝트 구성

| 경로 | 내용 |
| --- | --- |
| `lib/` | 화면, 모델, 로컬 저장소, 계정·게임 서비스 |
| `assets/` | 신수와 게임 이미지 |
| `test/` | Flutter 테스트 |
| `supabase/` | DB 마이그레이션, 서버 함수, 관련 테스트 |
| `scripts/` | 빌드와 로컬 서버 검증 스크립트 |
| `docs/` | 제품 설계, 설정 방법, 검증 기록 |

자세한 제품 방향은 [마스터 플랜](docs/MASTER_PLAN.md), 기록 내보내기 방법은 [백업 안내](docs/BACKUP.md), 사용 중 발견한 문제와 제안은 [FEEDBACK.md](FEEDBACK.md)에 정리되어 있습니다.
