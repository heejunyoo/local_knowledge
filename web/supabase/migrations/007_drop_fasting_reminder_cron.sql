-- ⛔ 새 DB(ingreed 프로젝트의 `today` 스키마)에는 **적용하지 않는다** (2026-08-21).
--
-- 이 파일은 옛 Knowledge 프로젝트에서 일어난 일의 기록이다. 006 이 만든 것을
-- 007 이 전부 되돌렸으므로 둘을 함께 건너뛰면 결과가 같다. 굳이 적용하면
-- ingreed 프로덕션 DB 에 pg_cron·pg_net 과 private 스키마가 새로 심긴다 —
-- 쓰지 않는 확장을 남의 서비스 DB 에 심는 셈이라 하지 않는다.
-- 적용 대상 목록은 이 디렉토리의 README.md 에 있다.
--
-- 006_fasting_reminder_cron.sql 되돌리기.
--
-- 2026-07-29 오너 결정: 단식 리마인더의 이메일 채널(Resend)을 전면 폐기하고
-- "앱 내 표시"로 대체한다. 근거는 리마인더 문구가 이미 도메인 계층에 있었다는
-- 점이다 — diet-read.ts의 fastingStatus()가 goal_met을 계산해 label("목표 14h
-- 달성 · 공복 14.2h")과 hint("목표 공복을 채웠어요")를 만들고, /diet 화면이 그
-- 둘을 이미 렌더링하고 있었다. 이메일이 담당하던 몫은 "앱을 열지 않아도 알려주는"
-- 푸시 성격뿐이었고, 그걸 위해 외부 서비스(Resend) 계정·API 키·5분 주기 pg_cron·
-- pg_net 아웃바운드 호출을 유지할 가치가 없다고 판단했다.
--
-- 006은 히스토리로 남긴다(적용 사실 자체가 기록이므로 삭제하지 않는다).

-- 잡이 이미 없어도 실패하지 않도록 방어적으로 해제한다.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'fasting-reminder') then
    perform cron.unschedule('fasting-reminder');
  end if;
end;
$$;

drop function if exists private.trigger_fasting_reminder();

-- 이 두 시크릿은 위 함수의 pg_net 호출 전용이었다. Vercel 환경변수 CRON_SECRET은
-- /api/cron/keepalive(Vercel cron)가 계속 쓰므로 그대로 둔다 — 여기서 지우는 것은
-- Vault에 복제해 둔 사본뿐이다.
delete from vault.secrets where name in ('fasting_reminder_target_url', 'cron_secret');

-- private 스키마와 pg_net 확장은 남긴다. 비어 있어도 해가 없고, 나중에 다른 내부
-- 함수를 둘 자리로 재사용할 수 있다. 확장을 되돌리는 쪽이 오히려 위험하다.
