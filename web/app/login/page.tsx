"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { PrimaryButton } from "@/components/ui";
import styles from "./page.module.css";

// 구글 브랜드 마크. 외부 요청 없이 인라인 SVG로 둔다(오프라인 셸 서비스워커·CSP
// 양쪽 모두와 무관해진다).
function GoogleMark() {
  return (
    <svg className={styles.googleMark} viewBox="0 0 18 18" aria-hidden="true" focusable="false">
      <path
        fill="#4285F4"
        d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z"
      />
      <path
        fill="#34A853"
        d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.81.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18z"
      />
      <path
        fill="#FBBC05"
        d="M3.97 10.72a5.4 5.4 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33z"
      />
      <path
        fill="#EA4335"
        d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58C13.46.89 11.43 0 9 0A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58z"
      />
    </svg>
  );
}

const ERROR_MESSAGES: Record<string, string> = {
  auth_failed: "로그인 링크가 만료되었거나 이미 사용되었습니다. 다시 시도해 주세요.",
  // P3부터 쓰던 값 — 이전에 발급된 링크가 아직 돌아다닐 수 있어 함께 받는다.
  magic_link_invalid: "로그인 링크가 만료되었거나 이미 사용되었습니다. 다시 시도해 주세요.",
};

/** Supabase가 돌려주는 영문 메시지 중 실제로 마주치는 것만 한국어로 바꾼다. */
function localizeAuthError(message: string): string {
  if (message.includes("Invalid login credentials")) {
    return "이메일 또는 비밀번호가 올바르지 않습니다.";
  }
  if (message.includes("Email logins are disabled")) {
    return "비밀번호 로그인이 꺼져 있습니다. 아래 '메일로 로그인 링크 받기'를 쓰세요.";
  }
  return message;
}

type Status = "idle" | "password" | "google" | "sending" | "sent" | "error";

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showAlternatives, setShowAlternatives] = useState(false);
  const [status, setStatus] = useState<Status>("idle");
  const [errorMessage, setErrorMessage] = useState("");

  const callbackError = searchParams.get("error");
  const shownError =
    errorMessage || (callbackError ? (ERROR_MESSAGES[callbackError] ?? "로그인에 실패했습니다.") : "");

  /** 기본 경로 — 이메일 왕복이 없다. 브라우저가 자격증명을 저장하면 사실상 1탭. */
  async function signInWithPassword(event: React.FormEvent) {
    event.preventDefault();
    setStatus("password");
    setErrorMessage("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      setStatus("error");
      setErrorMessage(localizeAuthError(error.message));
      return;
    }
    // 세션 쿠키는 @supabase/ssr이 심는다. 서버 컴포넌트가 새 세션을 보도록
    // refresh까지 해야 홈이 로그인 화면으로 되튕기지 않는다.
    router.push("/");
    router.refresh();
  }

  async function signInWithGoogle() {
    setStatus("google");
    setErrorMessage("");

    const supabase = createClient();
    // OAuth도 매직링크와 같은 PKCE 흐름이라 콜백은 기존 /auth/callback을 그대로
    // 쓴다(one-time `code`를 서버에서 교환).
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
    }
    // 성공하면 구글로 리다이렉트되므로 여기서 상태를 되돌릴 필요가 없다.
  }

  /** 보조 경로 — 비밀번호를 아직 안 정했거나 잊었을 때의 복구용. */
  async function sendMagicLink() {
    if (!email) {
      setStatus("error");
      setErrorMessage("이메일을 먼저 입력해 주세요.");
      return;
    }
    setStatus("sending");
    setErrorMessage("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
    });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
      return;
    }
    setStatus("sent");
  }

  if (status === "sent") {
    return (
      <div className={styles.wrap}>
        <div className={styles.panel}>
          <p className={styles.sentTitle}>메일을 보냈습니다</p>
          <p className={styles.note}>
            {email}(으)로 로그인 링크를 보냈습니다. 메일함을 확인하세요.
            <br />
            로그인한 뒤 설정 → 계정에서 비밀번호를 정해두면 다음부터는 메일이 필요 없어요.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.wrap}>
      <div className={styles.panel}>
        <h1 className={styles.brand}>Knowledge</h1>
        <p className={styles.tagline}>메모·검색·식단을 한 곳에서</p>

        <form className={styles.form} onSubmit={signInWithPassword}>
          <label className={styles.label} htmlFor="email">
            이메일
          </label>
          <input
            id="email"
            name="email"
            className={styles.input}
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />

          <label className={styles.label} htmlFor="password">
            비밀번호
          </label>
          <input
            id="password"
            name="password"
            className={styles.input}
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />

          <PrimaryButton type="submit" disabled={status === "password"}>
            {status === "password" ? "로그인 중..." : "로그인"}
          </PrimaryButton>
        </form>

        {shownError ? (
          <p className={styles.error} role="alert">
            {shownError}
          </p>
        ) : null}

        {showAlternatives ? (
          <div className={styles.alternatives}>
            <PrimaryButton
              className={styles.googleButton}
              onClick={signInWithGoogle}
              disabled={status === "google"}
            >
              <GoogleMark />
              {status === "google" ? "이동 중..." : "Google로 계속하기"}
            </PrimaryButton>
            <button
              type="button"
              className={styles.linkButton}
              onClick={sendMagicLink}
              disabled={status === "sending"}
            >
              {status === "sending" ? "전송 중..." : "메일로 로그인 링크 받기"}
            </button>
            <p className={styles.note}>
              비밀번호를 아직 정하지 않았다면 링크로 한 번 들어와 설정 → 계정에서 정하세요.
            </p>
          </div>
        ) : (
          <button
            type="button"
            className={styles.linkButton}
            onClick={() => setShowAlternatives(true)}
          >
            다른 방법으로 로그인
          </button>
        )}

        <p className={styles.note}>
          이 서비스는 오너 한 사람만 사용합니다. 신규 가입은 막혀 있어요.
        </p>
      </div>
    </div>
  );
}

// useSearchParams는 정적 렌더링 중 Suspense 경계를 요구한다.
export default function LoginPage() {
  return (
    <Suspense fallback={null}>
      <LoginForm />
    </Suspense>
  );
}
