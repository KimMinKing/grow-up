import { createClient } from "npm:@supabase/supabase-js@2";
import {
  parseOpenAiResponse,
  parseRequest,
  readJsonRequest,
  roadmapSchema,
} from "./roadmap.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>): Response {
  return Response.json(body, { status, headers: cors });
}

function positiveNumber(name: string): number | null {
  const value = Number(Deno.env.get(name));
  return Number.isFinite(value) && value > 0 ? value : null;
}

function secretKey(): string | null {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys);
      if (typeof parsed.default === "string") return parsed.default;
    } catch (_) { /* Missing or invalid configuration is handled below. */ }
  }
  return Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

type TokenUsage = { input_tokens: number; output_tokens: number };

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const jwt = /^Bearer (.+)$/.exec(request.headers.get("authorization") ?? "")
    ?.[1];
  if (!jwt) return json(401, { error: "authentication_required" });

  const url = Deno.env.get("SUPABASE_URL");
  const key = secretKey();
  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL");
  const requestReserve = positiveNumber("ROADMAP_REQUEST_RESERVE_MICROS");
  const monthBudget = positiveNumber("ROADMAP_MONTH_BUDGET_MICROS");
  const inputRate = positiveNumber("OPENAI_INPUT_USD_PER_MILLION");
  const outputRate = positiveNumber("OPENAI_OUTPUT_USD_PER_MILLION");
  if (
    !url || !key || !openAiKey || !model || !requestReserve || !monthBudget ||
    !inputRate || !outputRate || !Number.isSafeInteger(requestReserve) ||
    !Number.isSafeInteger(monthBudget) || monthBudget < requestReserve ||
    requestReserve < Math.ceil(12000 * inputRate + 3600 * outputRate)
  ) {
    return json(503, { error: "service_not_configured" });
  }

  const supabase = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser(jwt);
  if (userError || !user) {
    return json(401, { error: "authentication_required" });
  }

  if (Number(request.headers.get("content-length") ?? 0) > 4096) {
    return json(413, { error: "request_too_large" });
  }
  const parsed = await readJsonRequest(request);
  if ("error" in parsed) {
    return parsed.error === "too_large"
      ? json(413, { error: "request_too_large" })
      : json(400, { error: "invalid_request" });
  }
  const brief = parseRequest(parsed.value);
  if (!brief) {
    return json(400, { error: "invalid_request" });
  }

  const monthStart = new Date().toISOString().slice(0, 7) + "-01";
  const { data: reservation, error: reserveError } = await supabase.rpc(
    "reserve_ai_roadmap_call",
    {
      p_user_id: user.id,
      p_month_start: monthStart,
      p_request_budget_micros: requestReserve,
      p_month_budget_micros: monthBudget,
    },
  );
  if (reserveError) return json(503, { error: "quota_unavailable" });
  if (!reservation) return json(429, { error: "monthly_limit_reached" });

  let plans: Record<string, unknown>[] | null = null;
  let usage: TokenUsage = { input_tokens: 0, output_tokens: 0 };
  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        store: false,
        max_output_tokens: 3600,
        instructions:
          "한국어로 현실적인 성장 로드맵 세 안을 만드세요. 각 안은 실천 부담과 속도가 달라야 합니다. 사용자의 주당 가능 시간을 넘기지 말고, 첫 주 행동은 구체적이고 작게 쓰세요. 건강·운동 목표에는 진단이나 위험한 강도 권고를 피하세요. JSON 스키마를 따르세요.",
        input: JSON.stringify(brief),
        text: {
          format: {
            type: "json_schema",
            name: "roadmap_options",
            strict: true,
            schema: roadmapSchema,
          },
        },
      }),
      signal: AbortSignal.timeout(30000),
    });
    if (response.ok) {
      const body = await response.json();
      const tokens = body?.usage;
      if (
        Number.isSafeInteger(tokens?.input_tokens) &&
        tokens.input_tokens >= 0 &&
        Number.isSafeInteger(tokens?.output_tokens) && tokens.output_tokens >= 0
      ) {
        usage = {
          input_tokens: tokens.input_tokens,
          output_tokens: tokens.output_tokens,
        };
      }
      plans = parseOpenAiResponse(body, brief.availableMinutes);
    }
  } catch (_) {
    // The app keeps the user's draft and offers the manual plan on failure.
  }

  const actualMicros = Math.ceil(
    usage.input_tokens * inputRate + usage.output_tokens * outputRate,
  );
  const { error: finishError } = await supabase.rpc("finish_ai_roadmap_call", {
    p_id: reservation,
    p_user_id: user.id,
    p_success: plans !== null,
    p_input_tokens: usage.input_tokens,
    p_output_tokens: usage.output_tokens,
    p_actual_micros: actualMicros,
  });
  if (finishError) return json(503, { error: "usage_record_failed" });
  return plans
    ? json(200, { plans })
    : json(502, { error: "generation_failed" });
});
