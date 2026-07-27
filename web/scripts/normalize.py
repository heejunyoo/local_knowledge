#!/usr/bin/env python3
"""Golden snapshot normalizer — see web/tests/golden/NORMALIZE.md for the rules.

Reads a JSON-RPC response body from stdin, normalizes volatile fields, and
writes deterministically key-sorted JSON to stdout.
"""
import json
import re
import sys

ISO_TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$")
UUID_RE = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
DIGIT_RUN_RE = re.compile(r"\d+(\.\d+)?")

# Keys whose value is always time/volatile regardless of shape.
VOLATILE_KEYS = {
    "ts", "date", "updated_at", "created_at", "generated_at", "started_at",
    "ends_at", "starts_at", "heartbeat_at", "hours_since_last_meal",
}
# Keys whose *string* value contains an embedded relative-time phrase
# ("오늘 오후 1:51", "내일 오전 3:51", "364.6시간") — digits get redacted,
# the Korean relative words are left as-is (they are the thing we want to
# regress on: does the phrasing change, not the clock value).
RELATIVE_TEXT_KEYS = {
    "starts_at_label", "ends_at_label", "detail_line", "preview_line",
    "hint", "summary", "summary_text", "lines",
}


def normalize(value, key=None):
    if isinstance(value, dict):
        return {k: normalize(v, key=k) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v, key=key) for v in value]
    if isinstance(value, str):
        if key in VOLATILE_KEYS or ISO_TS_RE.match(value):
            return "<TS>"
        value = UUID_RE.sub("<UUID>", value)
        if key in RELATIVE_TEXT_KEYS:
            value = DIGIT_RUN_RE.sub("<N>", value)
        return value
    if isinstance(value, float):
        if key in VOLATILE_KEYS:
            return "<N>"
        return round(value, 2)
    return value


def main():
    raw = sys.stdin.read()
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"normalize.py: invalid JSON: {e}\nraw={raw[:500]!r}\n")
        sys.exit(1)
    normalized = normalize(obj)
    json.dump(normalized, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
