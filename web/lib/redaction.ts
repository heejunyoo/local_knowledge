// Swift 원본: Packages/KnowledgeWorkers/Sources/KnowledgeWorkers/RedactionPreflight.swift
// 데이터는 docs/redaction_patterns.json · docs/redaction_allowlist.json을 그대로 쓴다
// (정적 import — Vercel Root Directory가 web/이라 런타임 fs 읽기는 배포 시 누락될
// 수 있고, 정적 import는 빌드 시점에 번들에 인라인되어 그 경계와 무관하다).
import patternsFile from "../../docs/redaction_patterns.json";
import allowlistFile from "../../docs/redaction_allowlist.json";

export interface RedactionHit {
  id: string;
  label: string;
}

export interface RedactionResult {
  allowed: boolean;
  hits: RedactionHit[];
  message: string;
}

function compilePattern(regex: string): RegExp {
  // 원본 패턴 중 하나(`bearer_token`)가 Python/ICU식 인라인 플래그 `(?i)`
  // 접두를 쓴다 — JS RegExp는 이 문법이 없으므로 벗겨서 `i` 플래그로 옮긴다.
  if (regex.startsWith("(?i)")) {
    return new RegExp(regex.slice(4), "gi");
  }
  return new RegExp(regex, "g");
}

const compiledPatterns = patternsFile.patterns.map((p) => ({
  id: p.id,
  label: p.label,
  re: compilePattern(p.regex),
}));

const allowlist: string[] = allowlistFile.allowed_exact;

/** 클라우드 LLM 프리플라이트: 프롬프트에서 고위험 시크릿을 차단한다. */
export function scan(text: string): RedactionResult {
  const hits: RedactionHit[] = [];

  // compiledPatterns의 id는 정의상 유일하므로(패턴 하나당 id 하나) 별도
  // dedupe 없이도 hits는 자연히 id당 최대 1건이다.
  for (const { id, label, re } of compiledPatterns) {
    re.lastIndex = 0;
    for (const match of text.matchAll(re)) {
      const frag = match[0];
      if (allowlist.some((entry) => frag.includes(entry))) continue;
      hits.push({ id, label });
      break;
    }
  }

  if (hits.length === 0) {
    return { allowed: true, hits: [], message: "ok" };
  }
  const labels = hits.map((h) => h.label).join(", ");
  return {
    allowed: false,
    hits,
    message: `클라우드 전송 차단: 민감 패턴 (${labels}). 로컬 7B/extractive로 폴백합니다.`,
  };
}
