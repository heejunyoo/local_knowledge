#!/usr/bin/env bash
# 옛 Knowledge 프로젝트의 pg_dump 백업을 새 DB 의 `today` 스키마로 되살린다.
#
# 옛 프로젝트(gppklwzcmfuuhsefdeik)는 삭제됐다. 남은 것은 heejunyoo/knowledge-backup
# 리포의 주간 덤프뿐이고, 마지막 성공본은 **2026-08-09** 다(8/16 실행은
# `tenant/user not found` 로 실패). 옛 DB 의 마지막 활동이 7/31 이라 8/2 와 8/9
# 덤프는 바이트까지 같다 — 손실은 없다.
#
# ## 이 스크립트가 하는 일
#   ① 덤프에서 `public.*` 데이터 COPY 블록만 뽑아 `today.*` 로 바꿔 넣는다
#   ② state_event 시퀀스를 덤프의 setval 값으로 맞춘다
#   ③ owner_id 를 **새 프로젝트의 owner uuid** 로 일괄 치환한다
#   ④ 테이블별 행수를 기대값과 대조해 **판정**한다 (다르면 exit 1)
#
# ## 왜 owner_id 를 치환하는가 — 여기가 이 복원의 유일한 함정
# 전 테이블의 owner_id 는 옛 프로젝트 auth.users 의 uuid 다. 새 프로젝트에서
# 계정을 만들면 uuid 가 달라지므로, 그대로 넣으면 RLS(`owner_id = auth.uid()`)가
# 전부 걸러 **로그인은 되는데 데이터가 하나도 안 보이는** 상태가 된다.
# auth.users 에 옛 uuid 를 직접 꽂는 방법은 쓰지 않는다 — Supabase 내부 테이블을
# 손으로 건드리는 쪽이 더 위험하다.
#
# 사용법
#   NEW_OWNER_ID=<새 auth.users.id> \
#   SUPABASE_DB_URL='postgresql://...' \
#     web/scripts/restore-into-today.sh /path/to/knowledge-20260809.sql
#
# 선행조건: 000~005·008·009 마이그레이션이 이미 적용돼 today 스키마가 비어 있을 것.
set -euo pipefail

DUMP="${1:?덤프 파일 경로를 인자로 준다 (knowledge-YYYYMMDD.sql)}"
: "${NEW_OWNER_ID:?NEW_OWNER_ID 가 필요하다 — 새 프로젝트 auth.users 의 owner uuid}"
: "${SUPABASE_DB_URL:?SUPABASE_DB_URL 가 필요하다. 파일에 쓰지 않는다}"

[ -f "$DUMP" ] || { echo "덤프가 없다: $DUMP" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DATA="$WORK/data.sql"

# ── ① public 데이터 블록만 추출 ────────────────────────────────────────────
# auth.* / storage.* 는 **가져오지 않는다**. 새 프로젝트의 인증 상태를 덮어쓰는
# 일이고, 어차피 계정은 새로 만든다.
python3 - "$DUMP" "$DATA" <<'PY'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
out, keep = [], False
for line in open(src, encoding='utf-8'):
    m = re.match(r'COPY "public"\."(\w+)" \((.*)\) FROM stdin;', line)
    if m:
        keep = True
        out.append(f'COPY today.{m.group(1)} ({m.group(2)}) FROM stdin;\n')
        continue
    if keep:
        out.append(line)
        if line.startswith('\\.'):
            keep = False
        continue
    m = re.match(r"SELECT pg_catalog\.setval\('\"public\"\.\"(\w+)\"', (\d+), (\w+)\);", line)
    if m:
        out.append(f"SELECT pg_catalog.setval('today.{m.group(1)}', {m.group(2)}, {m.group(3)});\n")
open(dst, 'w', encoding='utf-8').writelines(out)
n = sum(1 for l in out if l.startswith('COPY '))
print(f"  추출: COPY 블록 {n}개")
PY

# ── ②③ 적재 + owner_id 치환 (한 트랜잭션) ────────────────────────────────
# 실패하면 통째로 되돌아간다. 반쯤 들어간 상태를 만들지 않는다.
{
  echo "begin;"
  cat "$DATA"
  for t in settings connected_source knowledge_unit knowledge_chunk note_mirror \
           source_pointer search_doc diet_meal diet_workout diet_metric \
           inbox_item ingest_job state_event llm_answer_cache; do
    echo "update today.$t set owner_id = '$NEW_OWNER_ID';"
  done
  echo "commit;"
} | psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q

# ── ④ 판정 — 8/9 덤프의 실제 행수와 대조한다 ──────────────────────────────
# 이 값들은 덤프를 세어 얻은 것이다. 하나라도 어긋나면 복원이 실패한 것이다.
EXPECTED="knowledge_chunk 590
knowledge_unit 236
search_doc 236
source_pointer 236
state_event 160
ingest_job 53
diet_meal 25
note_mirror 19
settings 9
diet_metric 8
diet_workout 8
connected_source 3
inbox_item 0
llm_answer_cache 0"

fail=0
while read -r tbl want; do
  got=$(psql "$SUPABASE_DB_URL" -At -c "select count(*) from today.$tbl;")
  if [ "$got" != "$want" ]; then
    echo "  ❌ $tbl: $got (기대 $want)"; fail=1
  else
    echo "  ✅ $tbl: $got"
  fi
done <<< "$EXPECTED"

orphan=$(psql "$SUPABASE_DB_URL" -At -c "select count(*) from today.knowledge_unit where owner_id <> '$NEW_OWNER_ID';")
if [ "$orphan" != "0" ]; then
  echo "  ❌ owner_id 치환이 안 된 행 $orphan 개"; fail=1
fi

[ "$fail" -eq 0 ] || { echo "복원 실패 — 위 항목을 보라." >&2; exit 1; }
echo "✅ 복원 완료 · 1,583행(public 데이터 전량) · owner_id=$NEW_OWNER_ID"
