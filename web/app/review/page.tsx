import { assistant_week_review, day_grade } from "@/lib/rpc/handlers";
import { Card } from "@/components/ui";
import styles from "./page.module.css";

interface WeekReviewDay {
  date: string;
  kcal: number;
  protein_g: number;
  workout_minutes: number;
  meals: number;
  workouts: number;
}

interface WeekReviewResult {
  from: string;
  to: string;
  days: WeekReviewDay[];
  narrative_lines: string[];
}

interface DayGradeResult {
  date: string;
  grade: string | null;
  ratable: boolean;
}

// 돌아보기 — 과거의 날들·추세. 얇게: assistant.week_review 를 그대로 재사용하고
// 하루짜리 day.grade 를 날짜별로 호출해 ratable=false 인 날(진행 중인 오늘 포함)을
// 추세에서 뺀다. 채점 로직 자체는 새로 만들지 않는다.
export default async function ReviewPage() {
  const week = (await assistant_week_review()) as unknown as WeekReviewResult;
  const grades = await Promise.all(
    week.days.map((d) => day_grade({ date: d.date }) as Promise<DayGradeResult>),
  );
  const gradeByDate = new Map(grades.map((g) => [g.date, g]));
  const trendDays = week.days.filter((d) => gradeByDate.get(d.date)?.ratable);

  return (
    <div>
      <h1 className={styles.title}>돌아보기</h1>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>지난 한 주</p>
        <Card>
          {week.narrative_lines.map((line, i) => (
            <p key={i} className={styles.narrativeLine}>
              {line}
            </p>
          ))}
        </Card>
      </div>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>추세</p>
        <Card>
          {trendDays.length === 0 ? (
            <p className={styles.emptyHint}>등급을 매길 수 있는 날이 아직 없어요</p>
          ) : (
            trendDays.map((d) => {
              const g = gradeByDate.get(d.date);
              return (
                <div key={d.date} className={styles.row}>
                  <span className={styles.rowLabel}>{d.date}</span>
                  <span className={styles.rowMeta}>
                    {Math.round(d.kcal)} kcal · 단백질 {Math.round(d.protein_g)}g · 운동 {d.workout_minutes}분
                  </span>
                  <span className={styles.rowGrade}>{g?.grade ?? "·"}</span>
                </div>
              );
            })
          )}
        </Card>
      </div>
    </div>
  );
}
