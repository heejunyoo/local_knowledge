import styles from "./ScreenHeader.module.css";

export function ScreenHeader({
  title,
  subtitle,
  onHome,
}: {
  title: string;
  subtitle?: string;
  onHome?: () => void;
}) {
  return (
    <div className={styles.header}>
      <div className={styles.texts}>
        <h1 className={styles.title}>{title}</h1>
        {subtitle ? <p className={styles.subtitle}>{subtitle}</p> : null}
      </div>
      {onHome ? (
        <button type="button" className={styles.home} onClick={onHome}>
          홈
        </button>
      ) : null}
    </div>
  );
}
