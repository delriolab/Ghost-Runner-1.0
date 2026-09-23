import Foundation

// MARK: - Standard times
//
// Every countdown the app can run comes from this file.
// Each entry is t(Routine, Pressure, Hair on fire) in seconds.
//
// To change a time, edit the number. To add a field size, age group, or drill,
// add its name to that sport's list and give it a row in the table.
// The unit tests check that every combination has a time.

enum StandardTimes {
    static let defaultDrill = "Home to 1st"

    static let baseball = SportTimes(
        categoryLabel: "Field size",
        categories: ["40/60 (7U–8U)", "46/65 (9U–10U)", "50/70 (11U–12U)", "60/90 (High school)", "60/90 (College/pro)"],
        defaultCategory: "60/90 (High school)",
        drills: ["Home to 1st", "Home to 2nd", "Home to 3rd", "2nd to Home", "3rd to Home"],
        times: [
            "40/60 (7U–8U)": [
                "Home to 1st": t(4.4, 4.2, 4.0),
                "Home to 2nd": t(7.7, 7.4, 7.1),
                "Home to 3rd": t(12.4, 12.0, 11.6),
                "2nd to Home": t(6.8, 6.4, 6.0),
                "3rd to Home": t(3.5, 3.3, 3.1),
            ],
            "46/65 (9U–10U)": [
                "Home to 1st": t(4.2, 4.0, 3.8),
                "Home to 2nd": t(7.5, 7.2, 6.9),
                "Home to 3rd": t(12.0, 11.6, 11.2),
                "2nd to Home": t(6.5, 6.2, 5.9),
                "3rd to Home": t(3.3, 3.1, 2.9),
            ],
            "50/70 (11U–12U)": [
                "Home to 1st": t(4.3, 4.1, 3.9),
                "Home to 2nd": t(7.6, 7.3, 7.0),
                "Home to 3rd": t(12.1, 11.7, 11.3),
                "2nd to Home": t(6.6, 6.3, 5.9),
                "3rd to Home": t(3.4, 3.2, 3.0),
            ],
            "60/90 (High school)": [
                "Home to 1st": t(4.3, 4.1, 3.9),
                "Home to 2nd": t(7.7, 7.4, 7.1),
                "Home to 3rd": t(12.2, 11.8, 11.4),
                "2nd to Home": t(6.6, 6.3, 6.0),
                "3rd to Home": t(3.4, 3.2, 3.0),
            ],
            "60/90 (College/pro)": [
                "Home to 1st": t(4.2, 4.0, 3.8),
                "Home to 2nd": t(7.4, 7.1, 6.8),
                "Home to 3rd": t(11.7, 11.3, 10.9),
                "2nd to Home": t(6.4, 6.0, 5.6),
                "3rd to Home": t(3.3, 3.1, 2.9),
            ],
        ]
    )

    static let softball = SportTimes(
        categoryLabel: "Age group",
        categories: ["8U–10U", "11U–12U", "13U–14U", "High school", "College/elite"],
        defaultCategory: "High school",
        drills: ["Home to 1st", "Home to 2nd", "Home to 3rd", "2nd to Home", "3rd to Home"],
        times: [
            "8U–10U": [
                "Home to 1st": t(4.4, 4.2, 4.0),
                "Home to 2nd": t(7.8, 7.5, 7.2),
                "Home to 3rd": t(12.4, 12.0, 11.6),
                "2nd to Home": t(6.8, 6.4, 6.1),
                "3rd to Home": t(3.5, 3.3, 3.1),
            ],
            "11U–12U": [
                "Home to 1st": t(4.0, 3.8, 3.6),
                "Home to 2nd": t(7.1, 6.8, 6.5),
                "Home to 3rd": t(11.3, 10.9, 10.5),
                "2nd to Home": t(6.2, 5.8, 5.5),
                "3rd to Home": t(3.2, 3.0, 2.8),
            ],
            "13U–14U": [
                "Home to 1st": t(3.7, 3.5, 3.3),
                "Home to 2nd": t(6.6, 6.3, 5.9),
                "Home to 3rd": t(10.5, 10.0, 9.6),
                "2nd to Home": t(5.7, 5.3, 5.0),
                "3rd to Home": t(2.9, 2.7, 2.5),
            ],
            "High school": [
                "Home to 1st": t(3.5, 3.3, 3.1),
                "Home to 2nd": t(6.2, 5.9, 5.6),
                "Home to 3rd": t(9.9, 9.5, 9.0),
                "2nd to Home": t(5.4, 5.0, 4.7),
                "3rd to Home": t(2.8, 2.6, 2.4),
            ],
            "College/elite": [
                "Home to 1st": t(3.2, 3.0, 2.8),
                "Home to 2nd": t(5.8, 5.5, 5.2),
                "Home to 3rd": t(9.3, 8.9, 8.5),
                "2nd to Home": t(4.9, 4.6, 4.3),
                "3rd to Home": t(2.5, 2.3, 2.2),
            ],
        ]
    )

    static func table(for sport: Sport) -> SportTimes {
        switch sport {
        case .baseball: return baseball
        case .softball: return softball
        }
    }

    /// The countdown for a setup, or nil if the table has no entry for it.
    static func time(sport: Sport, category: String, drill: String, intensity: Intensity) -> Double? {
        table(for: sport).times[category]?[drill]?[intensity]
    }

    private static func t(_ routine: Double, _ pressure: Double, _ hairOnFire: Double) -> TimeSet {
        TimeSet(routine: routine, pressure: pressure, hairOnFire: hairOnFire)
    }
}

// MARK: - Types

enum Sport: String, CaseIterable, Identifiable, Hashable {
    case baseball
    case softball

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum Intensity: String, CaseIterable, Identifiable {
    case routine
    case pressure
    case hairOnFire

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routine: return "Routine"
        case .pressure: return "Pressure"
        case .hairOnFire: return "Hair on fire"
        }
    }
}

struct TimeSet {
    let routine: Double
    let pressure: Double
    let hairOnFire: Double

    subscript(intensity: Intensity) -> Double {
        switch intensity {
        case .routine: return routine
        case .pressure: return pressure
        case .hairOnFire: return hairOnFire
        }
    }
}

struct SportTimes {
    /// Row title on the setup screen, e.g. "Field size" or "Age group"
    let categoryLabel: String
    let categories: [String]
    let defaultCategory: String
    let drills: [String]
    let times: [String: [String: TimeSet]]
}
