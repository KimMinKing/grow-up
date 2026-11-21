# Android 출시 준비 현황 — 2026-11-15

## 이번에 준비한 것

- `android/app/build.gradle.kts`는 배포용 application ID와 업로드 키를 환경 변수로 받는다. `GROWUP_REQUIRE_PRODUCTION_SIGNING=true`이면 개발용 ID나 누락된 서명 값으로 빌드할 수 없다. 기존 시험판은 현재 ID와 개발 서명을 계속 사용한다.
- Android 시작 Activity의 실제 클래스명은 유지하고 로그인 복귀 URI의 scheme은 배포 ID에 맞춘다. Flutter의 `LOGIN_REDIRECT_SCHEME`도 같은 ID로 빌드해야 한다. Supabase Redirect URLs에 `<permanent.application.id>://login-callback/`을 추가해야 한다.
- `내 데이터` 화면은 `PRIVACY_POLICY_URL`이 HTTPS로 설정되면 개인정보처리방침 링크를 표시한다. `ACCOUNT_DELETION_ENABLED=true`와 `ACCOUNT_DELETION_URL`이 함께 설정되면 외부 계정 삭제 요청 링크를 표시한다.
- `scripts/release_preflight.ps1`은 배포 전 ID, 키 파일, 서명 환경 변수, 두 공개 URL의 형식을 검사하고 빠진 항목을 한 번에 표시한다. 비밀번호 값은 출력하지 않는다.
- `scripts/build_production_bundle.ps1`은 사전 검사 후 같은 ID를 Android 패키지명과 로그인 복귀 scheme에 동시에 적용하며, 검증된 게임 기능 플래그로 AAB를 빌드한다. 계정 삭제 경로를 검증했다는 명시적 스위치가 있어야 실행된다.

## 남은 실제 배포 조건

| 항목 | 현재 | 완료 조건 |
|---|---|---|
| 영구 패키지명 | `com.example.growup` | 운영자가 고유 ID를 결정하고 Play Console의 신규 앱과 일치시킨다. 기존 시험판의 앱 내 로컬 기록은 ID 변경만으로 이전되지 않으므로 JSON 백업·가져오기를 안내한다. |
| 업로드 키 | 개발 키 사용 | 업로드 키를 안전한 장소에 보관하고 지문을 기록한다. 값은 저장소에 넣지 않는다. |
| 개인정보처리방침 | 앱에는 시험판 데이터 안내만 있음 | 운영 주체·연락처, 수집/공유 항목, 보관·삭제 기간, 위탁 서비스를 실제 설정과 대조해 작성하고 공개 HTTPS 페이지로 게시한다. |
| 계정 삭제 | `delete-account` 운영 배포·무인증 차단·로컬 DB 연쇄 삭제 확인. 외부 웹 페이지를 웹 빌드에 포함. 앱 기능은 꺼짐 | 별도 시험 계정의 잘못된 확인값·실제 삭제·재로그인 불가를 검증하고 외부 페이지를 공개 HTTPS로 게시한 뒤 기능 플래그를 켠다. |
| 로그인 제공자 | 이메일 사용, Google·Kakao 설정 대기 | 운영 ID/서명에 맞춘 공급자 설정 및 실제 로그인·복구 확인. |
| 앱 번들 | 기존 arm64 시험용 APK와 공개 설정을 포함한 웹 빌드 생성 | 위 항목을 채운 뒤 AAB를 만들고 Play 내부 테스트에서 설치·업데이트·로그인·탈퇴 동선을 확인한다. |

## 배포 빌드 입력 예시

공개 문서의 시작점은 [개인정보처리방침 작성 초안](PRIVACY_POLICY_DRAFT.md)이다. 실제 값이 비어 있어 게시용 문서로 사용하면 안 된다.

PowerShell에서 운영자가 값과 키 경로를 채운다. 키 비밀번호는 명령줄 인수나 저장소 파일에 넣지 않는다.

```powershell
$env:ORG_GRADLE_PROJECT_GROWUP_APPLICATION_ID = '<permanent.application.id>'
$env:ORG_GRADLE_PROJECT_GROWUP_REQUIRE_PRODUCTION_SIGNING = 'true'
$env:GROWUP_RELEASE_STORE_FILE = '<absolute-path-to-upload-keystore>'
$env:GROWUP_RELEASE_STORE_PASSWORD = '<from-secure-secret-store>'
$env:GROWUP_RELEASE_KEY_ALIAS = '<upload-key-alias>'
$env:GROWUP_RELEASE_KEY_PASSWORD = '<from-secure-secret-store>'
$env:GROWUP_PRIVACY_POLICY_URL = 'https://<public-policy-page>'
$env:GROWUP_ACCOUNT_DELETION_URL = 'https://<public-deletion-page>'
./scripts/release_preflight.ps1
./scripts/build_production_bundle.ps1 -AccountDeletionVerified `
  -FlutterCommand 'C:\Users\fback\develop\flutter\bin\flutter.bat'
```

앱 번들 생성만으로 공개 배포 조건이 충족되지는 않는다. `ACCOUNT_DELETION_ENABLED`는 함수 검증이 끝난 뒤에만 사용한다. 실제 빌드에서는 게임 기능 플래그도 시험한 값으로 명시한다.

## 확인한 공식 기준

- [Android application ID](https://developer.android.com/build/configure-app-module): 공개 후 ID 변경은 별도 앱으로 취급된다.
- [Android 앱 서명 및 Play App Signing](https://developer.android.com/studio/publish/app-signing): 신규 Play 앱은 업로드 키로 서명한 번들을 사용한다.
- [Google Play 사용자 데이터 정책](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en): 개인정보처리방침은 앱 안과 Play Console에서 접근 가능해야 하고, 계정 생성 앱에는 앱 안과 외부 웹의 삭제 요청 경로가 필요하다.
