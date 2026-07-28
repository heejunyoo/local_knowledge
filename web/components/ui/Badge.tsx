import styles from "./Badge.module.css";

export type BadgeKind = "info" | "danger" | "neutral";

export function Badge({ children, kind = "info" }: { children: string; kind?: BadgeKind }) {
  return <span className={`${styles.badge} ${styles[kind]}`}>{children}</span>;
}
