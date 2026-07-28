"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { callRpc } from "@/lib/rpc/client";
import { createClient } from "@/lib/supabase/client";
import styles from "./page.module.css";

export function SyncButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function runSync() {
    setBusy(true);
    setMessage(null);
    try {
      await callRpc("corpus.sync", {});
      await callRpc("search.reindex", {});
      setMessage("동기화했어요");
      router.refresh();
    } catch (e) {
      setMessage(`실패: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <button type="button" className={styles.actionButton} disabled={busy} onClick={runSync}>
        {busy ? "동기화하는 중…" : "지금 동기화"}
      </button>
      {message ? <p className={styles.hint}>{message}</p> : null}
    </>
  );
}

export function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function signOut() {
    setBusy(true);
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <button type="button" className={styles.signOutButton} disabled={busy} onClick={signOut}>
      {busy ? "로그아웃하는 중…" : "로그아웃"}
    </button>
  );
}
