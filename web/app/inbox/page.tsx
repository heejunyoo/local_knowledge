"use client";

import { useEffect, useState } from "react";
import { callRpc } from "@/lib/rpc/client";
import { Card, EmptyState } from "@/components/ui";
import styles from "./page.module.css";

interface InboxItem {
  id: string;
  ts: string;
  text: string;
  status: "open" | "promoting" | "promoted" | "promote_failed";
  promoted_path?: string;
}

const STATUS_LABEL: Record<InboxItem["status"], string> = {
  open: "확인 대기",
  promoting: "저장 중…",
  promoted: "저장됨",
  promote_failed: "저장 실패",
};

export default function InboxPage() {
  const [items, setItems] = useState<InboxItem[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [newText, setNewText] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);

  async function refresh() {
    const result = await callRpc<{ items: InboxItem[] }>("inbox.list", { include_promoted: true });
    setItems(result.items);
    setLoaded(true);
  }

  useEffect(() => {
    refresh();
  }, []);

  async function addItem() {
    const text = newText.trim();
    if (!text) return;
    setNewText("");
    await callRpc("inbox.create", { text });
    await refresh();
  }

  async function promote(id: string) {
    setBusyId(id);
    try {
      await callRpc("inbox.promote", { id });
      await refresh();
    } finally {
      setBusyId(null);
    }
  }

  const open = items.filter((i) => i.status === "open" || i.status === "promoting" || i.status === "promote_failed");
  const promoted = items.filter((i) => i.status === "promoted");

  return (
    <div>
      <h1 className={styles.title}>{open.length > 0 ? "확인이 필요해요" : "확인함"}</h1>
      <p className={styles.subtitle}>
        {open.length > 0 ? "메모를 읽은 뒤 승격하면 지식 저장소(vault)에 남아요." : "저장한 메모를 다시 볼 수 있어요."}
      </p>

      <div className={styles.addRow}>
        <input
          className={styles.addInput}
          placeholder="메모를 남겨 보세요"
          value={newText}
          onChange={(e) => setNewText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") addItem();
          }}
        />
        <button type="button" className={styles.addButton} disabled={!newText.trim()} onClick={addItem}>
          추가
        </button>
      </div>

      {loaded && items.length === 0 ? (
        <EmptyState icon="📥" title="확인할 일이 없어요" message="위에서 메모를 남기면 여기로 모여요." />
      ) : null}

      {open.length > 0 ? (
        <div className={styles.section}>
          <p className={styles.sectionLabel}>저장 전 확인</p>
          <Card padded={false}>
            {open.map((item) => (
              <div key={item.id} className={styles.itemCard}>
                <span style={{ flex: 1, minWidth: 0 }}>
                  <p className={styles.itemText}>{item.text}</p>
                  <p className={styles.itemMeta}>{STATUS_LABEL[item.status]}</p>
                </span>
                <button
                  type="button"
                  className={`${styles.itemAction} ${item.status === "promote_failed" ? styles.retry : styles.promote}`}
                  disabled={busyId === item.id || item.status === "promoting"}
                  onClick={() => promote(item.id)}
                >
                  {item.status === "promote_failed" ? "다시 시도" : "승격"}
                </button>
              </div>
            ))}
          </Card>
        </div>
      ) : null}

      {promoted.length > 0 ? (
        <div className={styles.section}>
          <p className={styles.sectionLabel}>저장됨</p>
          <Card padded={false}>
            {promoted.map((item) => (
              <div key={item.id} className={styles.itemCard}>
                <span style={{ flex: 1, minWidth: 0 }}>
                  <p className={styles.itemText}>{item.text}</p>
                  <p className={styles.itemMeta}>{STATUS_LABEL[item.status]}</p>
                </span>
              </div>
            ))}
          </Card>
        </div>
      ) : null}
    </div>
  );
}
