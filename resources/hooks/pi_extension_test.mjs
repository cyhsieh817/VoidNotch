// pi_extension_test.mjs — voidnotch.ts（pi extension）的 broker 測試。
// 以 node --experimental-strip-types 直接載入 TS；只測純函式，不需啟動 pi。
//
// 執行：node --experimental-strip-types resources/hooks/pi_extension_test.mjs

import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const TMP = mkdtempSync(join(tmpdir(), "voidnotch-pi-"));
const EVENTS = join(TMP, "agent-events.jsonl");
const RESPONSES = join(TMP, "responses");
mkdirSync(RESPONSES, { recursive: true });

process.env.VOIDNOTCH_AGENT_EVENTS = EVENTS;
process.env.VOIDNOTCH_RESPONSE_DIR = RESPONSES;

const { publishQuestion, awaitAnswer, QUESTION_TOOL_MARKER } = await import("./voidnotch.ts");

let fail = 0;
const check = (ok, label) => {
    if (!ok) {
        console.log(`FAIL: ${label}`);
        fail = 1;
    }
};

// 0) marker 必須存在（PiHookAdapter 靠它判斷已安裝版本夠不夠新）
check(typeof QUESTION_TOOL_MARKER === "string" && QUESTION_TOOL_MARKER.length > 0, "QUESTION_TOOL_MARKER 缺失");

// 1) publishQuestion 寫出 pi / needsInput / input_request，且 request_id 為小寫
const options = [
    { label: "甲", description: "第一個" },
    { label: "乙", description: "" },
];
const requestID = publishQuestion({
    question: "選一個",
    header: "測試",
    options,
    cwd: "/tmp/proj",
});
const record = JSON.parse(readFileSync(EVENTS, "utf8").trim().split("\n").pop());
check(record.provider === "pi", "provider 應為 pi");
check(record.status === "needsInput", "status 應為 needsInput");
check(record.input_request?.request_id === requestID, "input_request.request_id 不符");
check(requestID === requestID.toLowerCase(), "request_id 必須小寫（與 relay 一致）");
check(record.input_request?.questions?.[0]?.options?.length === 2, "options 未帶出");
check(record.input_request?.questions?.[0]?.multiSelect === false, "multiSelect 應為 false");
check(record.workspace === "proj", "workspace 應取自 cwd");

// 2) App 端（Swift UUID.uuidString）寫的是大寫檔名與大寫 request_id，broker 必須吃得下。
//    這是先前 Claude 那條路徑上真正的斷點，這裡直接鎖住。
const upper = requestID.toUpperCase();
writeFileSync(
    join(RESPONSES, `${upper}.json`),
    JSON.stringify({ request_id: upper, answers: { 選一個: "乙" } }),
);
const answered = await awaitAnswer(requestID, { timeoutMs: 5000, pollMs: 50 });
check(answered.kind === "answered", `應收到答案，實得 ${answered.kind}`);
check(answered.answer === "乙", `答案應為「乙」，實得 ${answered.answer}`);

// 3) dismissed：使用者關掉瀏海卡片 → 立即放行，交還終端機提問
const dismissID = publishQuestion({ question: "Q2", header: "H", options, cwd: "/tmp/proj" });
writeFileSync(
    join(RESPONSES, `${dismissID}.json`),
    JSON.stringify({ request_id: dismissID, dismissed: true }),
);
const dismissed = await awaitAnswer(dismissID, { timeoutMs: 5000, pollMs: 50 });
check(dismissed.kind === "dismissed", `應為 dismissed，實得 ${dismissed.kind}`);

// 4) timeout：沒人回答就放行，不可無限期卡住 agent
const timeoutID = publishQuestion({ question: "Q3", header: "H", options, cwd: "/tmp/proj" });
const started = Date.now();
const timedOut = await awaitAnswer(timeoutID, { timeoutMs: 400, pollMs: 50 });
const elapsed = Date.now() - started;
check(timedOut.kind === "timeout", `應為 timeout，實得 ${timedOut.kind}`);
check(elapsed < 3000, `timeout 應及時返回，實花 ${elapsed}ms`);

rmSync(TMP, { recursive: true, force: true });
if (fail === 0) console.log("pi_extension_test: ALL PASS");
process.exit(fail);
