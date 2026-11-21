# AI 로드맵 서버 설정

`supabase/functions/generate-roadmap`는 로그인 JWT를 확인하고 OpenAI Responses API의 Structured Outputs로 계획 3개를 요청합니다. `supabase/migrations/20261031000000_ai_roadmap_usage.sql`은 사용자당 UTC 월 1회 성공, 실패 후 최대 2회 재시도, 전체 월간 비용 예약·기록을 처리합니다. 함수는 배포되지 않았고 실제 OpenAI 호출도 아직 검증하지 않았습니다.

## 배포 순서

1. [Supabase 프로젝트](AUTH_SETUP.md)를 준비하고 CLI에서 `supabase login`, `supabase link`를 실행합니다.
2. `supabase db push`로 마이그레이션을 적용합니다. 이 테이블은 앱에서 직접 조회하거나 수정할 수 없습니다.
3. Edge Function Secrets에 아래 값을 등록합니다. `SUPABASE_URL`과 서버용 키는 Supabase가 함수 환경에 제공합니다. 비밀 값은 앱의 `--dart-define`에 넣지 않습니다.
4. `supabase functions deploy generate-roadmap`을 실행합니다. `supabase/config.toml`의 `verify_jwt = true`를 유지합니다.
5. Android·웹 앱을 `ROADMAP_AI_ENABLED=true`로 빌드해 로그인, 성공, 월간 한도, 실패 후 수동 시작안을 실기기에서 확인합니다.

필요한 사용자 지정 Secrets:

| 이름 | 의미 |
|---|---|
| `OPENAI_API_KEY` | OpenAI API 비밀키 |
| `OPENAI_MODEL` | Structured Outputs를 지원하는 모델 ID |
| `OPENAI_INPUT_USD_PER_MILLION` | 해당 모델의 입력 100만 토큰당 USD 단가 |
| `OPENAI_OUTPUT_USD_PER_MILLION` | 해당 모델의 출력 100만 토큰당 USD 단가 |
| `ROADMAP_REQUEST_RESERVE_MICROS` | 요청 한 건에 미리 확보할 최대 예산, USD 백만분의 1 단위 |
| `ROADMAP_MONTH_BUDGET_MICROS` | 전체 사용자 월간 예산, 같은 단위 |

요청당 예약액은 `12000 × 입력 단가 + 3600 × 출력 단가` 이상이어야 합니다. 실제 사용 토큰을 기록하면서 예약액은 실제 비용으로 대체합니다. 모델 단가가 바뀌면 두 단가와 예약액을 함께 갱신하세요. 한도에 도달하면 함수는 429를 반환하고 앱은 수동 시작안으로 계속할 수 있습니다. 요청 본문은 `Content-Length`가 없어도 읽는 동안 UTF-8 4096바이트로 제한하며, 함수 호출 시간은 30초로 제한합니다.

함수는 OpenAI의 거절, 미완료, 형식 오류, 과도한 주당 시간에 대해 계획을 반환하지 않습니다. 실패 내역도 비용이 발생했다면 기록합니다. 로그와 DB에는 목표 문구나 OpenAI 원문 응답을 저장하지 않습니다. 예약만 남은 호출은 2분 뒤 다음 예약 시 실패로 전환합니다.

실제 생성 결과를 공개하기 전에는 [AI 로드맵 평가표](AI_ROADMAP_EVAL.md)의 서로 다른 목표 사례로 실행 가능성, 세 안의 차이, 첫 주 행동과 건강 관련 표현을 검토합니다.

참고: [Supabase Edge Function 인증](https://supabase.com/docs/guides/functions/auth), [DB 마이그레이션 배포](https://supabase.com/docs/guides/deployment/database-migrations), [함수 비밀 환경 변수](https://supabase.com/docs/guides/functions/secrets), [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses), [OpenAI API 요금](https://developers.openai.com/api/docs/pricing).
