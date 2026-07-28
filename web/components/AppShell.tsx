"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { BottomNav } from "./BottomNav";
import styles from "./AppShell.module.css";

const NO_SHELL_PREFIXES = ["/login", "/auth"];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const showNav = !NO_SHELL_PREFIXES.some((prefix) => pathname.startsWith(prefix));

  if (!showNav) {
    return <>{children}</>;
  }

  return (
    <>
      <main className={`${styles.main} ${styles.mainWithNav}`}>{children}</main>
      <BottomNav />
    </>
  );
}
