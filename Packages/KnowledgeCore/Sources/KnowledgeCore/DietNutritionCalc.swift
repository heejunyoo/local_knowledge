import Foundation

/// Approximate nutrition from amount (g / ml) using a small home-use food catalog.
/// Not a full nutrition DB — good enough for daily logging without typing kcal every time.
public enum DietNutritionCalc {
    public enum Unit: String, CaseIterable, Sendable {
        case g
        case ml

        public var label: String { rawValue }
    }

    public struct Food: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        public var aliases: [String]
        /// Preferred unit for this food (g solid / ml liquid).
        public var unit: Unit
        public var kcalPer100: Double
        public var proteinPer100: Double

        public init(
            name: String,
            aliases: [String] = [],
            unit: Unit = .g,
            kcalPer100: Double,
            proteinPer100: Double
        ) {
            self.name = name
            self.aliases = aliases
            self.unit = unit
            self.kcalPer100 = kcalPer100
            self.proteinPer100 = proteinPer100
        }
    }

    public struct Estimate: Equatable, Sendable {
        public var foodName: String
        public var amount: Double
        public var unit: Unit
        public var kcal: Double
        public var proteinG: Double
        public var matchedCatalog: Bool
        public var note: String

        public var itemLine: String {
            let a = amount == amount.rounded() ? "\(Int(amount))" : String(format: "%.1f", amount)
            return "\(foodName) \(a)\(unit.rawValue)"
        }

        public func asDict() -> [String: Any] {
            [
                "food": foodName,
                "amount": amount,
                "unit": unit.rawValue,
                "kcal": kcal.rounded(),
                "protein_g": (proteinG * 10).rounded() / 10,
                "matched": matchedCatalog,
                "note": note,
                "item_line": itemLine,
            ]
        }
    }

    /// Catalog values are approximate per 100 g or 100 ml (home cooking estimates).
    public static let catalog: [Food] = [
        .init(name: "밥·반찬", aliases: ["밥", "흰밥", "공기밥", "집밥", "반찬"], kcalPer100: 173, proteinPer100: 6),
        .init(name: "현미밥", aliases: ["잡곡밥"], kcalPer100: 160, proteinPer100: 3.5),
        .init(name: "샐러드", aliases: [" greensalad"], kcalPer100: 60, proteinPer100: 2.5),
        .init(name: "닭가슴살", aliases: ["닭가슴", "닭살", "chicken breast"], kcalPer100: 110, proteinPer100: 23),
        .init(name: "닭다리", aliases: ["닭정육", "치킨"], kcalPer100: 180, proteinPer100: 18),
        .init(name: "계란", aliases: ["달걀", "egg", "계란프라이", "삶은계란"], kcalPer100: 140, proteinPer100: 12),
        .init(name: "단백질 쉐이크", aliases: ["프로틴", "쉐이크", "protein", "whey"], kcalPer100: 400, proteinPer100: 80),
        .init(name: "두부", aliases: ["순두부"], kcalPer100: 76, proteinPer100: 8),
        .init(name: "돼지고기", aliases: ["삼겹살", "목살", "돼지"], kcalPer100: 240, proteinPer100: 17),
        .init(name: "소고기", aliases: ["한우", "우둔", "국거리"], kcalPer100: 200, proteinPer100: 20),
        .init(name: "생선", aliases: ["고등어", "연어", "참치", "생선구이"], kcalPer100: 150, proteinPer100: 20),
        .init(name: "과일", aliases: ["사과", "바나나", "오렌지", "과일샐러드"], kcalPer100: 53, proteinPer100: 0.7),
        .init(name: "바나나", aliases: [], kcalPer100: 89, proteinPer100: 1.1),
        .init(name: "사과", aliases: [], kcalPer100: 52, proteinPer100: 0.3),
        .init(name: "요거트", aliases: ["그릭요거트", "yogurt"], kcalPer100: 70, proteinPer100: 4),
        .init(name: "그릭요거트", aliases: [], kcalPer100: 97, proteinPer100: 9),
        .init(name: "빵", aliases: ["식빵", "토스트", "베이글"], kcalPer100: 265, proteinPer100: 9),
        .init(name: "라면", aliases: ["컵라면", "인스턴트"], kcalPer100: 450, proteinPer100: 9),
        .init(name: "김치", aliases: [], kcalPer100: 20, proteinPer100: 2),
        .init(name: "치즈", aliases: [], kcalPer100: 350, proteinPer100: 22),
        .init(name: "견과", aliases: ["아몬드", "호두", "땅콩"], kcalPer100: 600, proteinPer100: 20),
        .init(name: "올리브오일", aliases: ["식용유", "기름"], unit: .ml, kcalPer100: 884, proteinPer100: 0),
        .init(name: "커피", aliases: ["아메리카노", "에스프레소", "블랙커피"], unit: .ml, kcalPer100: 2.5, proteinPer100: 0),
        .init(name: "라떼", aliases: ["카페라떼", "밀크커피"], unit: .ml, kcalPer100: 45, proteinPer100: 2.5),
        .init(name: "우유", aliases: ["흰우유", "milk"], unit: .ml, kcalPer100: 42, proteinPer100: 3.4),
        .init(name: "두유", aliases: [], unit: .ml, kcalPer100: 54, proteinPer100: 3.3),
        .init(name: "주스", aliases: ["오렌지주스", "과일주스"], unit: .ml, kcalPer100: 45, proteinPer100: 0.5),
        .init(name: "맥주", aliases: ["소주", "술"], unit: .ml, kcalPer100: 43, proteinPer100: 0.5),
        .init(name: "물", aliases: ["생수", "water"], unit: .ml, kcalPer100: 0, proteinPer100: 0),
        // generic fallbacks (used when name unknown but unit given)
        .init(name: "일반 음식", aliases: ["음식", "meal", "기타"], kcalPer100: 150, proteinPer100: 8),
        .init(name: "음료", aliases: ["드링크", "drink"], unit: .ml, kcalPer100: 30, proteinPer100: 0),
    ]

    // MARK: - Public API

    public static func estimate(
        foodQuery: String,
        amount: Double,
        unit: Unit
    ) -> Estimate? {
        guard amount > 0, amount < 50_000 else { return nil }
        let q = foodQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        if let food = matchFood(q) {
            // If user picks ml for a g-food (or reverse), still scale per 100 of that unit as approximate.
            let factor = amount / 100.0
            let kcal = (food.kcalPer100 * factor * 10).rounded() / 10
            let protein = (food.proteinPer100 * factor * 10).rounded() / 10
            var note = "\(food.name) 기준 약 \(Int(food.kcalPer100.rounded()))kcal/100\(food.unit.rawValue)"
            if food.unit != unit {
                note += " · 단위 \(unit.rawValue)로 환산(대략)"
            }
            return Estimate(
                foodName: food.name,
                amount: amount,
                unit: unit,
                kcal: max(0, kcal),
                proteinG: max(0, protein),
                matchedCatalog: true,
                note: note
            )
        }

        // Unknown food: generic density by unit so user still gets a number they can edit.
        let generic = unit == .ml
            ? catalog.first { $0.name == "음료" }!
            : catalog.first { $0.name == "일반 음식" }!
        let factor = amount / 100.0
        return Estimate(
            foodName: q,
            amount: amount,
            unit: unit,
            kcal: max(0, (generic.kcalPer100 * factor * 10).rounded() / 10),
            proteinG: max(0, (generic.proteinPer100 * factor * 10).rounded() / 10),
            matchedCatalog: false,
            note: "목록에 없는 음식 · \(unit == .ml ? "음료" : "일반 음식") 평균으로 대략 계산. kcal을 직접 고칠 수 있어요."
        )
    }

    /// Parse free text: "닭가슴살 150g", "커피 300ml", "150g 닭가슴살", "우유 200"
    public static func parse(_ text: String, defaultUnit: Unit? = nil) -> Estimate? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // Prefer explicit unit
        let patterns = [
            #"(\d+(?:\.\d+)?)\s*(ml|mL|ML|밀리|밀리리터)"#,
            #"(\d+(?:\.\d+)?)\s*(g|G|그램|그람)"#,
            #"(\d+(?:\.\d+)?)\s*(kg|KG|킬로)"#,
        ]
        for (idx, pat) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                  let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  let numR = Range(m.range(at: 1), in: raw) else { continue }
            var amount = Double(raw[numR]) ?? 0
            var unit: Unit = .g
            if idx == 0 { unit = .ml }
            else if idx == 1 { unit = .g }
            else if idx == 2 {
                unit = .g
                amount *= 1000
            }
            guard amount > 0 else { continue }
            var name = raw
            if let full = Range(m.range(at: 0), in: raw) {
                name.removeSubrange(full)
            }
            name = name
                .replacingOccurrences(of: ",", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // strip common meal slots
            for slot in ["아침", "점심", "저녁", "간식"] {
                name = name.replacingOccurrences(of: slot, with: "")
            }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = unit == .ml ? "음료" : "일반 음식" }
            return estimate(foodQuery: name, amount: amount, unit: unit)
        }

        // No unit: if defaultUnit and trailing number "닭가슴살 150"
        if let def = defaultUnit,
           let re = try? NSRegularExpression(pattern: #"^(.*?)(\d+(?:\.\d+)?)\s*$"#),
           let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let nameR = Range(m.range(at: 1), in: raw),
           let numR = Range(m.range(at: 2), in: raw),
           let amount = Double(raw[numR]), amount > 0 {
            let name = String(raw[nameR]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return estimate(foodQuery: name, amount: amount, unit: def)
            }
        }
        return nil
    }

    /// Scale a preset by amount (e.g. chicken 150g when preset is 100g).
    public static func scalePreset(
        name: String,
        baseGrams: Double,
        baseKcal: Double,
        baseProtein: Double,
        amount: Double,
        unit: Unit
    ) -> Estimate {
        let factor = baseGrams > 0 ? amount / baseGrams : 1
        return Estimate(
            foodName: name,
            amount: amount,
            unit: unit,
            kcal: max(0, (baseKcal * factor * 10).rounded() / 10),
            proteinG: max(0, (baseProtein * factor * 10).rounded() / 10),
            matchedCatalog: true,
            note: "프리셋 분량 \(Int(baseGrams))\(unit.rawValue) 기준 비례"
        )
    }

    public static func matchFood(_ query: String) -> Food? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        // exact name / alias
        for f in catalog {
            if f.name.lowercased() == q { return f }
            if f.aliases.contains(where: { $0.lowercased() == q }) { return f }
        }
        // contains: longest alias/name wins
        var best: Food?
        var bestLen = 0
        for f in catalog {
            let keys = [f.name] + f.aliases
            for k in keys {
                let kl = k.lowercased()
                if kl.count < 2 { continue }
                if q.contains(kl) || kl.contains(q) {
                    if kl.count > bestLen {
                        best = f
                        bestLen = kl.count
                    }
                }
            }
        }
        return best
    }

    public static func catalogNames(for unit: Unit? = nil) -> [String] {
        catalog
            .filter { unit == nil || $0.unit == unit || $0.name == "일반 음식" || $0.name == "음료" }
            .map(\.name)
            .filter { $0 != "일반 음식" && $0 != "음료" }
    }
}
