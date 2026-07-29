"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import styles from "./BottomNav.module.css";

const TABS = [
  { href: "/", label: "홈", icon: "🏠" },
  { href: "/chat", label: "채팅", icon: "💬" },
  { href: "/search", label: "검색", icon: "🔍" },
  { href: "/diet", label: "식단", icon: "🍽️" },
  { href: "/inbox", label: "인박스", icon: "📥" },
  { href: "/settings", label: "설정", icon: "⚙️" },
] as const;

export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className={styles.nav} aria-label="주 메뉴">
      {TABS.map((tab) => {
        const active = tab.href === "/" ? pathname === "/" : pathname.startsWith(tab.href);
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className={`${styles.item} ${active ? styles.active : ""}`}
            aria-current={active ? "page" : undefined}
          >
            <span className={styles.icon} aria-hidden="true">
              {tab.icon}
            </span>
            <span className={styles.label}>{tab.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
