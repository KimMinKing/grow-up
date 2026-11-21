# Supabase 로그인 연결

> 현재 상태 (2026-11-07): 아래 SMTP 오류 설명은 이전 장애 기록입니다. 이메일 인증번호 발송과 플립4 로그인을 확인했습니다. 앱 첫 화면은 이메일 비밀번호 로그인·회원가입·인증번호 로그인으로 바뀌었습니다. Google·카카오 연결 절차와 남은 설정은 [첫 실행 로그인과 제공자 설정](LOGIN_PROVIDERS.md)을 보세요.

원하는 로그인 방식은 **이메일로 받은 인증번호를 앱에 입력**하는 것입니다. 메일은 컴퓨터에서 열고 인증번호만 휴대폰 앱에 입력해도 됩니다. 앱의 번호 입력과 Supabase `verifyOTP` 연결은 준비됐습니다. Supabase 프로젝트에는 SMTP와 두 인증번호 템플릿이 저장됐으나 현재 Gmail SMTP 인증 오류 535로 발송이 실패합니다. 아래의 Gmail 앱 비밀번호를 바로잡은 뒤 실제 발송을 확인해야 합니다. 로그인만으로 목표와 실천 기록이 전송되지는 않습니다.

## 인증번호 메일로 전환

1. 메일 발송 서비스에서 SMTP 서버 주소, 포트, 사용자 이름, 비밀번호, 발신 주소를 발급받습니다. Supabase는 Resend·Brevo·Postmark 등 SMTP 서비스를 지원합니다. SMTP 비밀번호는 앱 코드나 채팅에 넣지 말고 Supabase 관리 화면에 직접 입력합니다.

개인 시험용으로 Gmail을 쓰는 경우에는 Google 계정의 **2단계 인증**을 켠 뒤 [앱 비밀번호](https://support.google.com/accounts/answer/185833?hl=ko)를 만듭니다. 일반 Google 로그인 비밀번호는 입력하지 않습니다. Supabase 화면의 예시 값 `noreply@yourdomain.com`이나 `your.smtp.host.com`을 그대로 저장하면 안 됩니다.

| Supabase 입력 칸 | Gmail 시험용 값 |
|---|---|
| Sender email address | 발송에 사용할 본인 Gmail 주소 |
| Sender name | `전설키우기` |
| Host | `smtp.gmail.com` |
| Port number | `465` |
| Username | 같은 Gmail 주소 전체 |
| Password | Google에서 새로 발급한 16자리 앱 비밀번호 |

Gmail 외의 SMTP 서비스를 사용한다면 그 서비스가 발급한 호스트·포트·계정·비밀번호와 인증된 발신 주소를 입력합니다. 실제 사용자에게 배포할 때는 메일 발송 전용 서비스를 설정합니다. [Google SMTP 안내](https://support.google.com/mail/answer/7104828?hl=ko)

### Gmail 오류 535 해결

Supabase Auth 로그에 `535 5.7.8 Username and Password not accepted`가 보이면 앱의 인증번호 기능이나 메일 템플릿 문제가 아니라 **Gmail SMTP 로그인 실패**입니다. Google 계정의 [앱 비밀번호 관리](https://support.google.com/accounts/answer/185833?hl=ko)에서 2단계 인증을 확인하고 `전설키우기`용 앱 비밀번호를 새로 발급합니다. Supabase `Authentication → Emails → SMTP Settings`의 Password에 그 16자리 앱 비밀번호를 입력하고 저장합니다. Username과 Sender email address는 앱 비밀번호를 만든 **같은 Gmail 주소**여야 합니다. 기존 Gmail 로그인 비밀번호나 Supabase API 키를 넣지 않습니다. 새 비밀번호는 채팅·코드·문서에 복사하지 않습니다.
2. Supabase 대시보드의 `Authentication → Emails → SMTP Settings → Set up SMTP`에서 발송 서비스를 연결하고 저장합니다. 메일이 실제로 발송되는지 확인합니다.
3. `Authentication → Emails → Templates → Confirm sign up`의 본문을 [가입 확인용 템플릿](../supabase/email_templates/confirm_signup.html) 내용으로 바꿉니다. 새 계정의 첫 요청에 이 템플릿이 사용됩니다.
4. `Magic link or OTP`의 본문을 [로그인용 템플릿](../supabase/email_templates/magic_link.html) 내용으로 바꿉니다. 이미 확인된 계정의 요청에 사용됩니다. 두 템플릿 모두 `{{ .Token }}`을 포함해야 합니다. 제목은 `전설키우기 인증번호`처럼 설정하고 저장합니다.
5. 앱에서 `인증번호 받기`를 눌러 **새 메일**을 요청합니다. 컴퓨터나 휴대폰에서 번호를 확인하고 앱의 `인증 코드`에 입력해 `코드 확인`을 누릅니다. 계정 화면에 `로그인됨`이 표시되는지 확인합니다. 기존에 받은 링크 메일의 URL에 있는 `code=...` 값은 인증번호가 아니므로 입력하지 않습니다.

Supabase는 2026년 6월부터 새 무료 프로젝트의 기본 발송 서비스에서 인증 메일 템플릿 수정을 제한합니다. 따라서 현재 대시보드의 `Set up custom SMTP to edit templates` 안내는 정상이며, 앱 코드만 바꿔서는 메일 본문을 인증번호로 전환할 수 없습니다. [정책 공지](https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier) · [SMTP 설정](https://supabase.com/docs/guides/auth/auth-smtp) · [템플릿 변수](https://supabase.com/docs/guides/auth/auth-email-templates)

SMTP 인증이 정상 동작하기 전에는 새 인증번호 메일을 받을 수 없습니다. 임시로 로그인해야 한다면 기존에 받은 유효한 링크를 **휴대폰에서** 열어 Android 앱으로 돌아올 수 있습니다. 이 링크는 컴퓨터에서 열면 Android 앱으로 이어지지 않습니다.

## 프로젝트 설정

1. Supabase 프로젝트에서 이메일 인증을 켭니다. `mpj` production 프로젝트는 켜져 있습니다.
2. `Authentication → URL Configuration → Redirect URLs`에 `com.example.growup://login-callback/`을 등록합니다. `mpj` 프로젝트에는 등록했습니다. 앱은 Android에서 메일을 보낼 때 이 주소를 `emailRedirectTo`로 지정합니다. Supabase의 기본 Site URL인 `http://localhost:3000`은 현재 Android 로그인 흐름에서 사용하지 않습니다.
3. 프로젝트 URL과 **publishable key**를 Flutter 빌드 설정으로 전달합니다. OpenAI API 키나 Supabase secret key는 앱에 전달하지 않습니다.
4. 계정 화면에서 목표를 동기화하려면 [DB 마이그레이션](GOAL_SYNC_DESIGN.md)을 적용하고 `GOAL_SYNC_ENABLED=true`로 빌드합니다. DB는 적용했지만 기능은 아직 검증 전이라 꺼져 있습니다.

기존 Android 링크 로그인 경로는 SMTP 설정 전의 임시 수단으로 유지합니다. `com.example.growup` 패키지명을 나중에 바꾸면 딥링크 주소와 Supabase 허용 목록도 함께 변경해야 합니다. 숫자 인증번호 로그인에는 딥링크나 `localhost:3000`이 필요하지 않습니다. 웹 버전도 동일한 번호 입력 방식으로 로그인할 수 있지만 아직 실제 브라우저에서 서버 메일을 이용한 검증은 하지 않았습니다.

```powershell
flutter run -d chrome `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=PUBLIC_KEY
```

Android도 같은 `--dart-define` 설정으로 빌드합니다. 이 작업 환경에는 전달받은 공개 설정을 `flutter_defines.env`에 저장하고 Git 무시 목록에 넣었습니다. 다음처럼 실행할 수도 있습니다.

```powershell
flutter build apk --debug --dart-define-from-file=flutter_defines.env
```

동기화 테이블은 있지만 현재 설치본의 동기화 버튼은 꺼져 있습니다. 실서비스 검증 뒤 `--dart-define=GOAL_SYNC_ENABLED=true`를 추가해야 합니다. `ROADMAP_AI_ENABLED=true`는 인증된 `generate-roadmap` 서버 함수가 배포되고 사용량 제한이 적용된 뒤에만 추가합니다.

```powershell
flutter build apk --debug `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=PUBLIC_KEY `
  --dart-define=GOAL_SYNC_ENABLED=true `
  --dart-define=ROADMAP_AI_ENABLED=true
```

앱은 세션을 복구하고, 계정 화면에서 코드 요청·확인·로그아웃을 처리합니다. AI 요청이 활성화되면 현재 사용자 세션의 JWT를 서버 함수로 보내며, 서버가 검증해야 합니다. 서버 계약은 [AI 로드맵 서버 연결 계약](AI_ROADMAP_CONTRACT.md)에 있습니다.

참고: [Supabase Flutter 초기화](https://supabase.com/docs/guides/getting-started/quickstarts/flutter), [이메일 OTP](https://supabase.com/docs/reference/dart/auth-signinwithotp), [OTP 확인](https://supabase.com/docs/reference/dart/auth-verifyotp), [이메일 템플릿](https://supabase.com/docs/guides/auth/auth-email-templates).
