# AI 로드맵 서버 연결 계약

앱의 `HttpRoadmapGenerator`는 로그인한 사용자의 JWT로 HTTPS 서버 함수에 요청합니다. 이메일 코드 로그인과 서버 함수 코드는 준비되어 있으나 Supabase 프로젝트에 배포되지 않아 기본 빌드의 실제 AI 호출은 꺼져 있습니다. OpenAI API 키는 서버의 비밀 환경 변수로만 관리합니다. 배포 절차는 [서버 설정 안내](AI_SERVER_SETUP.md)에 있습니다.

## 요청

`POST /functions/v1/generate-roadmap`

- `Authorization: Bearer <사용자 JWT>`
- `apikey: <Supabase 공개 키>` (Supabase 사용 시)
- `Content-Type: application/json`

```json
{
  "goal": "책 읽는 습관 만들기",
  "currentLevel": "이제 시작함",
  "targetDate": "2027-01-31",
  "availableMinutes": 120,
  "preferredPath": "균형 있게",
  "mini": "책 2쪽 읽기",
  "more": "책 15분 읽기",
  "max": "책 40분 읽기",
  "firstMilestone": "첫 책 한 권 끝내기"
}
```

서버는 JWT를 검증하고 사용자별 월간 호출 횟수와 전체 월간 비용 한도를 확인합니다. 목표 텍스트와 행동 문구는 AI 요청에 필요한 범위만 전달합니다.

## 정상 응답

HTTP 200의 JSON 객체에 `plans` 배열을 정확히 3개 넣습니다. 각 계획은 다음 필드를 가집니다.

```json
{
  "plans": [
    {
      "title": "가벼운 안",
      "summary": "작은 실천부터 시작합니다.",
      "weeklyTarget": 2,
      "durationWeeks": 8,
      "weeklyMinutes": 60,
      "milestones": ["첫 주 적응", "첫 책 완독"],
      "firstWeekActions": ["월요일에 책 2쪽 읽기", "목요일에 책 15분 읽기"]
    }
  ]
}
```

위 JSON은 한 계획의 **형식 예시**입니다. 실제 응답에는 제목·내용뿐 아니라 주간 실천일·기간·주당 예상 시간의 조합도 서로 다른 계획 세 개가 필요합니다. 앱은 기간 1~104주, 주간 실천 1~7일, 주당 예상 시간 1~10080분을 확인하며 예상 시간이 사용자가 입력한 가능 시간을 넘으면 거부합니다. 이정표는 1~12개, 첫 주 행동은 1~7개가 필요합니다.

서버가 오류를 보내거나 응답이 검증에 실패하면 현재 입력 내용은 유지되고 수동 시작안으로 계속 진행할 수 있습니다. AI 계획을 선택하면 그 계획의 이정표가 현재 로드맵으로 저장되고, 선택한 계획 자체도 처음 선택한 계획으로 보존됩니다.

## 배포 시 확인

1. Supabase 사용자 인증을 켜고 함수의 JWT 검증을 유지합니다.
2. 서버에 OpenAI API 키·모델·토큰 단가·월간 예산을 비밀 환경 변수로 등록합니다. 앱 바이너리와 웹 코드에는 넣지 않습니다.
3. SQL 마이그레이션을 적용한 뒤 Edge Function을 배포합니다.
4. 로그인·서버 함수 배포 후 실제 Android와 웹에서 성공 및 수동 복귀 흐름을 확인합니다.

참고: [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses), [OpenAI API 키 보관](https://developers.openai.com/api/reference/overview), [Supabase Edge Function 인증](https://supabase.com/docs/guides/functions/auth).
