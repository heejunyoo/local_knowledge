import Foundation

/// Simple body profile for beginners — drives auto kcal/protein + ETA.
public struct DietProfile: Codable, Equatable, Sendable {
    public enum Sex: String, Codable, CaseIterable, Sendable {
        case female = "female"
        case male = "male"

        public var labelKO: String {
            switch self {
            case .female: return "여성"
            case .male: return "남성"
            }
        }
    }

    public enum Activity: String, Codable, CaseIterable, Sendable {
        case sedentary = "sedentary"   // 거의 안 움직임
        case light = "light"           // 주 1–3 운동
        case moderate = "moderate"     // 주 3–5
        case active = "active"         // 주 6–7

        public var labelKO: String {
            switch self {
            case .sedentary: return "거의 안 함"
            case .light: return "조금 (주 1–3회)"
            case .moderate: return "보통 (주 3–5회)"
            case .active: return "많이 (주 6–7회)"
            }
        }

        /// Multiplier on BMR → TDEE
        public var factor: Double {
            switch self {
            case .sedentary: return 1.2
            case .light: return 1.375
            case .moderate: return 1.55
            case .active: return 1.725
            }
        }
    }

    public var heightCm: Double
    public var weightKg: Double
    public var age: Int
    public var sex: Sex
    public var targetWeightKg: Double
    public var activity: Activity

    enum CodingKeys: String, CodingKey {
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case age
        case sex
        case targetWeightKg = "target_weight_kg"
        case activity
    }

    public init(
        heightCm: Double = 165,
        weightKg: Double = 65,
        age: Int = 30,
        sex: Sex = .female,
        targetWeightKg: Double = 60,
        activity: Activity = .light
    ) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.age = age
        self.sex = sex
        self.targetWeightKg = targetWeightKg
        self.activity = activity
    }

    public var isComplete: Bool {
        heightCm > 100 && heightCm < 250
            && weightKg > 30 && weightKg < 300
            && age >= 14 && age <= 100
            && targetWeightKg > 30 && targetWeightKg < 300
    }

    /// Mifflin–St Jeor BMR
    public var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// Maintenance calories
    public var tdee: Double { bmr * activity.factor }

    /// Suggested daily intake for gradual loss (~0.5 kg/week) or mild surplus if gaining.
    public var recommendedKcal: Double {
        let delta = weightKg - targetWeightKg
        if delta > 0.3 {
            // lose: TDEE - 500 (floor 1200 female / 1500 male-ish)
            let floor: Double = sex == .female ? 1200 : 1500
            return max(floor, (tdee - 500).rounded())
        } else if delta < -0.3 {
            return (tdee + 300).rounded()
        }
        return tdee.rounded()
    }

    /// Protein ~1.6 g per kg current body weight (diet-friendly)
    public var recommendedProteinG: Double {
        (weightKg * 1.6).rounded()
    }

    public var recommendedWeeklyWorkouts: Int {
        switch activity {
        case .sedentary: return 3
        case .light: return 3
        case .moderate: return 4
        case .active: return 5
        }
    }

    public var recommendedWorkoutMinutesPerDay: Int {
        switch activity {
        case .sedentary: return 20
        case .light: return 30
        case .moderate: return 40
        case .active: return 45
        }
    }

    /// kg to lose (positive) or gain (negative)
    public var weightDeltaKg: Double { weightKg - targetWeightKg }

    /// ~7700 kcal ≈ 1 kg body fat (rule of thumb)
    public static let kcalPerKg: Double = 7700

    public func planSummary(avgDailyIntakeKcal: Double?, plannedKcal: Double) -> DietPlanProjection {
        let delta = weightDeltaKg
        let goalKcal = plannedKcal > 0 ? plannedKcal : recommendedKcal
        let maintenance = tdee

        // Prefer recent average intake if we have it; else use planned target
        let effectiveIntake = avgDailyIntakeKcal ?? goalKcal
        var dailyDeficit = maintenance - effectiveIntake

        // If user is eating at or above maintenance while wanting loss, use planned deficit
        if delta > 0.3 && dailyDeficit < 100 {
            dailyDeficit = max(100, maintenance - goalKcal)
        }
        // Gain: reverse
        if delta < -0.3 && dailyDeficit > -100 {
            dailyDeficit = min(-100, maintenance - goalKcal)
        }

        let weeks: Double?
        let days: Int?
        let etaText: String
        let paceText: String

        if abs(delta) < 0.3 {
            weeks = 0
            days = 0
            etaText = "목표 체중에 거의 도달했어요. 유지 칼로리로 관리하면 돼요."
            paceText = "유지"
        } else if delta > 0 {
            // lose
            guard dailyDeficit > 50 else {
                return DietPlanProjection(
                    bmr: bmr.rounded(),
                    tdee: maintenance.rounded(),
                    recommendedKcal: recommendedKcal,
                    recommendedProteinG: recommendedProteinG,
                    dailyDeficit: dailyDeficit,
                    weeksToGoal: nil,
                    daysToGoal: nil,
                    etaText: "지금 섭취가 유지 칼로리와 비슷해요. 목표 칼로리(\(Int(goalKcal))kcal)에 맞춰 먹으면 감량이 시작돼요.",
                    paceText: "정체",
                    avgIntakeUsed: avgDailyIntakeKcal
                )
            }
            let totalDeficitNeeded = delta * Self.kcalPerKg
            let d = totalDeficitNeeded / dailyDeficit
            days = max(1, Int(d.rounded()))
            weeks = d / 7
            let wStr = String(format: "%.1f", weeks!)
            etaText = "지금 페이스(하루 약 \(Int(dailyDeficit))kcal 부족)면 약 \(days!)일(\(wStr)주) 뒤 목표 체중 근처예요."
            paceText = "주 \(String(format: "%.2f", dailyDeficit * 7 / Self.kcalPerKg))kg 감량 페이스"
        } else {
            // gain
            let surplus = -dailyDeficit
            guard surplus > 50 else {
                return DietPlanProjection(
                    bmr: bmr.rounded(),
                    tdee: maintenance.rounded(),
                    recommendedKcal: recommendedKcal,
                    recommendedProteinG: recommendedProteinG,
                    dailyDeficit: dailyDeficit,
                    weeksToGoal: nil,
                    daysToGoal: nil,
                    etaText: "증량이 목표인데 섭취가 부족해 보여요. 목표 \(Int(goalKcal))kcal 근처로 올려 보세요.",
                    paceText: "정체",
                    avgIntakeUsed: avgDailyIntakeKcal
                )
            }
            let need = abs(delta) * Self.kcalPerKg
            let d = need / surplus
            days = max(1, Int(d.rounded()))
            weeks = d / 7
            let wStr = String(format: "%.1f", weeks!)
            etaText = "지금 페이스면 약 \(days!)일(\(wStr)주) 뒤 목표 체중 근처예요."
            paceText = "주 \(String(format: "%.2f", surplus * 7 / Self.kcalPerKg))kg 증량 페이스"
        }

        return DietPlanProjection(
            bmr: bmr.rounded(),
            tdee: maintenance.rounded(),
            recommendedKcal: recommendedKcal,
            recommendedProteinG: recommendedProteinG,
            dailyDeficit: dailyDeficit,
            weeksToGoal: weeks,
            daysToGoal: days,
            etaText: etaText,
            paceText: paceText,
            avgIntakeUsed: avgDailyIntakeKcal
        )
    }
}

public struct DietPlanProjection: Equatable, Sendable {
    public var bmr: Double
    public var tdee: Double
    public var recommendedKcal: Double
    public var recommendedProteinG: Double
    public var dailyDeficit: Double
    public var weeksToGoal: Double?
    public var daysToGoal: Int?
    public var etaText: String
    public var paceText: String
    public var avgIntakeUsed: Double?

    public func asDict() -> [String: Any] {
        var d: [String: Any] = [
            "bmr": bmr,
            "tdee": tdee,
            "recommended_kcal": recommendedKcal,
            "recommended_protein_g": recommendedProteinG,
            "daily_deficit": dailyDeficit,
            "eta_text": etaText,
            "pace_text": paceText,
        ]
        if let w = weeksToGoal { d["weeks_to_goal"] = w }
        if let days = daysToGoal { d["days_to_goal"] = days }
        if let a = avgIntakeUsed { d["avg_intake_kcal"] = a }
        return d
    }
}
