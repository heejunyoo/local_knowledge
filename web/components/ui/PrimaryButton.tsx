import type { ButtonHTMLAttributes } from "react";
import styles from "./PrimaryButton.module.css";

export function PrimaryButton({
  className,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button type="button" className={`${styles.button} ${className ?? ""}`} {...rest} />;
}
