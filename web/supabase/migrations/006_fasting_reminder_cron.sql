-- ⛔ 새 DB(ingreed 프로젝트의 `today` 스키마)에는 **적용하지 않는다** (2026-08-21).
--
-- 이 파일은 옛 Knowledge 프로젝트에서 일어난 일의 기록이다. 006 이 만든 것을
-- 007 이 전부 되돌렸으므로 둘을 함께 건너뛰면 결과가 같다. 굳이 적용하면
-- ingreed 프로덕션 DB 에 pg_cron·pg_net 과 private 스키마가 새로 심긴다 —
-- 쓰지 않는 확장을 남의 서비스 DB 에 심는 셈이라 하지 않는다.
-- 적용 대상 목록은 이 디렉토리의 README.md 에 있다.
--
-- G4b-4(단식 리마인더 실제 발화, 2026-07-29 오너 결정: 이메일 채널) 인프라.
-- pg_cron(이미 설치됨, 1.6.4)이 이 함수를 주기 실행해 goal_met 전환을 감지하고
-- Vercel의 순수 발송 라우트(web/app/api/cron/fasting-reminder/route.ts)를
-- pg_net으로 호출한다. 이 함수가 RLS를 우회해 settings를 직접 다루므로
-- SECURITY DEFINER로 만들되, health-ingest.ts에 한정된 SUPABASE_SERVICE_ROLE_KEY
-- 예외를 넓히지 않기 위해 웹 라우트에는 DB 접근 권한을 주지 않는 설계다
-- (docs/ENV_VARS.md의 "이 예외를 다른 파일로 넓히지 말 것" 원칙 준수).

create extension if not exists pg_net;

-- SECURITY DEFINER 함수는 public 스키마에 두면 anon/authenticated에게 기본
-- EXECUTE가 열린다(Supabase 보안 체크리스트) — cron 전용 내부 함수라 비노출
-- 스키마에 둔다.
create schema if not exists private;

-- URL/시크릿은 하드코딩하지 않고 Supabase Vault(vault.decrypted_secrets)에서
-- 읽는다. 이름 규칙: 'fasting_reminder_target_url' / 'cron_secret'.
-- 오너가 아직 Vercel 배포 전이라 Vault 시크릿 등록과 cron.schedule() 잡
-- 등록은 별도 세션(배포 후)으로 이월한다 — 아래 함수/스키마까지만 이번에 적용.
create or replace function private.trigger_fasting_reminder()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := '47e5b22d-a1f1-4266-b4e5-cd2524b0a37f';
  v_email text := 'naheejun87@gmail.com';
  v_prefs jsonb;
  v_active jsonb;
  v_started timestamptz;
  v_target numeric;
  v_elapsed numeric;
  v_url text;
  v_secret text;
begin
  select value into v_prefs
    from public.settings
    where owner_id = v_owner_id and key = 'diet.fasting';
  if v_prefs is null then
    return;
  end if;

  v_active := v_prefs->'active';
  if v_active is null
     or v_active->>'ended_at' is not null
     or v_active->>'reminder_sent_at' is not null then
    return;
  end if;

  v_started := (v_active->>'started_at')::timestamptz;
  v_target := (v_active->>'target_hours')::numeric;
  v_elapsed := extract(epoch from (now() - v_started)) / 3600.0;
  if v_elapsed < v_target then
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'fasting_reminder_target_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_secret is null then
    -- Vault 시크릿 미등록(배포 전) — 조용히 스킵, 에러 아님.
    return;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'to', v_email,
      'target_hours', v_target,
      'elapsed_hours', v_elapsed
    )
  );

  -- pg_net은 비동기라 실제 발송 성공을 기다리지 않고 낙관적으로 기록한다
  -- (net._http_response에서 사후 확인 가능, 실패 시 재시도는 없음 — 리마인더
  -- 1건 UX로는 허용 가능한 수준으로 판단).
  update public.settings
    set value = jsonb_set(v_prefs, '{active,reminder_sent_at}', to_jsonb(now()::text))
    where owner_id = v_owner_id and key = 'diet.fasting';
end;
$$;

revoke all on function private.trigger_fasting_reminder() from public;

-- 배포 후 별도 세션에서 실행할 것(이번엔 적용하지 않음):
--   select vault.create_secret('https://<실제-vercel-도메인>/api/cron/fasting-reminder', 'fasting_reminder_target_url');
--   select vault.create_secret('<CRON_SECRET 값>', 'cron_secret');
--   select cron.schedule('fasting-reminder', '*/5 * * * *', 'select private.trigger_fasting_reminder();');
