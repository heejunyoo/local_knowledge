import type { ReactNode } from "react";
import styles from "./Card.module.css";

export function Card({ padded = true, children }: { padded?: boolean; children: ReactNode }) {
  return <div className={`${styles.card} ${padded ? styles.padded : styles.unpadded}`}>{children}</div>;
}
