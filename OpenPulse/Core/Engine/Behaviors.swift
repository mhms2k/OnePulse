import Foundation

/// A habit the user can log in the daily Journal. Answers are given in the morning
/// about the day before, and are matched with that morning's Recovery.
struct Behavior: Identifiable, Hashable {
    enum Category: String, CaseIterable, Hashable {
        case nutrition = "Nutrition"
        case sleep = "Sleep"
        case recovery = "Recovery"
        case lifestyle = "Lifestyle"
        case health = "Health"
    }

    var id: String
    var title: String
    var symbol: String
    var category: Category
    var question: String

    static let catalog: [Behavior] = [
        Behavior(id: "alcohol", title: "Alcohol", symbol: "wineglass", category: .nutrition, question: "Drink alcohol?"),
        Behavior(id: "lateCaffeine", title: "Caffeine after 2 pm", symbol: "cup.and.saucer", category: .nutrition, question: "Have caffeine after 2 pm?"),
        Behavior(id: "lateMeal", title: "Late meal", symbol: "fork.knife", category: .nutrition, question: "Eat within 2 hours of bed?"),
        Behavior(id: "hydrated", title: "Well hydrated", symbol: "drop.fill", category: .nutrition, question: "Drink enough water?"),
        Behavior(id: "sugar", title: "Added sugar", symbol: "birthday.cake", category: .nutrition, question: "Eat a lot of added sugar?"),
        Behavior(id: "screens", title: "Screens in bed", symbol: "iphone", category: .sleep, question: "Use a screen in bed?"),
        Behavior(id: "reading", title: "Read before bed", symbol: "book", category: .sleep, question: "Read before sleeping?"),
        Behavior(id: "sharedBed", title: "Shared bed", symbol: "bed.double", category: .sleep, question: "Share your bed?"),
        Behavior(id: "melatonin", title: "Melatonin", symbol: "pills", category: .sleep, question: "Take melatonin?"),
        Behavior(id: "magnesium", title: "Magnesium", symbol: "capsule", category: .sleep, question: "Take magnesium?"),
        Behavior(id: "stretching", title: "Stretching / mobility", symbol: "figure.flexibility", category: .recovery, question: "Stretch or do mobility work?"),
        Behavior(id: "meditation", title: "Meditation / breathwork", symbol: "brain.head.profile", category: .recovery, question: "Meditate or do breathwork?"),
        Behavior(id: "sauna", title: "Sauna", symbol: "flame", category: .recovery, question: "Use a sauna?"),
        Behavior(id: "cold", title: "Cold exposure", symbol: "snowflake", category: .recovery, question: "Take a cold plunge or shower?"),
        Behavior(id: "massage", title: "Massage", symbol: "hand.raised", category: .recovery, question: "Get a massage?"),
        Behavior(id: "stressed", title: "Felt stressed", symbol: "exclamationmark.bubble", category: .lifestyle, question: "Feel stressed?"),
        Behavior(id: "travel", title: "Travelled", symbol: "airplane", category: .lifestyle, question: "Travel?"),
        Behavior(id: "outdoors", title: "Morning sunlight", symbol: "sun.max", category: .lifestyle, question: "Get sunlight in the morning?"),
        Behavior(id: "sick", title: "Feeling sick", symbol: "thermometer.medium", category: .health, question: "Feel sick?"),
        Behavior(id: "medication", title: "Medication", symbol: "cross.case", category: .health, question: "Take medication?"),
    ]

    static let defaultTracked = ["alcohol", "lateCaffeine", "lateMeal", "hydrated", "screens", "stressed"]

    static func find(_ id: String) -> Behavior? { catalog.first { $0.id == id } }
}

/// One day's journal: behavior id → yes/no.
struct JournalDay: Hashable {
    var answers: [String: Bool]
    var notes: String
    var source: String
}

/// How a behavior relates to next-morning Recovery.
struct BehaviorInsight: Identifiable, Hashable {
    var id: String { behavior.id }
    var behavior: Behavior
    var yesCount: Int
    var noCount: Int
    var recoveryWithYes: Double
    var recoveryWithNo: Double
    /// Percentage points of Recovery on "yes" days compared with "no" days.
    var impact: Double { recoveryWithYes - recoveryWithNo }
}

enum BehaviorAnalyzer {
    /// Like WHOOP: an insight needs at least 5 "yes" and 5 "no" answers within 90 days.
    static let minimumEach = 5
    static let windowDays = 90

    static func insights(journal: [Date: [String: Bool]], scores: [DayScore], now: Date = Date()) -> [BehaviorInsight] {
        let groups = recoveryGroups(journal: journal, scores: scores, now: now)
        var out: [BehaviorInsight] = []
        for b in Behavior.catalog {
            let yesValues = groups.yes[b.id] ?? []
            let noValues = groups.no[b.id] ?? []
            guard yesValues.count >= minimumEach, noValues.count >= minimumEach,
                  let my = Stats.mean(yesValues), let mn = Stats.mean(noValues) else { continue }
            out.append(BehaviorInsight(behavior: b, yesCount: yesValues.count, noCount: noValues.count,
                                       recoveryWithYes: my, recoveryWithNo: mn))
        }
        return out.sorted { abs($0.impact) > abs($1.impact) }
    }

    /// Answer counts per behavior (only days that have a Recovery score), for "x of 5" progress.
    static func counts(journal: [Date: [String: Bool]], scores: [DayScore], now: Date = Date()) -> [String: (yes: Int, no: Int)] {
        let groups = recoveryGroups(journal: journal, scores: scores, now: now)
        var out: [String: (yes: Int, no: Int)] = [:]
        for b in Behavior.catalog {
            out[b.id] = (yes: groups.yes[b.id]?.count ?? 0, no: groups.no[b.id]?.count ?? 0)
        }
        return out
    }

    private static func recoveryGroups(journal: [Date: [String: Bool]], scores: [DayScore], now: Date)
        -> (yes: [String: [Double]], no: [String: [Double]]) {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -windowDays, to: cal.startOfDay(for: now)) ?? now
        var recovery: [Date: Double] = [:]
        for s in scores {
            if let r = s.recovery { recovery[s.day] = r }
        }
        var yesGroups: [String: [Double]] = [:]
        var noGroups: [String: [Double]] = [:]
        for (day, answers) in journal where day >= from {
            guard let r = recovery[cal.startOfDay(for: day)] else { continue }
            for (id, value) in answers {
                if value {
                    yesGroups[id, default: []].append(r)
                } else {
                    noGroups[id, default: []].append(r)
                }
            }
        }
        return (yes: yesGroups, no: noGroups)
    }
}
