import Foundation

/// Default serving sizes for quick-add chips (approximate home-use values).
public struct DietMealPreset: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    /// Typical serving weight in grams (or ml for drinks).
    public var grams: Int
    public var kcal: Double
    public var proteinG: Double
    /// Unit label for UI: "g" or "ml"
    public var unit: String

    public init(name: String, grams: Int, kcal: Double, proteinG: Double, unit: String = "g") {
        self.name = name
        self.grams = grams
        self.kcal = kcal
        self.proteinG = proteinG
        self.unit = unit
    }

    /// Chip title e.g. "닭가슴살 100g"
    public var chipTitle: String { "\(name) \(grams)\(unit)" }

    /// Item line stored in meal log
    public var logItem: String { "\(name) \(grams)\(unit)" }

    public static let all: [DietMealPreset] = [
        .init(name: "밥·반찬", grams: 300, kcal: 520, proteinG: 18),
        .init(name: "샐러드", grams: 200, kcal: 120, proteinG: 5),
        .init(name: "닭가슴살", grams: 100, kcal: 110, proteinG: 23),
        .init(name: "계란", grams: 50, kcal: 70, proteinG: 6),
        .init(name: "단백질 쉐이크", grams: 30, kcal: 120, proteinG: 24), // scoop powder
        .init(name: "커피", grams: 200, kcal: 5, proteinG: 0, unit: "ml"),
        .init(name: "과일", grams: 150, kcal: 80, proteinG: 1),
    ]
}

public struct DietWorkoutPreset: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var minutes: Int

    public init(name: String, minutes: Int) {
        self.name = name
        self.minutes = minutes
    }

    public var chipTitle: String { "\(name) \(minutes)분" }

    public static let all: [DietWorkoutPreset] = [
        .init(name: "걷기", minutes: 20),
        .init(name: "계단오르기", minutes: 10),
        .init(name: "러닝", minutes: 30),
        .init(name: "헬스", minutes: 45),
        .init(name: "스트레칭", minutes: 10),
    ]
}
