// Swift 원본: MobileHTTPServer.classifyIntent(message:mode:) 1:1.
// 조합 로직(diet/mixed/knowledge 분기)은 handlers.ts의 chat_send가 담당한다
// — diet_coach 등 기존 핸들러와 같은 파일에 둬야 순환 import 없이 재사용 가능.
export type ChatIntent = "diet" | "knowledge" | "mixed";

const DIET_CUES = [
  "먹", "식사", "운동", "칼로리", "체중", "다이어트", "단백질", "수면",
  "workout", "calorie", "meal", "점심", "저녁", "아침", "kcal",
];
const KNOWLEDGE_CUES = ["회의", "미팅", "요약", "노트", "기억", "vault", "지난주", "지난번", "프로젝트", "액션", "할 일", "결정"];
const CROSS_CUES = ["그리고", "vs", "대비", "비교", "같이", "동시에", "이번 주", "이번주", "목표랑", "목표와"];

function includesAny(message: string, lower: string, cues: string[]): boolean {
  return cues.some((c) => lower.includes(c) || message.includes(c));
}

export function classifyIntent(message: string, mode: string): ChatIntent {
  if (mode === "diet") return "diet";
  if (mode === "knowledge") return "knowledge";
  if (mode === "mixed") return "mixed";

  const lower = message.toLowerCase();
  const hasDiet = includesAny(message, lower, DIET_CUES);
  const hasKnowledge = includesAny(message, lower, KNOWLEDGE_CUES);
  const hasCross = includesAny(message, lower, CROSS_CUES);

  if ((hasDiet && hasKnowledge) || (hasDiet && hasCross) || (hasKnowledge && hasCross && hasDiet)) {
    return "mixed";
  }
  if (message.includes("단백질") && (message.includes("회의") || message.includes("목표"))) {
    return "mixed";
  }
  return hasDiet ? "diet" : "knowledge";
}

/** 원본 firstInt(in:) — 문자열 내 첫 정수. */
export function firstInt(text: string): number | null {
  const m = text.match(/\d+/);
  return m ? Number(m[0]) : null;
}

/** 원본 firstDouble(in:) — 문자열 내 첫 소수(정수 포함). */
export function firstDouble(text: string): number | null {
  const m = text.match(/\d+(?:\.\d+)?/);
  return m ? Number(m[0]) : null;
}
