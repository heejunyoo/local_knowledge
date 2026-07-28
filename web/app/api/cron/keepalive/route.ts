import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { isCronAuthorized } from "@/lib/cron";

// 이 경로는 proxy.ts에서 세션 검사 대상 제외로 지정돼 있으므로(PUBLIC_PATH_PREFIXES)
// 여기서 직접 검증해야 한다.
export async function GET(request: NextRequest) {
  if (!isCronAuthorized(request.headers.get("authorization"))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  // 무료 티어 프로젝트의 자동 일시정지(장기 무활동) 방지가 유일한 목적이므로
  // RLS로 결과가 걸러지든 말든 상관없다 — DB 왕복 자체가 활동으로 기록된다.
  // 쿠키 세션이 없는 크론 요청이라 lib/supabase/server.ts(next/headers) 대신
  // anon key로 직접 클라이언트를 만든다.
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
  const { error } = await supabase.from("settings").select("key").limit(1);

  return NextResponse.json({ ok: !error });
}
