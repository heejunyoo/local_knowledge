import { describe, it, expect, vi, beforeEach } from "vitest";

const getClaims = vi.fn();
const maybeSingle = vi.fn();
const eq = vi.fn(() => ({ maybeSingle }));
const select = vi.fn(() => ({ eq }));
const upsert = vi.fn(async () => ({ error: null }));
const from = vi.fn(() => ({ select, upsert }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getClaims },
    from,
  })),
}));

const { getSetting, setSetting } = await import("@/lib/settings");

beforeEach(() => {
  vi.clearAllMocks();
  getClaims.mockResolvedValue({ data: { claims: { sub: "owner-1" } } });
});

describe("settings P-1 cache", () => {
  it("serves repeated reads from cache without hitting the DB twice", async () => {
    maybeSingle.mockResolvedValue({ data: { value: "tsvector" }, error: null });

    const first = await getSetting<string>("cache-hit-key");
    const second = await getSetting<string>("cache-hit-key");

    expect(first).toBe("tsvector");
    expect(second).toBe("tsvector");
    expect(maybeSingle).toHaveBeenCalledTimes(1);
  });

  it("bypasses the cache when refresh:true is passed", async () => {
    maybeSingle.mockResolvedValue({ data: { value: "v1" }, error: null });
    await getSetting<string>("refresh-key");

    maybeSingle.mockResolvedValue({ data: { value: "v2" }, error: null });
    const refreshed = await getSetting<string>("refresh-key", { refresh: true });

    expect(refreshed).toBe("v2");
    expect(maybeSingle).toHaveBeenCalledTimes(2);
  });

  it("returns null when no row exists", async () => {
    maybeSingle.mockResolvedValue({ data: null, error: null });
    const value = await getSetting("missing-key");
    expect(value).toBeNull();
  });

  it("setSetting writes through and updates the cache immediately", async () => {
    await setSetting("write-key", { dismissed: true });
    expect(upsert).toHaveBeenCalledWith(
      expect.objectContaining({ owner_id: "owner-1", key: "write-key", value: { dismissed: true } }),
    );

    const cached = await getSetting<{ dismissed: boolean }>("write-key");
    expect(cached).toEqual({ dismissed: true });
    // getSetting must not have queried the DB — the value came from the
    // cache entry setSetting populated, not from `select`.
    expect(maybeSingle).not.toHaveBeenCalled();
  });
});
