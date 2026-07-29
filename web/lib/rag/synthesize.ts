// Swift 원본: KnowledgeRAG.swift의 private synthesize()+헬퍼 전체 1:1 포트.
// extractive fallback — LLM 없이도 항상 응답 가능한 1급 경로(액션플랜 §P6-6, G6-3).
import { expand } from "./query-terms";

export interface SynthesizeCitation {
  unitId: string;
  title: string;
  sourceType: string;
  snippet: string;
}

const SENTENCE_SEP_RE = /[.。!?？]/;

function label(sourceType: string): string {
  switch (sourceType) {
    case "meeting":
      return "미팅";
    case "notes":
      return "Notes";
    case "obsidian":
      return "Obsidian";
    case "file":
      return "파일";
    default:
      return sourceType;
  }
}

/** 원본 cleanSnippet(_:) — 마크다운 마커(#, -, *, [..]) 선행 제거. */
export function cleanSnippet(s: string): string {
  let t = s.replace(/\n+/g, " ").replace(/\s+/g, " ").trim();
  // 원본은 "[" 시작하되 "]"가 없으면 이론상 무한루프 버그가 있다 — 실제 인덱스
  // 데이터에선 발생하지 않지만, 서비스 안정성을 위해 최소 가드만 추가한다.
  let guardCount = 0;
  while ((t.startsWith("#") || t.startsWith("-") || t.startsWith("*") || t.startsWith("[")) && guardCount < 100) {
    guardCount++;
    if (t.startsWith("[")) {
      const idx = t.indexOf("]");
      if (idx !== -1) {
        t = t.slice(idx + 1).trim();
        continue;
      }
      break;
    }
    const stripped = t.replace(/^[#\-* ]+/, "");
    if (stripped === t) break;
    t = stripped;
  }
  return t;
}

/**
 * 원본 compressSentence(_:max:) — 원본에 죽은 분기가 있다: 두 번째 문장을
 * 이어붙이는 로직이 `t = first` 재할당 후 같은 인덱스로 다시 슬라이스해
 * `rest`가 항상 빈 문자열이 되므로 실질적으로 절대 실행되지 않는다.
 * "고치지 않고 그대로" 원칙(P4b `planSummary` 선례)에 따라 이 동작을 그대로 재현한다.
 */
export function compressSentence(s: string, max: number): string {
  let t = cleanSnippet(s);
  const m = t.match(SENTENCE_SEP_RE);
  if (m && m.index !== undefined) {
    const cutEnd = m.index + 1;
    const first = t.slice(0, cutEnd).trim();
    if (first.length >= 20) {
      t = first;
      const rest = t.slice(cutEnd).trim(); // 원본 버그 재현: 항상 ""
      if (first.length < 80 && rest.length > 0) {
        const m2 = rest.match(SENTENCE_SEP_RE);
        if (m2 && m2.index !== undefined) {
          const second = rest.slice(0, m2.index + 1).trim();
          if (second) t = `${first} ${second}`;
        }
      }
    }
  }
  if (t.length > max) t = t.slice(0, max - 1) + "…";
  return t;
}

/** 원본 looksLikeDirectAnswer(question:text:). */
export function looksLikeDirectAnswer(question: string, text: string): boolean {
  const toks = expand(question).filter((t) => t.length >= 2);
  if (toks.length === 0) return text.length >= 30;
  const lower = text.toLowerCase();
  const hit = toks.filter((t) => lower.includes(t.toLowerCase())).length;
  return hit / toks.length >= 0.25;
}

function decapitalizeIfNeeded(s: string): string {
  if (!s) return s;
  const first = s[0];
  if (/[A-Z]/.test(first)) return first.toLowerCase() + s.slice(1);
  return s;
}

function normalizeKey(s: string): string {
  return s.toLowerCase().replace(/\s+/g, "").slice(0, 80);
}

/** 원본 jaccard(_:_:) — 문자 집합 기준. */
export function jaccard(a: string, b: string): number {
  const sa = new Set(Array.from(a));
  const sb = new Set(Array.from(b));
  if (sa.size === 0 || sb.size === 0) return 0;
  let inter = 0;
  for (const c of sa) if (sb.has(c)) inter++;
  const union = new Set([...sa, ...sb]).size;
  return inter / union;
}

/** 원본 KnowledgeRAG.synthesize(question:citations:) 1:1. */
export function synthesize(question: string, citations: SynthesizeCitation[]): string {
  const tops = citations.slice(0, 5);
  const bullets = tops.map((c) => ({
    kind: label(c.sourceType),
    title: c.title,
    text: cleanSnippet(c.snippet),
  }));

  const parts: string[] = [];
  const best = bullets[0];
  if (best) {
    const lead = compressSentence(best.text, 180);
    if (looksLikeDirectAnswer(question, lead)) {
      parts.push(lead);
    } else {
      parts.push(`「${best.title}」 기준으로 보면, ${decapitalizeIfNeeded(lead)}`);
    }
  }

  const used = new Set(parts.map(normalizeKey));
  const supports: string[] = [];
  for (const b of bullets.slice(1)) {
    const line = compressSentence(b.text, 140);
    const key = normalizeKey(line);
    if (!key || used.has(key)) continue;
    let tooSimilar = false;
    for (const u of used) {
      if (jaccard(u, key) > 0.55) {
        tooSimilar = true;
        break;
      }
    }
    if (tooSimilar) continue;
    used.add(key);
    supports.push(`· ${line} (${b.kind} · ${b.title})`);
    if (supports.length >= 3) break;
  }
  if (supports.length > 0) {
    parts.push("");
    parts.push(...supports);
  }

  const sourceCount = new Set(tops.map((c) => c.unitId)).size;
  parts.push("");
  parts.push(`근거 ${sourceCount}개 출처 · 아래 카드를 누르면 원문으로 이동해요.`);
  return parts.join("\n");
}
