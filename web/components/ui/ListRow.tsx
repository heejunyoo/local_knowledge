import type { ReactNode } from "react";
import styles from "./ListRow.module.css";

export function ListRow({
  icon,
  title,
  subtitle,
  trailing,
  onClick,
}: {
  icon: ReactNode;
  title: string;
  subtitle?: string;
  trailing?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      className={styles.row}
      onClick={onClick}
      aria-label={subtitle ? `${title}, ${subtitle}` : title}
    >
      <span className={styles.icon} aria-hidden="true">
        {icon}
      </span>
      <span className={styles.texts}>
        <span className={styles.title}>{title}</span>
        {subtitle ? <span className={styles.subtitle}>{subtitle}</span> : null}
      </span>
      {trailing ? <span className={styles.trailing}>{trailing}</span> : null}
      <span className={styles.chevron} aria-hidden="true">
        ›
      </span>
    </button>
  );
}
