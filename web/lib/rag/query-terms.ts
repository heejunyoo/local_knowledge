// Swift 원본: LocalRetrieve.swift 내 `enum QueryTerms` 1:1 포트.
// 한국어/영어 PKM 질의 토큰화+확장 — synthesize()의 looksLikeDirectAnswer()가 사용.
const STOP_WORDS = new Set([
  "은", "는", "이", "가", "을", "를", "의", "에", "와", "과", "도", "로", "으로",
  "뭐", "무엇", "어디", "언제", "how", "what", "the", "a",
]);

const TOKEN_SPLIT_RE = /[\s?,.!;:"'()[\]【】「」]+/u;

function isHangul(s: string): boolean {
  return /[가-힣]/.test(s);
}

export function tokens(q: string): string[] {
  return q
    .split(TOKEN_SPLIT_RE)
    .map((s) => s.trim())
    .filter((s) => s.length >= 2);
}

export function expand(query: string): string[] {
  const terms = tokens(query);
  const compact = query.replace(/\s+/g, "");
  const chars = Array.from(compact);

  for (let i = 0; i < chars.length - 1; i++) {
    const bi = chars[i] + chars[i + 1];
    if (isHangul(bi)) terms.push(bi);
  }
  for (let i = 0; i < chars.length - 2; i++) {
    const tri = chars[i] + chars[i + 1] + chars[i + 2];
    if (isHangul(tri)) terms.push(tri);
  }

  const filtered = terms.filter((t) => t.length >= 2 && !STOP_WORDS.has(t.toLowerCase()));
  return Array.from(new Set(filtered)).sort();
}
