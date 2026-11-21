import { createClient } from "npm:@supabase/supabase-js@2";
import { readSmallJson } from "./request_body.mjs";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, error?: string): Response {
  return Response.json(error ? { error } : { deleted: true }, {
    status,
    headers: cors,
  });
}

function secretKey(): string | null {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys);
      if (typeof parsed.default === "string") return parsed.default;
    } catch (_) { /* The missing configuration is handled below. */ }
  }
  return Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") return reply(405, "method_not_allowed");

  const jwt = /^Bearer (.+)$/.exec(request.headers.get("authorization") ?? "")
    ?.[1];
  if (!jwt) return reply(401, "authentication_required");

  const url = Deno.env.get("SUPABASE_URL");
  const key = secretKey();
  if (!url || !key) return reply(503, "service_not_configured");

  const admin = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !user || !user.email) {
    return reply(401, "authentication_required");
  }
  const parsed = await readSmallJson(request);
  if (parsed.error === "request_too_large") {
    return reply(413, "request_too_large");
  }
  if (parsed.error || typeof parsed.value !== "object" ||
      parsed.value === null || Array.isArray(parsed.value)) {
    return reply(400, "invalid_request");
  }
  const confirmation = parsed.value as Record<string, unknown>;
  if (
    confirmation.confirmation !== "DELETE_ACCOUNT" ||
    confirmation.email !== user.email
  ) {
    return reply(400, "confirmation_required");
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return reply(503, "deletion_failed");
  return reply(200);
});
