import Link from "next/link";
import { assistant_today, day_grade } from "@/lib/rpc/handlers";
import { Card, ListRow, Badge } from "@/components/ui";
import styles from "./page.module.css";

interface AssistantToday {
  body: {
    line: string;
    suggest: { title: string; subtitle: string };
    streak_days: number;
    sleep_hint?: string;
  };
  knowledge: { line: string; inbox_open: number };
  gaps: { label: string; slot?: string }[];
  next_actions: { kind: string; label: string; subtitle?: string; slot?: string }[];
}

interface DayGradeAxis {
  id: string;
  state: string;
  score?: number;
  reason: string;
}

interface DayGradeResult {
  grade: string | null;
  score: number | null;
  ratable: boolean;
  confidence: number;
  breakdown: DayGradeAxis[];
}

const ACTION_HREF: Record<string, string> = {
  gap: "/diet",
  diet_suggest: "/diet",
  inbox: "/inbox",
};

const AXIS_LABEL: Record<string, string> = {
  recovery: "회복",
  activity: "활동",
  intake: "섭취",
};

// confidence 는 3축(회복·활동·섭취) 중 실제로 아는 축의 비중이라 0, 0.33, 0.67, 1
// 넷 중 하나다. 절반 미만(0·0.33)만 알면 "추정치"로 표시한다.
const LOW_CONFIDENCE = 0.5;

export default async function HubPage() {
  const [today, grade] = await Promise.all([
    assistant_today() as unknown as Promise<AssistantToday>,
    day_grade({}) as unknown as Promise<DayGradeResult>,
  ]);
  const primaryAction = today.next_actions[0];
  const primaryHref = primaryAction ? (ACTION_HREF[primaryAction.kind] ?? "/diet") : "/diet";

  return (
    <div>
      <div className={styles.greeting}>
        <h1 className={styles.greetingTitle}>
          {today.knowledge.inbox_open > 0 ? "확인할 게 있어요" : "오늘의 나"}
        </h1>
        <p className={styles.greetingBody}>몸·지식·다음 할 일을 한곳에서 이어가요.</p>
      </div>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>오늘의 등급</p>
        <Card>
          <div className={styles.gradeHead}>
            {grade.grade !== null ? (
              <>
                <span className={styles.gradeLetter}>{grade.grade}</span>
                {grade.score !== null ? <span className={styles.gradeScore}>{Math.round(grade.score)}점</span> : null}
              </>
            ) : (
              <span className={styles.gradePending}>아직 진행 중</span>
            )}
            {grade.confidence < LOW_CONFIDENCE ? <Badge kind="neutral">추정치예요</Badge> : null}
            {grade.grade !== null && !grade.ratable ? (
              <Badge kind="neutral">다른 날과 비교할 수 없어요</Badge>
            ) : null}
          </div>

          {/* 빠진 기록 목록은 여기 두지 않는다. 아래 "빠진 기록" 섹션이 같은 today.gaps 를
              /diet 링크와 함께 이미 보여주고, 무엇이 비었는지는 바로 아래 축별 reason
              ("식사 기록 없음")이 말한다 — 한 화면에 같은 목록을 두 번 두지 않는다. */}

          <div className={styles.gradeAxisList}>
            {grade.breakdown.map((axis) => (
              <div key={axis.id} className={styles.gradeAxisRow}>
                <span className={styles.gradeAxisLabel}>{AXIS_LABEL[axis.id] ?? axis.id}</span>
                <span className={styles.gradeAxisReason}>{axis.reason}</span>
                {axis.score != null ? <span className={styles.gradeAxisScore}>{Math.round(axis.score)}</span> : null}
              </div>
            ))}
          </div>
        </Card>
      </div>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>오늘</p>
        <Card>
          <div className={styles.briefingLine}>
            <span className={styles.briefingLabel}>몸</span>
            <span className={styles.briefingText}>
              {today.body.line || "아직 오늘 식단·운동 기록이 없어요"}
            </span>
          </div>
          {today.body.streak_days > 0 ? (
            <p className={styles.streak}>연속 {today.body.streak_days}일</p>
          ) : null}
          {today.body.sleep_hint ? <p className={styles.briefingSub}>{today.body.sleep_hint}</p> : null}

          <div className={styles.divider} />
          <div className={styles.briefingLine}>
            <span className={styles.briefingLabel}>지식</span>
            <span className={styles.briefingText}>{today.knowledge.line}</span>
          </div>

          <div className={styles.divider} />
          <div className={styles.briefingLine}>
            <span className={styles.briefingLabel}>다음</span>
            <span className={styles.briefingText}>{today.body.suggest.title || "식단을 남겨 보세요"}</span>
          </div>
          {today.body.suggest.subtitle ? (
            <p className={styles.briefingSub}>{today.body.suggest.subtitle}</p>
          ) : null}
        </Card>
      </div>

      {today.gaps.length > 0 ? (
        <div className={styles.section}>
          <p className={styles.sectionLabel}>빠진 기록</p>
          <Card>
            {today.gaps.slice(0, 5).map((gap, i) => (
              <Link key={i} href="/diet" className={styles.gapRow}>
                {gap.label}
              </Link>
            ))}
          </Card>
        </div>
      ) : null}

      {primaryAction ? (
        <div className={styles.section}>
          <Link href={primaryHref} className={styles.primaryLinkButton}>
            {primaryAction.label}
          </Link>
        </div>
      ) : null}

      <div className={styles.section}>
        <p className={styles.sectionLabel}>바로가기</p>
        <Card padded={false}>
          <div className={styles.menuList}>
            <ListRow
              href="/inbox"
              icon="📥"
              title="확인함"
              subtitle={today.knowledge.inbox_open > 0 ? "저장 전 살펴보기" : "비어 있어요"}
              trailing={today.knowledge.inbox_open > 0 ? String(today.knowledge.inbox_open) : undefined}
            />
            <ListRow href="/search" icon="🔍" title="검색" subtitle="지식 찾아보기" />
            <ListRow href="/diet" icon="🍽️" title="식단" subtitle="오늘 기록·목표" />
            <ListRow href="/settings" icon="⚙️" title="설정" subtitle="코퍼스·계정" />
          </div>
        </Card>
      </div>
    </div>
  );
}
