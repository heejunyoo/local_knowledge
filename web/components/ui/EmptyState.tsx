import type { ReactNode } from "react";
import styles from "./EmptyState.module.css";

export function EmptyState({
  icon,
  title,
  message,
  actionTitle,
  onAction,
}: {
  icon: ReactNode;
  title: string;
  message: string;
  actionTitle?: string;
  onAction?: () => void;
}) {
  return (
    <div className={styles.wrap}>
      <div className={styles.iconCircle} aria-hidden="true">
        {icon}
      </div>
      <p className={styles.title}>{title}</p>
      <p className={styles.message}>{message}</p>
      {actionTitle && onAction ? (
        <button type="button" className={styles.action} onClick={onAction}>
          {actionTitle}
        </button>
      ) : null}
    </div>
  );
}
