// 브라우저(클라이언트 컴포넌트)에서 /api/rpc를 호출하는 헬퍼.
// app/api/rpc/route.ts의 JSON-RPC 봉투({jsonrpc,id,result|error})를 벗겨
// result만 반환하고, error면 throw한다.

let nextId = 1;

export class RpcError extends Error {
  code: number;
  constructor(code: number, message: string) {
    super(message);
    this.code = code;
    this.name = "RpcError";
  }
}

export async function callRpc<T = unknown>(method: string, params?: unknown): Promise<T> {
  const res = await fetch("/api/rpc", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ id: nextId++, method, params }),
  });

  if (res.status === 401) {
    throw new RpcError(401, "인증이 필요합니다");
  }

  const body = (await res.json()) as {
    result?: T;
    error?: { code: number; message: string };
  };

  if (body.error) {
    throw new RpcError(body.error.code, body.error.message);
  }
  return body.result as T;
}
