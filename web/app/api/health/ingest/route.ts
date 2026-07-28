import { NextRequest, NextResponse } from "next/server";
import { isIngestAuthorized } from "@/lib/ingest-auth";
import { ingestHealthSamples, type IngestSample } from "@/lib/health-ingest";

// 이 경로는 proxy.ts에서 세션 검사 대상 제외로 지정돼 있으므로(PUBLIC_PATH_PREFIXES)
// 여기서 직접 검증해야 한다. Shortcuts(iOS)가 INGEST_API_TOKEN Bearer로 호출한다.
export async function POST(request: NextRequest) {
  if (!isIngestAuthorized(request.headers.get("authorization"))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid json body" }, { status: 400 });
  }
  const samples = Array.isArray((body as { samples?: unknown })?.samples)
    ? ((body as { samples: unknown[] }).samples as IngestSample[])
    : [];

  const result = await ingestHealthSamples(samples);
  return NextResponse.json(result);
}
