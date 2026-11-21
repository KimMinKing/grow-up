# 첫 실행 로그인과 제공자 설정

앱을 실행할 때 저장된 세션이 없으면 로그인 화면이 먼저 열린다. 이메일 비밀번호 로그인, 이메일 회원가입, 기존 계정용 인증번호 로그인, 기기에만 저장하며 시작하기를 선택할 수 있다. 회원가입 후 확인 메일의 6자리 코드를 앱에 입력한다. 이미 이메일 인증번호로 사용하던 계정은 **비밀번호 없이 인증번호로 로그인**을 사용한다. 다른 로그인 방식으로 새 계정을 만들면 기존 계정의 서버 기록이 자동으로 합쳐지지 않는다.

Google·카카오 버튼은 Supabase의 제공자 설정이 켜지면 자동으로 활성화된다. 2026-11-07 확인 시 프로젝트 `ybblmftlbrdqzvehnnev`에서 두 제공자는 모두 꺼져 있다. 앱 코드와 Android 복귀 주소는 준비되어 있지만 실제 간편 로그인 검증은 제공자 설정 후 가능하다.

## 공통

1. 시험판은 Supabase → Authentication → URL Configuration → Redirect URLs에 `com.example.growup://login-callback/`을 등록한다. 정식 배포는 결정한 application ID의 `<application-id>://login-callback/`도 등록하고 앱 번들에 `LOGIN_REDIRECT_SCHEME=<application-id>`를 지정한다.
2. 제공자 개발자 콘솔의 OAuth 콜백 주소에는 `https://ybblmftlbrdqzvehnnev.supabase.co/auth/v1/callback`을 등록한다. 이것은 앱 복귀 주소와 다르다.
3. 클라이언트 비밀 값은 Supabase 대시보드에만 입력한다. 코드나 채팅에 붙여 넣지 않는다.

## Google

1. Google Cloud Console에서 OAuth 동의 화면을 설정하고 **웹 애플리케이션** 유형의 OAuth 클라이언트를 만든다.
2. 승인된 리디렉션 URI에 위 Supabase OAuth 콜백 주소를 추가한다.
3. Supabase → Authentication → Providers → Google에 클라이언트 ID와 보안 비밀을 입력하고 활성화한다.
4. 앱을 다시 열어 Google 버튼이 활성화되는지 확인하고, 브라우저 로그인 후 앱으로 복귀하는지 시험한다.

## 카카오

1. Kakao Developers에서 애플리케이션을 만들고 카카오 로그인을 활성화한다.
2. Redirect URI에 위 Supabase OAuth 콜백 주소를 등록하고 필요한 동의 항목을 설정한다.
3. Supabase → Authentication → Providers → Kakao에 REST API 키와 Client Secret을 입력하고 활성화한다.
4. 앱을 다시 열어 카카오 버튼이 활성화되는지 확인하고, 브라우저 로그인 후 앱으로 복귀하는지 시험한다. 카카오 계정이 이메일 제공에 동의하지 않아도 로그인할 수 있으므로 앱은 이메일 없는 계정도 표시한다.

참고: [Supabase Google 설정](https://supabase.com/docs/guides/auth/social-sign-in/auth-google), [Supabase 카카오 설정](https://supabase.com/docs/guides/auth/social-sign-in/auth-kakao), [리디렉션 URL](https://supabase.com/docs/guides/auth/redirect-urls).
