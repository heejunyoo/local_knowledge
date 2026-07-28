import { describe, it, expect } from "vitest";
import { scan } from "@/lib/redaction";

describe("redaction preflight", () => {
  it("allows plain text with no sensitive patterns", () => {
    const result = scan("오늘 회의는 3시에 시작합니다.");
    expect(result).toEqual({ allowed: true, hits: [], message: "ok" });
  });

  it("blocks an AWS access key id", () => {
    const result = scan("key: AKIAABCDEFGHIJKLMNOP");
    expect(result.allowed).toBe(false);
    expect(result.hits).toEqual([{ id: "aws_access_key", label: "AWS access key id" }]);
  });

  it("blocks a PEM private key header", () => {
    const result = scan("-----BEGIN RSA PRIVATE KEY-----\nMIIEow...");
    expect(result.hits.map((h) => h.id)).toContain("private_key_pem");
  });

  it("blocks a bearer token case-insensitively (ported (?i) inline flag)", () => {
    const result = scan("Authorization: BEARER abc123.def-456_ghi=");
    expect(result.hits.map((h) => h.id)).toContain("bearer_token");
  });

  it("blocks a card-like digit run", () => {
    const result = scan("card 4111 1111 1111 1111 exp 12/29");
    expect(result.hits.map((h) => h.id)).toContain("pan_like");
  });

  it("dedupes multiple hits of the same pattern into one entry", () => {
    const result = scan("AKIAABCDEFGHIJKLMNOP and again AKIAZZZZZZZZZZZZZZZZ");
    const awsHits = result.hits.filter((h) => h.id === "aws_access_key");
    expect(awsHits).toHaveLength(1);
  });

  it("reports multiple distinct pattern types together", () => {
    const result = scan("AKIAABCDEFGHIJKLMNOP\n-----BEGIN EC PRIVATE KEY-----");
    expect(result.hits.map((h) => h.id).sort()).toEqual(["aws_access_key", "private_key_pem"]);
    expect(result.message).toContain("AWS access key id");
    expect(result.message).toContain("PEM private key");
  });
});
