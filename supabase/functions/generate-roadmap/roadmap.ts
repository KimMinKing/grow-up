export type RoadmapRequest = {
  goal: string;
  currentLevel: string;
  targetDate: string;
  availableMinutes: number;
  preferredPath: string;
  mini: string;
  more: string;
  max: string;
  firstMilestone: string;
};

export async function readJsonRequest(
  request: Request,
  maxBytes = 4096,
): Promise<{ value: unknown } | { error: "too_large" | "invalid" }> {
  if (!request.body) return { error: "invalid" };
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel();
        return { error: "too_large" };
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return {
      value: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    };
  } catch (_) {
    return { error: "invalid" };
  } finally {
    reader.releaseLock();
  }
}

export const roadmapSchema = {
  type: "object",
  properties: {
    plans: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          summary: { type: "string" },
          weeklyTarget: { type: "integer" },
          durationWeeks: { type: "integer" },
          weeklyMinutes: { type: "integer" },
          milestones: { type: "array", items: { type: "string" } },
          firstWeekActions: { type: "array", items: { type: "string" } },
        },
        required: [
          "title",
          "summary",
          "weeklyTarget",
          "durationWeeks",
          "weeklyMinutes",
          "milestones",
          "firstWeekActions",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["plans"],
  additionalProperties: false,
} as const;

function boundedText(
  value: unknown,
  max: number,
  optional = false,
): value is string {
  return typeof value === "string" && value.trim().length <= max &&
    (optional || value.trim().length > 0);
}

export function parseRequest(value: unknown): RoadmapRequest | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const r = value as Record<string, unknown>;
  if (
    !boundedText(r.goal, 120) || !boundedText(r.currentLevel, 160) ||
    !boundedText(r.preferredPath, 60) || !boundedText(r.mini, 160) ||
    !boundedText(r.more, 160) || !boundedText(r.max, 160) ||
    !boundedText(r.firstMilestone, 120, true) ||
    !Number.isInteger(r.availableMinutes) ||
    (r.availableMinutes as number) < 1 ||
    (r.availableMinutes as number) > 10080 ||
    typeof r.targetDate !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(r.targetDate)
  ) return null;
  const date = new Date(`${r.targetDate}T00:00:00Z`);
  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== r.targetDate
  ) return null;
  return r as RoadmapRequest;
}

export function parsePlans(
  value: unknown,
  availableMinutes: number,
): Record<string, unknown>[] | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const plans = (value as Record<string, unknown>).plans;
  if (!Array.isArray(plans) || plans.length !== 3) return null;
  const titles = new Set<string>();
  const variants = new Set<string>();
  const pacing = new Set<string>();
  for (const plan of plans) {
    if (!plan || typeof plan !== "object" || Array.isArray(plan)) return null;
    const p = plan as Record<string, unknown>;
    if (
      !boundedText(p.title, 80) || !boundedText(p.summary, 500) ||
      !Number.isInteger(p.weeklyTarget) || (p.weeklyTarget as number) < 1 ||
      (p.weeklyTarget as number) > 7 || !Number.isInteger(p.durationWeeks) ||
      (p.durationWeeks as number) < 1 || (p.durationWeeks as number) > 104 ||
      !Number.isInteger(p.weeklyMinutes) || (p.weeklyMinutes as number) < 1 ||
      (p.weeklyMinutes as number) > availableMinutes ||
      !Array.isArray(p.milestones) || p.milestones.length < 1 ||
      p.milestones.length > 12 || !p.milestones.every((x: unknown) =>
        boundedText(x, 120)
      ) ||
      !Array.isArray(p.firstWeekActions) || p.firstWeekActions.length < 1 ||
      p.firstWeekActions.length > 7 ||
      !p.firstWeekActions.every((x: unknown) => boundedText(x, 160))
    ) return null;
    titles.add(p.title.trim());
    variants.add(JSON.stringify([
      p.summary,
      p.weeklyTarget,
      p.durationWeeks,
      p.weeklyMinutes,
      p.milestones,
      p.firstWeekActions,
    ]));
    pacing.add(JSON.stringify([
      p.weeklyTarget,
      p.durationWeeks,
      p.weeklyMinutes,
    ]));
  }
  return titles.size === 3 && variants.size === 3 && pacing.size === 3
    ? plans
    : null;
}

export function parseOpenAiResponse(value: unknown, availableMinutes: number) {
  if (!value || typeof value !== "object") return null;
  const response = value as Record<string, unknown>;
  if (response.status !== "completed" || !Array.isArray(response.output)) {
    return null;
  }
  const parts = response.output.flatMap((item: unknown) => {
    if (!item || typeof item !== "object") return [];
    const content = (item as Record<string, unknown>).content;
    return Array.isArray(content) ? content : [];
  });
  if (
    parts.some((part: unknown) =>
      part && typeof part === "object" &&
      (part as Record<string, unknown>).type === "refusal"
    )
  ) return null;
  const texts = parts.filter((part: unknown) =>
    part && typeof part === "object" &&
    (part as Record<string, unknown>).type === "output_text"
  );
  if (texts.length !== 1 || typeof texts[0].text !== "string") return null;
  try {
    return parsePlans(JSON.parse(texts[0].text), availableMinutes);
  } catch (_) {
    return null;
  }
}
