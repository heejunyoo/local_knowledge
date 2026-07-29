import { type NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Supabase Auth defaults to the PKCE flow: signInWithOtp() stores a code
// verifier cookie in the browser, and the magic link redirects back here
// with a one-time `code` that must be exchanged (server-side, so the
// resulting session cookie is visible to proxy.ts on the next request).
//
// Google OAuth (signInWithOAuth) lands here through the exact same flow, so
// this route needs no provider-specific branch — only the failure message is
// worded generically.
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const next = searchParams.get("next") ?? "/";

  const redirectTo = request.nextUrl.clone();
  redirectTo.pathname = next;
  redirectTo.searchParams.delete("code");
  redirectTo.searchParams.delete("next");

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return NextResponse.redirect(redirectTo);
    }
  }

  redirectTo.pathname = "/login";
  redirectTo.searchParams.set("error", "auth_failed");
  return NextResponse.redirect(redirectTo);
}
