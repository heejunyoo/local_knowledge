import Link from "next/link";
import { assistant_today } from "@/lib/rpc/handlers";
import { Card, ListRow } from "@/components/ui";
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

const ACTION_HREF: Record<string, string> = {
  gap: "/diet",
  diet_suggest: "/diet",
  inbox: "/inbox",
};

export default async function HubPage() {
  const today = (await assistant_today()) as unknown as AssistantToday;
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
