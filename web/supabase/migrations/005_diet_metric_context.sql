-- P4b 착수 전 발견: diet_metric에 context 컬럼이 없어 Swift 원본의
-- weightForPlanLocked()(체중 소스 우선순위) / isHealthKitMetric() 판정을
-- 1:1로 재현할 수 없었다. 001_init.sql이 놓친 컬럼을 추가한다.
alter table today.diet_metric add column context text;
