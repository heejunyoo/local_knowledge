// Swift 원본: LocalLLM.ragPrompt(question:contexts:) 1:1.
export interface RagContext {
  title: string;
  snippet: string;
}

export function ragPrompt(question: string, contexts: RagContext[]): string {
  let ctx = "";
  contexts.forEach((c, i) => {
    ctx += `[${i + 1}] ${c.title}\n${c.snippet}\n\n`;
  });
  return `당신은 개인 지식 비서입니다. 아래 근거만 사용해 한국어로 짧게 답하세요.
근거에 없으면 "모은 지식에서 찾지 못했어요"라고 말하세요.
추측하지 마세요. 2~5문장. 불릿이 필요하면 · 사용.

### 근거
${ctx}
### 질문
${question}

### 답변
`;
}
