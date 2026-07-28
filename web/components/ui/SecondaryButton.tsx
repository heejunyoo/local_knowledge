import type { ButtonHTMLAttributes } from "react";
import styles from "./SecondaryButton.module.css";

export function SecondaryButton({
  className,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button type="button" className={`${styles.button} ${className ?? ""}`} {...rest} />;
}
