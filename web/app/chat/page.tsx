"use client";

import { useState, useRef } from "react";
import { callRpc } from "@/lib/rpc/client";
import { ScreenHeader } from "@/components/ui";
import styles from "./page.module.css";

interface ChatSource {
  service: string;
  title: string;
  snippet: string;
  unit_id?: string;
}

interface ChatResult {
  answer: string;
  engine: string;
  sources: ChatSource[];
  trace: string[];
  intent?: string;
}

interface ChatMessage {
  role: "user" | "assistant";
  text: string;
  sources?: ChatSource[];
}

export default function ChatPage() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const requestId = useRef(0);

  async function send() {
    const trimmed = input.trim();
    if (!trimmed || sending) return;
    setInput("");
    setMessages((prev) => [...prev, { role: "user", text: trimmed }]);
    setSending(true);
    const myId = ++requestId.current;
    try {
      const result = await callRpc<ChatResult>("chat.send", { message: trimmed, mode: "auto" });
      if (myId !== requestId.current) return;
      setMessages((prev) => [...prev, { role: "assistant", text: result.answer, sources: result.sources }]);
    } catch {
      if (myId !== requestId.current) return;
      setMessages((prev) => [...prev, { role: "assistant", text: "답변을 가져오지 못했어요. 잠시 후 다시 시도해 주세요." }]);
    } finally {
      if (myId === requestId.current) setSending(false);
    }
  }

  return (
    <div className={styles.page}>
      <ScreenHeader title="채팅" />

      {messages.length === 0 ? (
        <div className={styles.emptyIdle}>
          <p className={styles.emptyTitle}>무엇이든 물어보세요</p>
          <p className={styles.emptyBody}>지식·식단·건강 기록을 넘나들며 답해요.</p>
        </div>
      ) : (
        <div className={styles.messageList}>
          {messages.map((m, i) => (
            <div key={i} className={m.role === "user" ? styles.userBubble : styles.assistantBubble}>
              <p className={styles.messageText}>{m.text}</p>
              {m.sources && m.sources.length > 0 ? (
                <div className={styles.sources}>
                  {m.sources.map((s, j) => (
                    <span key={j} className={styles.sourceChip}>
                      {s.title || s.service}
                    </span>
                  ))}
                </div>
              ) : null}
            </div>
          ))}
          {sending ? <p className={styles.pending}>생각하는 중…</p> : null}
        </div>
      )}

      <div className={styles.inputBar}>
        <input
          className={styles.input}
          type="text"
          placeholder="메시지를 입력하세요"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") send();
          }}
          disabled={sending}
        />
        <button type="button" className={styles.sendButton} onClick={send} disabled={sending || !input.trim()}>
          보내기
        </button>
      </div>
    </div>
  );
}
