import { describe, it, expect } from "vitest";
import { health_sync_status } from "@/lib/rpc/handlers";

describe("health_sync_status", () => {
  it("원본 Swift와 동일한 고정값을 반환한다 (상태와 무관, 골든과 diff 0)", async () => {
    await expect(health_sync_status()).resolves.toEqual({
      ok: true,
      mirror: "diet",
      pull_mode: "app_open",
      mac_healthkit: false,
    });
  });
});
