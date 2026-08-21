-- diet_metric에 활동 지표 컬럼 2개를 추가한다.
--
-- 하루 등급(A~E) 산정에 걸음 수·활동 에너지가 필요하다. HealthKit/Shortcuts
-- 연동으로 채워질 값이며, 컬럼 추가 전에는 해당 필드가 존재하지 않는다.
--
-- 순서 주의: 이 마이그레이션을 먼저 적용한 뒤에 steps를 select하는 코드를
-- 배포해야 한다. 순서가 바뀌면 컬럼 미존재로 런타임 에러가 난다.
--
-- 기존 행이 있으므로 not null 제약을 걸지 않는다. RLS 정책은 004_rls.sql의
-- owner_all 정책이 테이블 단위로 이미 적용되었으므로 재정의하지 않는다.

alter table today.diet_metric
  add column steps integer,
  add column active_energy_kcal numeric;
