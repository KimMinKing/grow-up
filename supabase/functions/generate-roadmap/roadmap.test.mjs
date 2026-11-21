import assert from "node:assert/strict";
import test from "node:test";
import {
  parseOpenAiResponse,
  parsePlans,
  parseRequest,
  readJsonRequest,
} from "./roadmap.ts";

const brief = {
  goal: "책 읽는 습관",
  currentLevel: "시작",
  targetDate: "2027-01-31",
  availableMinutes: 120,
  preferredPath: "균형",
  mini: "2쪽",
  more: "15분",
  max: "40분",
  firstMilestone: "",
};
const plan = (index) => ({
  title: `안 ${index}`,
  summary: `${index}번째 실천안`,
  weeklyTarget: index + 1,
  durationWeeks: 8,
  weeklyMinutes: index * 20,
  milestones: ["첫 주 적응"],
  firstWeekActions: ["월요일에 2쪽 읽기"],
});
const plans = [plan(1), plan(2), plan(3)];

test("request rejects malformed dates and unrealistic time", () => {
  assert.deepEqual(parseRequest(brief), brief);
  assert.equal(parseRequest({ ...brief, targetDate: "2027-02-30" }), null);
  assert.equal(parseRequest({ ...brief, availableMinutes: 0 }), null);
  assert.equal(parseRequest({ ...brief, goal: "a".repeat(121) }), null);
});

test("request body is limited by UTF-8 bytes without a length header", async () => {
  const valid = new Request("http://localhost", {
    method: "POST",
    body: JSON.stringify(brief),
  });
  assert.deepEqual(await readJsonRequest(valid), { value: brief });

  const oversized = new Request("http://localhost", {
    method: "POST",
    body: JSON.stringify({ ...brief, goal: "가".repeat(1400) }),
  });
  assert.deepEqual(await readJsonRequest(oversized), { error: "too_large" });

  const invalid = new Request("http://localhost", {
    method: "POST",
    body: "{broken",
  });
  assert.deepEqual(await readJsonRequest(invalid), { error: "invalid" });
});

test("three distinct plans must fit the weekly time", () => {
  assert.equal(parsePlans({ plans }, 120)?.length, 3);
  assert.equal(parsePlans({ plans }, 40), null);
  assert.equal(
    parsePlans({ plans: [plans[0], plans[0], plans[2]] }, 120),
    null,
  );
  assert.equal(
    parsePlans({
      plans: [
        { ...plans[0], summary: "첫 번째 설명", weeklyTarget: 3, weeklyMinutes: 40 },
        { ...plans[1], summary: "두 번째 설명" },
        { ...plans[2], summary: "세 번째 설명", weeklyTarget: 3, weeklyMinutes: 40 },
      ],
    }, 120),
    null,
  );
  assert.equal(parsePlans({ plans: [plans[0], plans[1]] }, 120), null);
});

test("OpenAI refusal and incomplete output never reach the app", () => {
  const complete = {
    status: "completed",
    output: [{
      content: [{ type: "output_text", text: JSON.stringify({ plans }) }],
    }],
  };
  assert.equal(parseOpenAiResponse(complete, 120)?.length, 3);
  assert.equal(
    parseOpenAiResponse({ ...complete, status: "incomplete" }, 120),
    null,
  );
  assert.equal(
    parseOpenAiResponse({
      status: "completed",
      output: [
        { content: [{ type: "refusal", refusal: "cannot answer" }] },
      ],
    }, 120),
    null,
  );
});
