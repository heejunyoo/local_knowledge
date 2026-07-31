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

/** 비밀번호 설정·변경. 매직링크 왕복 없이 로그인하려면 한 번은 여기서 정해야 한다. */
export function PasswordForm() {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setMessage(null);

    // Supabase 기본 최소 길이는 6이지만, 이 앱은 개인 데이터 전부를 이 한 겹으로
    // 가리므로 8로 올려 받는다.
    if (password.length < 8) {
      setMessage("8자 이상으로 정해 주세요");
      return;
    }
    if (password !== confirm) {
      setMessage("두 번 입력한 비밀번호가 다릅니다");
      return;
    }

    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.auth.updateUser({ password });
    setBusy(false);

    if (error) {
      setMessage(`실패: ${error.message}`);
      return;
    }
    setPassword("");
    setConfirm("");
    setMessage("비밀번호를 저장했어요. 다음부터 이메일+비밀번호로 바로 로그인됩니다.");
  }

  return (
    <form className={styles.passwordForm} onSubmit={save}>
      <label className={styles.passwordLabel} htmlFor="new-password">
        새 비밀번호
      </label>
      <input
        id="new-password"
        className={styles.passwordInput}
        type="password"
        autoComplete="new-password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
      />
      <label className={styles.passwordLabel} htmlFor="confirm-password">
        한 번 더
      </label>
      <input
        id="confirm-password"
        className={styles.passwordInput}
        type="password"
        autoComplete="new-password"
        value={confirm}
        onChange={(e) => setConfirm(e.target.value)}
      />
      <button type="submit" className={styles.actionButton} disabled={busy}>
        {busy ? "저장하는 중…" : "비밀번호 저장"}
      </button>
      {message ? <p className={styles.hint}>{message}</p> : null}
    </form>
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
