"use client";

import { useState, useRef } from "react";
import { callRpc } from "@/lib/rpc/client";
import { ScreenHeader } from "@/components/ui";
import styles from "./page.module.css";

interface SearchHit {
  doc_id: string;
  source_type: string | null;
  title: string | null;
  snippet: string | null;
}

type Status = "idle" | "searching" | "done";

export default function SearchPage() {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<Status>("idle");
  const [hits, setHits] = useState<SearchHit[]>([]);
  const requestId = useRef(0);

  async function runSearch(q: string) {
    const trimmed = q.trim();
    if (!trimmed) {
      setStatus("idle");
      setHits([]);
      return;
    }
    setStatus("searching");
    const myId = ++requestId.current;
    try {
      const result = await callRpc<{ hits: SearchHit[] }>("knowledge.search", { q: trimmed });
      if (myId !== requestId.current) return; // 응답 도착 전에 새 검색이 시작됨
      setHits(result.hits);
      setStatus("done");
    } catch {
      if (myId !== requestId.current) return;
      setHits([]);
      setStatus("done");
    }
  }

  return (
    <div>
      <ScreenHeader title="검색" />
      <div className={styles.searchBar}>
        <span className={styles.searchIcon} aria-hidden="true">
          🔍
        </span>
        <input
          className={styles.input}
          type="search"
          placeholder="검색"
          autoFocus
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") runSearch(query);
          }}
        />
        {status === "searching" ? (
          <span aria-hidden="true">…</span>
        ) : query ? (
          <button
            type="button"
            className={styles.clearButton}
            aria-label="검색어 지우기"
            onClick={() => {
              setQuery("");
              setStatus("idle");
              setHits([]);
            }}
          >
            ✕
          </button>
        ) : null}
      </div>

      {hits.length === 0 ? (
        status === "searching" ? (
          <p className={styles.searching}>찾는 중…</p>
        ) : status === "done" ? (
          <div className={styles.emptyNoResults}>
            <p className={styles.emptyTitle}>결과가 없어요</p>
            <p className={styles.emptyBody}>
              다른 단어로 시도해 보세요. 지식 연결을 다시 동기화하면 새로 추가된 노트가 반영돼요.
            </p>
          </div>
        ) : (
          <div className={styles.emptyIdle}>
            <p className={styles.emptyTitle}>무엇을 찾을까요?</p>
            <p className={styles.emptyBody}>미팅, 메모, 노트 이름을 검색해 보세요.</p>
          </div>
        )
      ) : (
        <div className={styles.hitList}>
          {hits.slice(0, 30).map((hit) => (
            <div key={hit.doc_id} className={styles.hit}>
              <p className={styles.hitTitle}>{hit.title ?? "(제목 없음)"}</p>
              {hit.snippet ? <p className={styles.hitSnippet}>{hit.snippet}</p> : null}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
