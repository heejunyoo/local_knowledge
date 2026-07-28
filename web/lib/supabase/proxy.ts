import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Paths that don't require a browser session: /login itself (would loop
// otherwise), the Shortcuts ingestion endpoint (authenticated via a bearer
// token instead, see docs/ENV_VARS.md), and the Vercel cron trigger (its own
// secret header).
const PUBLIC_PATH_PREFIXES = [
  "/login",
  "/auth/callback",
  "/auth/confirm",
  "/api/cron/",
  "/api/health/ingest",
];

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Do not run code between createServerClient and getClaims() — see
  // https://supabase.com/docs/guides/auth/server-side/creating-a-client
  const { data } = await supabase.auth.getClaims();
  const isPublicPath = PUBLIC_PATH_PREFIXES.some((prefix) =>
    request.nextUrl.pathname.startsWith(prefix),
  );

  if (!data?.claims && !isPublicPath) {
    // API routes are called by fetch/curl clients, not browsers following a
    // redirect chain — a 307 to /login would just hand back an HTML page as
    // the "response" to a JSON caller. G4a-5 requires 401 here.
    if (request.nextUrl.pathname.startsWith("/api/")) {
      return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    }

    const url = request.nextUrl.clone();
    // A magic link lands on whatever URL Supabase allows (by default the Site
    // URL root, not the callback route), carrying either a one-time PKCE
    // `code` or a `token_hash`. Hand it to the matching route instead of
    // bouncing it to /login, where the credential would be discarded and the
    // user would just see the form again.
    if (url.searchParams.has("code")) {
      url.pathname = "/auth/callback";
    } else if (url.searchParams.has("token_hash")) {
      url.pathname = "/auth/confirm";
    } else {
      url.pathname = "/login";
    }
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
