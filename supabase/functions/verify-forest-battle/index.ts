import { createClient } from "npm:@supabase/supabase-js@2";
import { simulateForestBattle } from "./battle_engine.mjs";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const stageIds = new Set([
  "forest_moss_gate",
  "forest_firefly_path",
  "forest_dawn_lookout",
  "river_mist_entry",
  "river_shallow_crossing",
  "river_moon_ferry",
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function reply(status: number, payload: Record<string, unknown>): Response {
  return Response.json(payload, { status, headers: cors });
}

function secretKey(): string | null {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys);
      if (typeof parsed.default === "string") return parsed.default;
    } catch (_) { /* Fallback to the older service key below. */ }
  }
  return Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

type Attempt = {
  requestId: string;
  stageId: string;
  status: "pending" | "resolved" | "expired";
  squad: ({ id: string; speciesId: string; level: number } | null)[];
  won?: boolean;
  stars?: number;
  turns?: number;
  experienceAwarded?: number;
  firstClearShards?: number;
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const jwt = /^Bearer (.+)$/i.exec(request.headers.get("authorization") ?? "")
    ?.[1];
  if (!jwt) return reply(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const key = secretKey();
  if (!url || !publicKey || !key) {
    return reply(503, { error: "service_not_configured" });
  }
  let body: unknown;
  try {
    if (Number(request.headers.get("content-length") ?? 0) > 1024) {
      return reply(413, { error: "request_too_large" });
    }
    body = await request.json();
  } catch (_) {
    return reply(400, { error: "invalid_request" });
  }
  if (!body || typeof body !== "object") {
    return reply(400, { error: "invalid_request" });
  }
  const { stageId, requestId } = body as Record<string, unknown>;
  if (typeof stageId !== "string" || !stageIds.has(stageId) ||
      typeof requestId !== "string" || !uuid.test(requestId)) {
    return reply(400, { error: "invalid_battle_request" });
  }

  const admin = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !user) return reply(401, { error: "authentication_required" });

  const player = createClient(url, publicKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: rawAttempt, error: startError } = await player.rpc(
    "begin_game_forest_battle",
    { p_request_id: requestId, p_stage_id: stageId },
  );
  if (startError) {
    return reply(startError.code === "22023" ? 409 : 503,
      { error: "battle_start_failed", reason: startError.message });
  }
  const attempt = rawAttempt as Attempt;
  if (!attempt || attempt.requestId !== requestId ||
      attempt.stageId !== stageId) {
    return reply(503, { error: "invalid_server_attempt" });
  }
  if (attempt.status === "resolved") {
    const { data: saved, error: savedError } = await player
      .from("game_battle_attempts")
      .select("companion_species_id")
      .eq("request_id", requestId)
      .single();
    if (savedError || !saved) {
      return reply(503, { error: "battle_result_unavailable" });
    }
    return reply(200, {
      requestId, stageId, won: attempt.won, stars: attempt.stars,
      turns: attempt.turns, experienceAwarded: attempt.experienceAwarded,
      firstClearShards: attempt.firstClearShards, alreadyResolved: true,
      companionSpeciesId: saved.companion_species_id,
    });
  }
  if (attempt.status !== "pending" || !Array.isArray(attempt.squad)) {
    return reply(409, { error: "battle_attempt_expired" });
  }

  let result;
  try {
    // The squad is the database snapshot, never a field from the request body.
    result = simulateForestBattle(stageId, attempt.squad);
  } catch (_) {
    return reply(503, { error: "invalid_server_squad" });
  }
  const { data: resolved, error: finishError } = await admin.rpc(
    "finish_game_forest_battle",
    {
      p_request_id: requestId,
      p_won: result.won,
      p_stars: result.stars,
      p_turns: result.turns,
    },
  );
  if (finishError) {
    return reply(finishError.code === "22023" ? 409 : 503,
      { error: "battle_finish_failed", reason: finishError.message });
  }
  return reply(200, {
    stageId, ...resolved, remainingHp: result.remainingHp,
  });
});
