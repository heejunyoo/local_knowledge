import { corpus_status } from "@/lib/rpc/handlers";
import { getSearchMode } from "@/lib/db/search";
import { Card } from "@/components/ui";
import { SyncButton, SignOutButton, PasswordForm } from "./SettingsActions";
import styles from "./page.module.css";

interface CorpusStatus {
  total_units: number;
  meetings: number;
  notes: number;
  obsidian: number;
  files: number;
  sources: { id: string; source_type: string; label: string; last_sync_at: string | null; last_error: string | null; unit_count: number }[];
}

const SEARCH_MODE_LABEL: Record<string, string> = {
  tsvector: "tsvector (기본)",
  trgm: "trigram",
  hybrid: "hybrid",
};

export default async function SettingsPage() {
  const [status, searchMode] = await Promise.all([
    corpus_status() as Promise<CorpusStatus>,
    getSearchMode(),
  ]);

  return (
    <div>
      <h1 className={styles.title}>설정</h1>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>지식 코퍼스</p>
        <Card>
          <div className={styles.row}>
            <span className={styles.rowLabel}>전체 단위</span>
            <span className={styles.rowValue}>{status.total_units}</span>
          </div>
          <div className={styles.row}>
            <span className={styles.rowLabel}>Obsidian</span>
            <span className={styles.rowValue}>{status.obsidian}</span>
          </div>
          <div className={styles.row}>
            <span className={styles.rowLabel}>노트</span>
            <span className={styles.rowValue}>{status.notes}</span>
          </div>
          <div className={styles.row}>
            <span className={styles.rowLabel}>미팅</span>
            <span className={styles.rowValue}>{status.meetings}</span>
          </div>
          {status.sources.map((s) => (
            <div key={s.id} className={styles.row}>
              <span className={styles.rowLabel}>{s.label}</span>
              <span className={`${styles.rowValue} ${s.last_error ? styles.errorValue : ""}`}>
                {s.last_error ?? `${s.unit_count}건`}
              </span>
            </div>
          ))}
          <SyncButton />
        </Card>
      </div>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>검색</p>
        <Card>
          <div className={styles.row}>
            <span className={styles.rowLabel}>모드</span>
            <span className={styles.rowValue}>{SEARCH_MODE_LABEL[searchMode] ?? searchMode}</span>
          </div>
          <p className={styles.hint}>D-4 결정값 — docs/FTS_COMPARISON_2026-07.md 참고. 여기서는 바꿀 수 없어요.</p>
        </Card>
      </div>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>계정</p>
        <Card>
          <PasswordForm />
        </Card>
        <SignOutButton />
      </div>
    </div>
  );
}
