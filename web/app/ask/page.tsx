import { Card, ListRow } from "@/components/ui";
import styles from "./page.module.css";

// 묻기 — 내 기록·지식에 질문. 채팅(종합 답변)과 검색(정확 검색)으로 가는
// 두 갈래를 고르게 하는 얇은 갈림길 화면이다. 기능은 각 라우트에 그대로 있다.
export default function AskPage() {
  return (
    <div>
      <h1 className={styles.title}>묻기</h1>
      <p className={styles.subtitle}>어떻게 찾아볼까요?</p>

      <div className={styles.section}>
        <Card padded={false}>
          <ListRow href="/chat" icon="💬" title="채팅" subtitle="대화하며 답을 찾아요" />
          <ListRow href="/search" icon="🔍" title="검색" subtitle="정확한 단어로 찾아요" />
        </Card>
      </div>
    </div>
  );
}
