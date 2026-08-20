"use client";

import { useEffect, useRef, useState } from "react";
import { callRpc } from "@/lib/rpc/client";
import { MEAL_PRESETS, WORKOUT_PRESETS, scaledMealPreset } from "@/lib/domain/diet-presets";
import { Card, Badge } from "@/components/ui";
import styles from "./page.module.css";

const SLOTS = ["아침", "점심", "저녁", "간식"] as const;
type Slot = (typeof SLOTS)[number];

interface MealDict {
  id: string;
  ts: string;
  items: string[];
  kcal?: number;
  protein_g?: number;
  note?: string;
}
interface WorkoutDict {
  id: string;
  ts: string;
  kind: string;
  minutes: number;
}
interface PlanDict {
  bmr: number;
  tdee: number;
  recommended_kcal: number;
  recommended_protein_g: number;
  eta_text: string;
  pace_text: string;
  avg_intake_kcal?: number;
}
interface ProfileDict {
  height_cm: number;
  weight_kg: number;
  age: number;
  sex: "male" | "female";
  target_weight_kg: number;
  activity: string;
}
interface ProductHit {
  report_no: string;
  name: string;
  maker: string;
  category: string;
  grade: string;
  ratable: boolean;
}
/** diet.preview_product 응답 — 쓰기 없이 환산값만. */
interface ProductPreview {
  found: boolean;
  item_line?: string;
  serving_g?: number | null;
  unit?: string | null;
  kcal?: number;
  protein_g?: number;
  sugar_g?: number;
  sodium_mg?: number;
  satfat_g?: number;
  nutrition_unavailable?: boolean;
}
/** diet.log_product_meal 응답 — 위와 같은 필드 + 저장된 행의 id. */
interface ProductLogResult extends Omit<ProductPreview, "found"> {
  id: string;
}
interface FastingDict {
  active: boolean;
  goal_met?: boolean;
  label: string;
  hint?: string;
  preview_line?: string;
  detail_line?: string;
  progress?: number;
  target_hours: number;
  hour_presets: number[];
  weight_prompt?: string;
  health_reference: { lines: string[] };
}
interface DashboardDict {
  day: {
    date: string;
    meals: MealDict[];
    workouts: WorkoutDict[];
    totals: { kcal: number; protein_g: number; workout_minutes: number };
  };
  goals: { target_kcal: number; target_protein_g: number; weekly_workouts: number; target_workout_minutes_per_day: number };
  progress: { kcal: number; protein: number; workout: number; weekly_workouts: number };
  week: { bars: { date: string; label: string; kcal: number }[]; workout_count: number; workout_minutes: number };
  analysis: string[];
  needs_profile: boolean;
  profile?: ProfileDict;
  plan?: PlanDict;
  fasting: FastingDict;
}

const ACTIVITY_OPTIONS: { value: string; label: string }[] = [
  { value: "sedentary", label: "거의 안 움직임" },
  { value: "light", label: "가벼운 활동" },
  { value: "moderate", label: "보통 활동" },
  { value: "active", label: "활발함" },
];

export default function DietPage() {
  const [dash, setDash] = useState<DashboardDict | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [selectedSlot, setSelectedSlot] = useState<Slot>("점심");
  const [quickLine, setQuickLine] = useState("");
  const [panel, setPanel] = useState<"log" | "week" | "goals" | "profile" | "product" | null>(null);
  const [weightKg, setWeightKg] = useState("");
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  async function refresh() {
    const result = await callRpc<DashboardDict>("diet.dashboard");
    setDash(result);
  }

  useEffect(() => {
    refresh();
  }, []);

  function notify(text: string) {
    setToast(text);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 4000);
  }

  async function runAction(label: string, fn: () => Promise<unknown>) {
    try {
      await fn();
      notify(label);
      await refresh();
    } catch (e) {
      notify(`실패: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  function withSlotPrefix(items: string[]): string[] {
    const text = items.join(" ");
    if (SLOTS.some((s) => text.includes(s))) return items;
    return [`${selectedSlot} ${items[0]}`, ...items.slice(1)];
  }

  async function quickAddMeal(presetIndex: number) {
    const preset = MEAL_PRESETS[presetIndex];
    const scaled = scaledMealPreset(preset, preset.grams);
    await runAction(`${scaled.line} · ~${Math.round(scaled.kcal)}kcal 저장됐어요`, () =>
      callRpc("diet.log_meal", {
        items: withSlotPrefix([scaled.line]),
        kcal: scaled.kcal,
        protein_g: scaled.proteinG,
        note: `기본 ${preset.grams}${preset.unit}`,
      }),
    );
  }

  async function quickAddWorkout(presetIndex: number) {
    const preset = WORKOUT_PRESETS[presetIndex];
    await runAction(`${preset.name} ${preset.minutes}분 저장됐어요`, () =>
      callRpc("diet.log_workout", { kind: preset.name, minutes: preset.minutes }),
    );
  }

  // 한 줄 자유입력 텍스트 → 추정 + 기록. 제품 검색에서 1회량을 못 구한
  // 경우(g 직접 입력)도 이 경로를 그대로 재사용한다 — 새 호출 방식을 만들지 않는다.
  async function logFoodLine(line: string) {
    try {
      const est = await callRpc<{
        matched: boolean;
        source?: "catalog" | "llm" | "generic";
        item_line: string;
        kcal: number;
        protein_g: number;
        note: string;
      }>("diet.estimate_nutrition", { text: line });
      // 카탈로그 매칭분에 더해 LLM 보강분(C3)도 신뢰해 kcal까지 저장한다.
      // source가 "generic"이면 일반식 평균이라 아래 폴백(원문만 저장)으로 넘긴다.
      if (est.matched || est.source === "llm") {
        await runAction(`${est.item_line} · ~${Math.round(est.kcal)}kcal 저장됐어요`, () =>
          callRpc("diet.log_meal", {
            items: withSlotPrefix([est.item_line]),
            kcal: est.kcal,
            protein_g: est.protein_g,
            note: est.note,
          }),
        );
        return;
      }
    } catch {
      // 추정 실패 시 아래 폴백으로 계속
    }
    const kcalMatch = line.match(/(\d+(?:\.\d+)?)\s*kcal/i);
    const kcal = kcalMatch ? parseFloat(kcalMatch[1]) : undefined;
    await runAction("식사 저장됐어요", () =>
      callRpc("diet.log_meal", { items: withSlotPrefix([line]), kcal, note: line }),
    );
  }

  async function commitQuickLine() {
    const line = quickLine.trim();
    if (!line) return;
    setQuickLine("");
    if (line.includes("운동") || line.toLowerCase().includes("workout")) {
      const digits = line.match(/\d+/)?.[0];
      const minutes = digits ? parseInt(digits, 10) : 20;
      const kind = line.replace("운동", "").replace(/\d+\s*분/, "").trim() || "workout";
      await runAction(`운동 ${minutes}분 저장됐어요`, () => callRpc("diet.log_workout", { kind, minutes }));
      return;
    }
    await logFoodLine(line);
  }

  // 담기 전에 환산값만 받아 본다 — 쓰기가 없다. 저장하고 나서 값을 보여준 뒤
  // 틀리면 지우는 모양을 피하려는 것이다(1회량을 모르는 제품에서 특히 나빴다).
  async function previewProduct(
    product: ProductHit,
    quantity: number,
    servingG?: number,
  ): Promise<ProductPreview> {
    return callRpc<ProductPreview>("diet.preview_product", {
      report_no: product.report_no,
      quantity,
      ...(servingG ? { serving_g: servingG } : {}),
    });
  }

  // 미리보기에서 확인한 것과 같은 인자로 기록한다. servingG 는 신고 1회량을
  // 못 구했을 때 사용자가 넣은 값이고, 그때도 환산 기준은 ingreed 의 100g
  // 실측값이다 — LLM 추정으로 바꿔치기하지 않는다(D2).
  async function addProduct(
    product: ProductHit,
    quantity: number,
    servingG?: number,
  ): Promise<ProductLogResult> {
    const result = await callRpc<ProductLogResult>("diet.log_product_meal", {
      report_no: product.report_no,
      quantity,
      ...(servingG ? { serving_g: servingG } : {}),
    });
    notify(
      result.nutrition_unavailable
        ? `${product.name} 저장했어요 · 양을 몰라 영양값은 비어 있어요`
        : `${product.name} ${result.serving_g ?? ""}${result.unit ?? "g"} · ~${Math.round(result.kcal ?? 0)}kcal 저장됐어요`,
    );
    await refresh();
    return result;
  }

  async function deleteMeal(id: string) {
    await runAction("식사 삭제됐어요", () => callRpc("diet.delete_meal", { id }));
  }

  async function deleteWorkout(id: string) {
    await runAction("운동 삭제됐어요", () => callRpc("diet.delete_workout", { id }));
  }

  async function saveMorningWeight() {
    const w = parseFloat(weightKg);
    if (!(w > 30 && w < 300)) {
      notify("체중을 확인해 주세요");
      return;
    }
    await runAction(`공복 ${w.toFixed(1)}kg 저장`, () =>
      callRpc("diet.log_metric", { weight_kg: w, context: "morning_fasted" }),
    );
    setWeightKg("");
  }

  async function pickFastingHours(hours: number) {
    const preview = await callRpc<FastingDict>("diet.fasting.status", { preview_hours: hours });
    setDash((prev) => (prev ? { ...prev, fasting: preview } : prev));
  }

  async function startFast(hours: number) {
    await runAction(`${Math.trunc(hours)}h 단식 시작`, () => callRpc("diet.fasting.start", { target_hours: hours }));
  }

  async function endFast() {
    await runAction("단식 종료", () => callRpc("diet.fasting.end", {}));
  }

  if (!dash) {
    return <div className={styles.section}>불러오는 중…</div>;
  }

  const fasting = dash.fasting;

  return (
    <div>
      <div className={styles.header}>
        <div className={styles.headerTexts}>
          <h1 className={styles.headerTitle}>식단</h1>
          <p className={styles.headerSubtitle}>가볍게, 매일</p>
        </div>
        <button type="button" className={styles.headerLink} onClick={() => setPanel("profile")}>
          내 정보
        </button>
        <button type="button" className={styles.headerLink} onClick={() => setPanel("goals")}>
          목표
        </button>
      </div>

      <div className={styles.section}>
        {dash.plan ? (
          <Card>
            <p className={styles.planEta}>{dash.plan.eta_text}</p>
            <p className={styles.planMeta}>
              기초대사 {Math.round(dash.plan.bmr)} · 유지 {Math.round(dash.plan.tdee)}kcal · 권장 섭취{" "}
              {Math.round(dash.plan.recommended_kcal)}kcal · 단백질 {Math.round(dash.plan.recommended_protein_g)}g
            </p>
            <p className={styles.planPace}>{dash.plan.pace_text}</p>
            <p className={styles.planNote}>규칙 계산 (Mifflin + 적자) · AI API 미사용</p>
          </Card>
        ) : (
          <button type="button" className={styles.ctaCard} onClick={() => setPanel("profile")}>
            <span className={styles.ctaIcon} aria-hidden="true">
              👤
            </span>
            <span style={{ flex: 1 }}>
              <p className={styles.ctaTitle}>건강 정보 입력하기</p>
              <p className={styles.ctaBody}>키·몸무게·나이·성별·목표 체중만 넣으면 칼로리·단백질·도달 시점을 알아서 잡아 줘요.</p>
            </span>
            <span className={styles.chevron} aria-hidden="true">
              ›
            </span>
          </button>
        )}
      </div>

      <div className={styles.section}>
        <Card>
          <p className={styles.sectionLabel}>간헐적 단식</p>
          {fasting.goal_met ? <p className={styles.fastingGoalBadge}>✓ 목표 달성</p> : null}
          <p className={styles.fastingLabel}>{fasting.label}</p>
          {fasting.preview_line ? <p className={styles.fastingPreview}>{fasting.preview_line}</p> : null}
          {!fasting.active ? (
            <>
              <p className={styles.smallNote}>공복 시간</p>
              <div className={styles.chipRow}>
                {fasting.hour_presets.map((h) => (
                  <button
                    key={h}
                    type="button"
                    className={`${styles.chip} ${Math.trunc(fasting.target_hours) === h ? styles.chipActive : ""}`}
                    onClick={() => pickFastingHours(h)}
                  >
                    {h}시간
                  </button>
                ))}
              </div>
            </>
          ) : null}
          {fasting.hint ? <p className={styles.fastingHint}>{fasting.hint}</p> : null}
          {fasting.active && typeof fasting.progress === "number" ? (
            <div className={styles.progressTrack}>
              <div
                className={`${styles.progressFill} ${fasting.goal_met ? styles.progressFillGoalMet : ""}`}
                style={{ width: `${Math.min(1, Math.max(0, fasting.progress)) * 100}%` }}
              />
            </div>
          ) : null}
          <div className={styles.refLines}>
            <p className={styles.smallNote}>참고 정보 (없어도 됨)</p>
            {fasting.health_reference.lines.length === 0 ? (
              <p className={styles.refLine}>건강·식사 참고 없음. 직접 기록만으로 동작해요.</p>
            ) : (
              fasting.health_reference.lines.slice(0, 8).map((line, i) => (
                <p key={i} className={styles.refLine}>
                  · {line}
                </p>
              ))
            )}
          </div>
          {fasting.active ? (
            <button type="button" className={styles.linkAction} onClick={endFast}>
              단식 종료
            </button>
          ) : (
            <button type="button" className={styles.linkAction} onClick={() => startFast(fasting.target_hours)}>
              {Math.trunc(fasting.target_hours)}시간 단식 시작
            </button>
          )}
          <p className={styles.smallNote}>첫 식사 기록 시 단식이 자동 종료돼요.</p>
        </Card>
      </div>

      <div className={styles.section}>
        <Card>
          <p className={styles.sectionLabel}>아침 공복 체중</p>
          <p className={styles.smallNote}>{fasting.weight_prompt ?? "매일 아침 공복에 재면 목표 도달 예상이 안정적이에요."}</p>
          <div className={styles.inlineRow}>
            <input
              className={styles.weightInput}
              type="number"
              placeholder="kg"
              value={weightKg}
              onChange={(e) => setWeightKg(e.target.value)}
            />
            <button type="button" className={styles.linkAction} disabled={!weightKg} onClick={saveMorningWeight}>
              공복 체중 저장
            </button>
          </div>
        </Card>
      </div>

      <div className={styles.section}>
        <Card>
          <p className={styles.sectionLabel}>{dash.day.date}</p>
          <div className={styles.ringRow}>
            <Ring title="칼로리" value={Math.round(dash.day.totals.kcal)} goal={Math.round(dash.goals.target_kcal)} unit="kcal" progress={dash.progress.kcal} color="var(--toss-blue-500)" />
            <Ring title="단백질" value={Math.round(dash.day.totals.protein_g)} goal={Math.round(dash.goals.target_protein_g)} unit="g" progress={dash.progress.protein} color="var(--toss-green-500)" />
            <Ring title="운동" value={dash.day.totals.workout_minutes} goal={dash.goals.target_workout_minutes_per_day} unit="분" progress={dash.progress.workout} color="#f59e0b" />
          </div>
          <p className={styles.smallNote}>% = 오늘 기록 ÷ 목표. 목표는 위 「목표」에서 바꿀 수 있어요.</p>
          <div className={styles.weeklyRow}>
            <span>주간 운동 횟수 (목표 대비)</span>
            <span className={styles.weeklyMeta}>
              {dash.week.workout_count}/{dash.goals.weekly_workouts}회 · {dash.week.workout_minutes}분
            </span>
          </div>
          <div className={styles.progressTrack}>
            <div className={styles.progressFill} style={{ width: `${Math.min(1, Math.max(0, dash.progress.weekly_workouts)) * 100}%` }} />
          </div>
        </Card>
      </div>

      <div className={styles.section}>
        <div className={styles.chipRow}>
          {SLOTS.map((slot) => (
            <button
              key={slot}
              type="button"
              className={`${styles.chip} ${selectedSlot === slot ? styles.chipActive : ""}`}
              onClick={() => setSelectedSlot(slot)}
            >
              {slot}
            </button>
          ))}
        </div>
      </div>

      <div className={styles.section}>
        <Card>
          <p className={styles.sectionLabel}>한 줄로 남기기</p>
          <div className={styles.nlRow}>
            <input
              className={styles.nlInput}
              placeholder={`예: ${selectedSlot} 닭가슴살 150g · 커피 300ml`}
              value={quickLine}
              onChange={(e) => setQuickLine(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") commitQuickLine();
              }}
            />
            <button type="button" className={styles.nlSubmit} disabled={!quickLine.trim()} onClick={commitQuickLine}>
              추가
            </button>
          </div>
          <button type="button" className={styles.linkAction} onClick={() => setPanel("product")}>
            기성식품 검색해서 담기
          </button>
        </Card>
      </div>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>빠른 식사 (기본 분량 · g/ml 비례 kcal)</p>
        <p className={styles.presetSub}>그램은 대략값이에요. 나중에 한 줄로 수정해도 됩니다.</p>
        <div className={styles.presetScroll}>
          {MEAL_PRESETS.map((p, i) => (
            <button key={p.name} type="button" className={styles.presetChip} onClick={() => quickAddMeal(i)}>
              <span className={styles.presetChipTitle}>
                {p.name} {p.grams}
                {p.unit}
              </span>
              <span className={styles.presetChipSub}>
                ~{Math.round(p.kcal)}kcal · P{Math.round(p.proteinG)}g
              </span>
            </button>
          ))}
        </div>
      </div>

      <div className={styles.section}>
        <p className={styles.sectionLabel}>빠른 운동 (기본 시간)</p>
        <div className={styles.presetScroll}>
          {WORKOUT_PRESETS.map((w, i) => (
            <button key={w.name} type="button" className={styles.workoutChip} onClick={() => quickAddWorkout(i)}>
              {w.name} {w.minutes}분
            </button>
          ))}
        </div>
      </div>

      {dash.analysis.slice(0, 3).map((line, i) => (
        <div key={i} className={styles.insightCard}>
          <span aria-hidden="true">💡</span>
          <span className={styles.insightText}>{line}</span>
        </div>
      ))}

      <div className={styles.section}>
        <p className={styles.sectionLabel}>오늘 기록</p>
        <Card padded={false}>
          {dash.day.meals.length === 0 && dash.day.workouts.length === 0 ? (
            <div style={{ padding: "var(--toss-space-6) var(--toss-space-4)", textAlign: "center" }}>
              <p className={styles.ctaTitle}>아직 없어요</p>
              <p className={styles.ctaBody}>끼니 칩이나 한 줄 입력으로 시작해 보세요.</p>
            </div>
          ) : (
            <>
              {dash.day.meals.map((m) => (
                <div key={m.id} className={styles.entryRow}>
                  <span className={styles.entryIcon} aria-hidden="true">
                    🍽️
                  </span>
                  <span className={styles.entryTexts}>
                    <p className={styles.entryTitle}>{m.items.join(", ")}</p>
                    <p className={styles.entrySub}>
                      {[m.kcal != null ? `${Math.round(m.kcal)} kcal` : null, m.protein_g != null ? `P${Math.round(m.protein_g)}g` : null]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                  </span>
                  <button type="button" className={styles.deleteButton} aria-label="삭제" onClick={() => deleteMeal(m.id)}>
                    삭제
                  </button>
                </div>
              ))}
              {dash.day.workouts.map((w) => (
                <div key={w.id} className={styles.entryRow}>
                  <span className={styles.entryIcon} aria-hidden="true">
                    🏃
                  </span>
                  <span className={styles.entryTexts}>
                    <p className={styles.entryTitle}>{w.kind}</p>
                    <p className={styles.entrySub}>{w.minutes}분</p>
                  </span>
                  <button type="button" className={styles.deleteButton} aria-label="삭제" onClick={() => deleteWorkout(w.id)}>
                    삭제
                  </button>
                </div>
              ))}
            </>
          )}
        </Card>
      </div>

      <div className={styles.section}>
        <div className={styles.secondaryRow}>
          <button type="button" className={styles.secondaryButton} onClick={() => setPanel("week")}>
            주간 보기
          </button>
          <button
            type="button"
            className={styles.secondaryButton}
            onClick={() => {
              refresh();
              notify("새로고침했어요");
            }}
          >
            새로고침
          </button>
        </div>
      </div>

      {toast ? (
        <div className={styles.toast}>
          <span className={styles.toastText}>{toast}</span>
          <button type="button" className={styles.toastClose} aria-label="닫기" onClick={() => setToast(null)}>
            ✕
          </button>
        </div>
      ) : null}

      {panel === "week" ? (
        <Panel title="주간" onClose={() => setPanel(null)}>
          <div className={styles.weekBars}>
            {(() => {
              const max = Math.max(...dash.week.bars.map((b) => b.kcal), dash.goals.target_kcal, 1);
              return dash.week.bars.map((bar) => (
                <div key={bar.date} className={styles.weekBarCol}>
                  <span className={styles.weekBarKcal}>{bar.kcal > 0 ? Math.round(bar.kcal) : "·"}</span>
                  <div
                    className={`${styles.weekBarFill} ${bar.date === dash.day.date ? styles.weekBarFillToday : ""}`}
                    style={{ height: `${Math.max(8, (bar.kcal / max) * 120)}px`, width: "100%" }}
                  />
                  <span className={styles.weekBarLabel}>{bar.label}</span>
                </div>
              ));
            })()}
          </div>
          {dash.analysis.map((line, i) => (
            <p key={i} className={styles.weekLine}>
              · {line}
            </p>
          ))}
        </Panel>
      ) : null}

      {panel === "product" ? (
        <ProductPanel
          onClose={() => setPanel(null)}
          onAdd={addProduct}
          onPreview={previewProduct}
        />
      ) : null}

      {panel === "goals" ? (
        <GoalsPanel
          goals={dash.goals}
          onClose={() => setPanel(null)}
          onOpenProfile={() => setPanel("profile")}
          onSave={async (g) => {
            await runAction(`목표 저장됐어요 · ${Math.round(g.target_kcal)}kcal · 단백질 ${Math.round(g.target_protein_g)}g`, () =>
              callRpc("diet.goals.set", g),
            );
            setPanel(null);
          }}
        />
      ) : null}

      {panel === "profile" ? (
        <ProfilePanel
          profile={dash.profile}
          onClose={() => setPanel(null)}
          onSave={async (p) => {
            const result = await callRpc<{ goals: { target_kcal: number; target_protein_g: number } }>("diet.profile.set", p);
            notify(`저장됐어요 · 목표 ${Math.round(result.goals.target_kcal)}kcal · 단백질 ${Math.round(result.goals.target_protein_g)}g`);
            await refresh();
            setPanel(null);
          }}
        />
      ) : null}
    </div>
  );
}

function Ring({
  title,
  value,
  goal,
  unit,
  progress,
  color,
}: {
  title: string;
  value: number;
  goal: number;
  unit: string;
  progress: number;
  color: string;
}) {
  const frac = Math.min(1, Math.max(0, progress));
  const deg = frac * 360;
  return (
    <div className={styles.ringWrap}>
      <div
        className={styles.ringSvgWrap}
        style={{
          borderRadius: "50%",
          background: `conic-gradient(${color} ${deg}deg, var(--toss-grey-200) ${deg}deg 360deg)`,
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 7,
            borderRadius: "50%",
            background: "var(--toss-white)",
          }}
        />
        <div className={styles.ringValue}>
          <span className={styles.ringValueNum}>{value}</span>
          <span className={styles.ringValueUnit}>{unit}</span>
        </div>
      </div>
      <span className={styles.ringTitle}>{title}</span>
      <span className={styles.ringGoal}>
        목표 {goal}
        {unit}
      </span>
      <span className={styles.ringPercent} style={{ color }}>
        {Math.round(frac * 100)}%
      </span>
    </div>
  );
}

function Panel({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <>
      <div className={styles.backdrop} onClick={onClose} />
      <div className={styles.panel}>
        <div className={styles.panelHeader}>
          <h2 className={styles.panelTitle}>{title}</h2>
          <button type="button" className={styles.panelClose} onClick={onClose}>
            닫기
          </button>
        </div>
        {children}
      </div>
    </>
  );
}

function GoalsPanel({
  goals,
  onClose,
  onOpenProfile,
  onSave,
}: {
  goals: DashboardDict["goals"];
  onClose: () => void;
  onOpenProfile: () => void;
  onSave: (g: {
    target_kcal: number;
    target_protein_g: number;
    weekly_workouts: number;
    target_workout_minutes_per_day: number;
  }) => void;
}) {
  const [kcal, setKcal] = useState(String(Math.round(goals.target_kcal)));
  const [protein, setProtein] = useState(String(Math.round(goals.target_protein_g)));
  const [weeklyWO, setWeeklyWO] = useState(String(goals.weekly_workouts));
  const [dayMin, setDayMin] = useState(String(goals.target_workout_minutes_per_day));

  const kcalNum = parseFloat(kcal);
  const proteinNum = parseFloat(protein);
  const valid = kcalNum > 500 && proteinNum > 0;

  return (
    <Panel title="목표" onClose={onClose}>
      <p className={styles.formNote}>
        다이어트 초보라면 「내 정보」에서 키·몸무게만 넣으면 여기 숫자가 자동으로 채워져요. 직접 고쳐도 됩니다.
        <br />
        링의 % = 오늘 기록 ÷ 이 목표
      </p>
      <button type="button" className={styles.linkAction} onClick={onOpenProfile}>
        내 정보로 자동 계산
      </button>

      <div className={styles.formSection}>
        <p className={styles.formSectionTitle}>칼로리</p>
        <input className={styles.formInput} type="number" value={kcal} onChange={(e) => setKcal(e.target.value)} />
        <p className={styles.formNote}>하루 목표 칼로리 (kcal) — 오늘 먹을 열량 목표</p>
      </div>
      <div className={styles.formSection}>
        <p className={styles.formSectionTitle}>단백질</p>
        <input className={styles.formInput} type="number" value={protein} onChange={(e) => setProtein(e.target.value)} />
        <p className={styles.formNote}>하루 목표 단백질 (g)</p>
      </div>
      <div className={styles.formSection}>
        <p className={styles.formSectionTitle}>주간 운동 횟수</p>
        <input className={styles.formInput} type="number" value={weeklyWO} onChange={(e) => setWeeklyWO(e.target.value)} />
        <p className={styles.formNote}>일주일에 운동할 횟수 목표 (주간 바)</p>
      </div>
      <div className={styles.formSection}>
        <p className={styles.formSectionTitle}>하루 운동 시간</p>
        <input className={styles.formInput} type="number" value={dayMin} onChange={(e) => setDayMin(e.target.value)} />
        <p className={styles.formNote}>하루 운동 시간(분) 목표</p>
      </div>
      <button
        type="button"
        className={styles.formSubmit}
        disabled={!valid}
        onClick={() =>
          onSave({
            target_kcal: kcalNum,
            target_protein_g: proteinNum,
            weekly_workouts: parseInt(weeklyWO, 10) || goals.weekly_workouts,
            target_workout_minutes_per_day: parseInt(dayMin, 10) || goals.target_workout_minutes_per_day,
          })
        }
      >
        저장
      </button>
    </Panel>
  );
}

function ProfilePanel({
  profile,
  onClose,
  onSave,
}: {
  profile?: ProfileDict;
  onClose: () => void;
  onSave: (p: {
    height_cm: number;
    weight_kg: number;
    age: number;
    sex: "male" | "female";
    target_weight_kg: number;
    activity: string;
    apply_goals: boolean;
  }) => void;
}) {
  const [height, setHeight] = useState(profile ? String(profile.height_cm) : "165");
  const [weight, setWeight] = useState(profile ? String(profile.weight_kg) : "65");
  const [age, setAge] = useState(profile ? String(profile.age) : "30");
  const [sex, setSex] = useState<"male" | "female">(profile?.sex ?? "female");
  const [target, setTarget] = useState(profile ? String(profile.target_weight_kg) : "60");
  const [activity, setActivity] = useState(profile?.activity ?? "light");

  const h = parseFloat(height);
  const w = parseFloat(weight);
  const a = parseInt(age, 10);
  const t = parseFloat(target);
  const valid = h > 100 && w > 30 && !Number.isNaN(a) && t > 30;

  return (
    <Panel title="내 정보" onClose={onClose}>
      <p className={styles.formNote}>
        키·몸무게·나이·성별·목표 체중을 넣으면 목표 칼로리·단백질을 자동으로 잡고, 지금 먹는 페이스로 언제쯤 목표에 닿을지 알려 줘요.
      </p>
      <div className={styles.formSection}>
        <p className={styles.formSectionTitle}>기본</p>
        <div className={styles.formRow}>
          <label className={styles.formLabel}>키 (cm)</label>
          <input className={styles.formInput} type="number" value={height} onChange={(e) => setHeight(e.target.value)} />
        </div>
        <div className={styles.formRow}>
          <label className={styles.formLabel}>지금 몸무게 (kg)</label>
          <input className={styles.formInput} type="number" value={weight} onChange={(e) => setWeight(e.target.value)} />
        </div>
        <div className={styles.formRow}>
          <label className={styles.formLabel}>나이</label>
          <input className={styles.formInput} type="number" value={age} onChange={(e) => setAge(e.target.value)} />
        </div>
        <div className={styles.formRow}>
          <div className={styles.segmented}>
            <button
              type="button"
              className={`${styles.segmentedButton} ${sex === "female" ? styles.segmentedButtonActive : ""}`}
              onClick={() => setSex("female")}
            >
              여성
            </button>
            <button
              type="button"
              className={`${styles.segmentedButton} ${sex === "male" ? styles.segmentedButtonActive : ""}`}
              onClick={() => setSex("male")}
            >
              남성
            </button>
          </div>
        </div>
      </div>
      <div className={styles.formSection}>
        <p className={styles.formSectionTitle}>목표</p>
        <div className={styles.formRow}>
          <label className={styles.formLabel}>목표 몸무게 (kg)</label>
          <input className={styles.formInput} type="number" value={target} onChange={(e) => setTarget(e.target.value)} />
        </div>
        <div className={styles.formRow}>
          <label className={styles.formLabel}>평소 활동</label>
          <select className={styles.formInput} value={activity} onChange={(e) => setActivity(e.target.value)}>
            {ACTIVITY_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </div>
      </div>
      <button
        type="button"
        className={styles.formSubmit}
        disabled={!valid}
        onClick={() =>
          onSave({
            height_cm: h,
            weight_kg: w,
            age: a,
            sex,
            target_weight_kg: t,
            activity,
            apply_goals: true,
          })
        }
      >
        저장하고 목표 자동 적용
      </button>
    </Panel>
  );
}

function ProductPanel({
  onClose,
  onAdd,
  onPreview,
}: {
  onClose: () => void;
  onAdd: (product: ProductHit, quantity: number, servingG?: number) => Promise<ProductLogResult>;
  onPreview: (product: ProductHit, quantity: number, servingG?: number) => Promise<ProductPreview>;
}) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<"idle" | "searching" | "done">("idle");
  const [hits, setHits] = useState<ProductHit[]>([]);
  const requestId = useRef(0);
  const [selected, setSelected] = useState<ProductHit | null>(null);
  const [qty, setQty] = useState(1);
  const [busy, setBusy] = useState(false);
  /** 담기 전에 보여주는 환산값. 저장 결과가 아니라 미리보기다 — 쓰기가 없다. */
  const [preview, setPreview] = useState<ProductPreview | null>(null);
  const [previewing, setPreviewing] = useState(false);
  const [gramsInput, setGramsInput] = useState("");
  const previewId = useRef(0);

  async function runSearch() {
    const trimmed = query.trim();
    if (!trimmed) {
      setStatus("idle");
      setHits([]);
      return;
    }
    setStatus("searching");
    const myId = ++requestId.current;
    try {
      const res = await callRpc<{ q: string; items: ProductHit[] }>("diet.search_product", { q: trimmed });
      if (myId !== requestId.current) return; // 응답 도착 전에 새 검색이 시작됨
      setHits(res.items ?? []);
      setStatus("done");
    } catch {
      if (myId !== requestId.current) return;
      setHits([]);
      setStatus("done");
    }
  }

  const manualGrams = parseFloat(gramsInput);
  const manualG = manualGrams > 0 ? manualGrams : undefined;

  /** 선택·수량·직접입력이 바뀔 때마다 다시 환산해 보여준다. 저장하지 않는다. */
  async function refreshPreview(product: ProductHit, quantity: number, servingG?: number) {
    const myId = ++previewId.current;
    setPreviewing(true);
    try {
      const p = await onPreview(product, quantity, servingG);
      if (myId !== previewId.current) return; // 더 새 요청이 이미 나갔다
      setPreview(p);
    } catch {
      if (myId !== previewId.current) return;
      setPreview(null);
    } finally {
      if (myId === previewId.current) setPreviewing(false);
    }
  }

  function pick(product: ProductHit) {
    setSelected(product);
    setQty(1);
    setPreview(null);
    setGramsInput("");
    void refreshPreview(product, 1);
  }

  function changeQty(next: number) {
    setQty(next);
    if (selected) void refreshPreview(selected, next, manualG);
  }

  function changeGrams(next: string) {
    setGramsInput(next);
    const g = parseFloat(next);
    if (selected && g > 0) void refreshPreview(selected, qty, g);
  }

  async function handleAdd() {
    if (!selected) return;
    setBusy(true);
    try {
      await onAdd(selected, qty, manualG);
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="제품 검색" onClose={onClose}>
      {!selected ? (
        <>
          <div className={styles.productSearchBar}>
            <input
              className={styles.productSearchInput}
              type="search"
              placeholder="제품 이름으로 검색"
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") runSearch();
              }}
            />
            <button type="button" className={styles.productSearchSubmit} disabled={!query.trim()} onClick={runSearch}>
              검색
            </button>
          </div>

          {status === "searching" ? (
            <p className={styles.productStatusText}>찾는 중…</p>
          ) : status === "done" && hits.length === 0 ? (
            <div className={styles.productEmpty}>
              <p className={styles.ctaTitle}>찾는 제품이 없어요</p>
              <p className={styles.ctaBody}>제품명을 바꿔보거나, 위 「한 줄로 남기기」로 직접 기록해 주세요.</p>
              <button type="button" className={styles.linkAction} onClick={onClose}>
                직접 입력으로 남기기
              </button>
            </div>
          ) : (
            <div className={styles.productList}>
              {hits.map((item) => (
                <button key={item.report_no} type="button" className={styles.productItem} onClick={() => pick(item)}>
                  <span className={styles.productItemTexts}>
                    <p className={styles.productItemTitle}>{item.name}</p>
                    <p className={styles.productItemMeta}>
                      {item.maker} · {item.category}
                    </p>
                  </span>
                  <Badge kind="neutral">{item.grade}</Badge>
                </button>
              ))}
            </div>
          )}
        </>
      ) : (
        <div>
          <div className={styles.productSelectedHeader}>
            <p className={styles.productSelectedTitle}>{selected.name}</p>
            <Badge kind="neutral">{selected.grade}</Badge>
          </div>
          <p className={styles.productSelectedMeta}>
            {selected.maker} · {selected.category}
          </p>

          <div className={styles.qtyRow}>
            <button
              type="button"
              className={styles.qtyButton}
              disabled={qty <= 0.5}
              onClick={() => changeQty(Math.max(0.5, Math.round((qty - 0.5) * 10) / 10))}
            >
              −
            </button>
            <span className={styles.qtyValue}>{qty}배</span>
            <button type="button" className={styles.qtyButton} onClick={() => changeQty(Math.round((qty + 0.5) * 10) / 10)}>
              +
            </button>
          </div>

          {previewing ? (
            <p className={styles.smallNote}>영양값을 불러오는 중…</p>
          ) : preview?.nutrition_unavailable ? (
            <div className={styles.manualGramsRow}>
              <input
                className={styles.manualGramsInput}
                type="number"
                placeholder="먹은 양 (g)"
                value={gramsInput}
                onChange={(e) => changeGrams(e.target.value)}
              />
            </div>
          ) : preview ? (
            <>
              <p className={styles.planEta}>
                {preview.serving_g}
                {preview.unit ?? "g"} · ~{Math.round(preview.kcal ?? 0)}kcal
              </p>
              <p className={styles.smallNote}>
                {[
                  preview.protein_g != null ? `단백질 ${preview.protein_g}g` : null,
                  preview.sugar_g != null ? `당 ${preview.sugar_g}g` : null,
                  preview.sodium_mg != null ? `나트륨 ${preview.sodium_mg}mg` : null,
                  preview.satfat_g != null ? `포화지방 ${preview.satfat_g}g` : null,
                ]
                  .filter(Boolean)
                  .join(" · ")}
              </p>
            </>
          ) : null}

          <button type="button" className={styles.formSubmit} disabled={busy || previewing} onClick={handleAdd}>
            {busy ? "담는 중…" : "담기"}
          </button>
          <button type="button" className={styles.linkAction} onClick={() => setSelected(null)}>
            다른 제품 선택
          </button>
        </div>
      )}
    </Panel>
  );
}
