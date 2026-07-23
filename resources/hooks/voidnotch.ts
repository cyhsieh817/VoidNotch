// VoidNotch pi 擴充：
//   ① 把 pi 生命週期事件寫進 agent-events.jsonl，供 VoidNotch 顯示活動狀態。
//   ② 註冊 `question` 工具，讓 pi 的提問直接彈到瀏海作答（沿用 Claude 那條檔案 broker 協議）。
// 自動探索路徑：~/.pi/agent/extensions/voidnotch.ts
//
// 停用本擴充時**不可**只加 `_DELETE_` 前綴：pi 的 loader 只看副檔名（.ts/.js），
// 前綴檔照樣被載入並重複註冊 handler。請改副檔名或移出 extensions 目錄。
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";

/** PiHookAdapter 靠這個字串判斷已安裝的擴充夠不夠新；改動 broker 協議時務必連號一起升。 */
export const QUESTION_TOOL_MARKER = "voidnotch-question-tool-v1";

/** 瀏海沒人回答時的等待上限。逾時就把提問交還終端機，不讓 agent 無限期卡住。 */
const DEFAULT_TIMEOUT_MS = 120_000;
const DEFAULT_POLL_MS = 100;

export function eventFile(): string {
  const override = process.env.VOIDNOTCH_AGENT_EVENTS;
  if (override && override.trim()) return override.replace(/^~/, homedir());
  return join(homedir(), "Library", "Application Support", "VoidNotch", "agent-events.jsonl");
}

export function responseDir(): string {
  const override = process.env.VOIDNOTCH_RESPONSE_DIR;
  if (override && override.trim()) return override.replace(/^~/, homedir());
  return join(homedir(), "Library", "Application Support", "VoidNotch", "responses");
}

/** 與 relay 一致：支援 VOIDNOTCH_SUPPORT_DIR，預設 ~/Library/Application Support/VoidNotch。 */
export function supportDir(): string {
  const override = process.env.VOIDNOTCH_SUPPORT_DIR;
  if (override && override.trim()) return override.replace(/^~/, homedir());
  return join(homedir(), "Library", "Application Support", "VoidNotch");
}

/**
 * App 宣告的可代答 provider 清單（broker-capabilities.json）。
 * fail-closed：檔案缺失、JSON 損壞、或 answerable_providers 不是 list 時回空陣列，
 * 不建立 input_request，只照常寫一般活動事件。
 */
export function answerableProviders(): string[] {
  try {
    const path = join(supportDir(), "broker-capabilities.json");
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    const declared = parsed?.answerable_providers;
    if (!Array.isArray(declared)) return [];
    return declared.map((item: unknown) => String(item));
  } catch {
    return [];
  }
}

/** pi 是否在 App 宣告的可代答清單內。不在就不接管，回退終端機。 */
export function isPiAnswerable(): boolean {
  return answerableProviders().includes("pi");
}

function appendRecord(record: Record<string, unknown>) {
  const file = eventFile();
  mkdirSync(dirname(file), { recursive: true });
  appendFileSync(file, JSON.stringify(record) + "\n", "utf8");
  try {
    const lines = readFileSync(file, "utf8").split("\n").filter(Boolean);
    if (lines.length > 5000) writeFileSync(file, lines.slice(-1000).join("\n") + "\n", "utf8");
  } catch { /* 忽略截尾錯誤 */ }
}

function write(status: string, title: string, detail: string | null, cwd: string) {
  appendRecord({
    id: randomUUID(),
    provider: "pi",
    status,
    hook_event_name: null,
    category: null,
    title,
    detail,
    workspace: cwd.split("/").filter(Boolean).pop() || null,
    cwd,
    timestamp: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
  });
}

export interface QuestionOption {
  label: string;
  description?: string;
}

/** 把一則提問公告到 agent-events.jsonl，回傳 request_id（小寫，與 relay 的 uuid4 格式一致）。 */
export function publishQuestion(args: {
  question: string;
  header: string;
  options: QuestionOption[];
  cwd: string;
}): string {
  const requestID = randomUUID().toLowerCase();
  const questions = [{
    question: args.question,
    header: args.header,
    options: args.options.map((o) => ({ label: o.label, description: o.description ?? "" })),
    multiSelect: false,
  }];
  appendRecord({
    id: requestID,
    provider: "pi",
    status: "needsInput",
    hook_event_name: null,
    category: "input.required",
    title: "pi needs input",
    detail: args.question,
    workspace: args.cwd.split("/").filter(Boolean).pop() || null,
    cwd: args.cwd,
    timestamp: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    input_request: { request_id: requestID, questions },
  });
  return requestID;
}

export type AnswerOutcome =
  | { kind: "answered"; answer: string }
  | { kind: "dismissed" }
  | { kind: "timeout" };

/**
 * 輪詢 VoidNotch 寫回的回應檔。
 *
 * App 端 Swift 的 `UUID.uuidString` 一律大寫，這裡的 request_id 是小寫，
 * 兩端必須大小寫無關地對得上——這正是先前 Claude 那條路徑上唯一的斷點。
 * 大小寫不敏感的檔案系統會讓大寫檔名也「開得起來」，所以比對絕不能只靠開檔成功。
 */
export async function awaitAnswer(
  requestID: string,
  opts: { timeoutMs?: number; pollMs?: number } = {},
): Promise<AnswerOutcome> {
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const pollMs = opts.pollMs ?? DEFAULT_POLL_MS;
  const dir = responseDir();
  const candidates = [
    join(dir, `${requestID}.json`),
    join(dir, `${requestID.toUpperCase()}.json`),
  ];
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    for (const candidate of candidates) {
      let parsed: any;
      try {
        parsed = JSON.parse(readFileSync(candidate, "utf8"));
      } catch {
        continue;  // 尚未寫入，或正寫到一半
      }
      if (String(parsed?.request_id ?? "").toLowerCase() !== requestID.toLowerCase()) continue;
      if (parsed.dismissed === true) return { kind: "dismissed" };
      const answers = parsed.answers;
      if (answers && typeof answers === "object") {
        const values = Object.values(answers).filter((v) => typeof v === "string" && v.length > 0);
        if (values.length > 0) return { kind: "answered", answer: values[0] as string };
      }
    }
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  return { kind: "timeout" };
}

/** VoidNotch 沒在跑就別公告到瀏海，直接在終端機問，否則使用者要乾等到 timeout。 */
function notchIsRunning(): boolean {
  try {
    const out = execFileSync("/usr/bin/pgrep", ["-x", "VoidNotch"], { encoding: "utf8" });
    return out.trim().length > 0;
  } catch {
    return false;  // pgrep 找不到行程時以非零退出
  }
}

export default function (pi: any) {
  pi.on("session_start", async (_event: any, ctx: any) => {
    write("started", "pi started", null, ctx?.cwd ?? process.cwd());
  });
  pi.on("turn_end", async (_event: any, ctx: any) => {
    write("completed", "pi completed", null, ctx?.cwd ?? process.cwd());
  });
  pi.on("session_shutdown", async (_event: any, ctx: any) => {
    write("stopped", "pi stopped", null, ctx?.cwd ?? process.cwd());
  });

  // question 工具：先送瀏海，使用者關掉卡片或逾時就回退終端機選單。
  // 語意與 Claude 的 AskUserQuestion 對齊，pi 端沒有內建等價工具，故自行註冊。
  pi.registerTool({
    name: "question",
    label: "Question",
    description:
      "Ask the user a question and let them pick from options. " +
      "The question is shown in the VoidNotch notch for one-tap answering, " +
      "falling back to the terminal. Use when you need a decision to proceed.",
    parameters: {
      type: "object",
      properties: {
        question: { type: "string", description: "The question to ask the user" },
        header: { type: "string", description: "Short label (max ~12 chars) shown as a chip" },
        options: {
          type: "array",
          description: "Options for the user to choose from",
          items: {
            type: "object",
            properties: {
              label: { type: "string", description: "Display label for the option" },
              description: { type: "string", description: "Optional detail shown below the label" },
            },
            required: ["label"],
          },
        },
      },
      required: ["question", "options"],
    },
    executionMode: "sequential",

    async execute(_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any) {
      const cwd = ctx?.cwd ?? process.cwd();
      const options: QuestionOption[] = Array.isArray(params.options) ? params.options : [];
      const labels = options.map((o) => o.label);
      const header = typeof params.header === "string" && params.header ? params.header : "pi";

      if (labels.length === 0) {
        return {
          content: [{ type: "text", text: "Error: question tool requires at least one option." }],
          isError: true,
        };
      }

      // ① 瀏海：VoidNotch 在跑且 App 宣告能答 pi 才公告 input_request；
      //    否則只走終端機（fail-closed：capabilities 缺失／損壞／不含 pi 都不接管）。
      if (notchIsRunning() && isPiAnswerable()) {
        const requestID = publishQuestion({ question: params.question, header, options, cwd });
        const outcome = await awaitAnswer(requestID);
        if (outcome.kind === "answered") {
          return {
            content: [{ type: "text", text: `User selected: ${outcome.answer}` }],
            details: { question: params.question, options: labels, answer: outcome.answer },
          };
        }
        // dismissed / timeout：交還終端機，不吞掉使用者的輸入需求。
      }

      // ② 終端機回退。
      if (!ctx?.hasUI) {
        return {
          content: [{
            type: "text",
            text: "Error: no answer received (VoidNotch not answering and no interactive UI available).",
          }],
          isError: true,
        };
      }
      const picked = await ctx.ui.select(params.question, labels);
      if (typeof picked !== "string" || !picked) {
        return {
          content: [{ type: "text", text: "User cancelled the question without answering." }],
          details: { question: params.question, options: labels, answer: null },
        };
      }
      return {
        content: [{ type: "text", text: `User selected: ${picked}` }],
        details: { question: params.question, options: labels, answer: picked },
      };
    },
  });
}
