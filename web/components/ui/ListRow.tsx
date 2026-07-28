import type { ReactNode } from "react";
import Link from "next/link";
import styles from "./ListRow.module.css";

interface ListRowContentProps {
  icon: ReactNode;
  title: string;
  subtitle?: string;
  trailing?: string;
}

function ListRowContent({ icon, title, subtitle, trailing }: ListRowContentProps) {
  return (
    <>
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
    </>
  );
}

type ListRowProps = ListRowContentProps & ({ href: string; onClick?: never } | { href?: never; onClick: () => void });

export function ListRow(props: ListRowProps) {
  const { icon, title, subtitle, trailing } = props;
  const label = subtitle ? `${title}, ${subtitle}` : title;

  if ("href" in props && props.href) {
    return (
      <Link href={props.href} className={styles.row} aria-label={label}>
        <ListRowContent icon={icon} title={title} subtitle={subtitle} trailing={trailing} />
      </Link>
    );
  }

  return (
    <button
      type="button"
      className={styles.row}
      onClick={"onClick" in props ? props.onClick : undefined}
      aria-label={label}
    >
      <ListRowContent icon={icon} title={title} subtitle={subtitle} trailing={trailing} />
    </button>
  );
}
